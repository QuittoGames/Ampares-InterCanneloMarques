package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import java.math.BigDecimal;
import java.math.RoundingMode;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;

/**
 * Funções determinísticas para o cálculo de horas de uso e standby
 * de um produto, baseadas nas fórmulas do coletor Python
 * (energy_collector/collector/normalization.py).
 *
 * <p>Port Java das funções:
 * <ul>
 *   <li>{@code compute_equivalent_hours_year} →
 *       {@link #computeEquivalentHoursYear(BigDecimal, BigDecimal)}</li>
 *   <li>{@code compute_equivalent_hours_year_day} →
 *       {@link #computeEquivalentHoursYearDay(BigDecimal)}</li>
 * </ul>
 *
 * <p>Princípios (espelho do normalizer Python):
 * <ul>
 *   <li>Pura: nenhum efeito colateral, nenhum I/O, sem Spring.</li>
 *   <li>Determinística: mesmos inputs → mesmo output.</li>
 *   <li>Sem inventar valor: entrada ausente ou inválida → {@code null}.</li>
 *   <li>Sem divisão por zero: divisor zero ou ausente → {@code null}.</li>
 * </ul>
 *
 * <p>Semântica usada no domínio:
 * <ul>
 *   <li>{@code avgActiveHours} = horas ativas por dia (do produto ligado)</li>
 *   <li>{@code hoursStandby} = horas em standby por dia (24 − avgActiveHours)</li>
 * </ul>
 */
public final class RegistryCalculator {

    /** Dias em um ano (base para converter horas/ano em horas/dia). */
    private static final BigDecimal DAYS_PER_YEAR = new BigDecimal("365");

    /** Horas em um dia (base para calcular standby = 24 − ativo). */
    private static final BigDecimal HOURS_PER_DAY = new BigDecimal("24");

    /** Escala padrão para resultados fracionários de horas. */
    private static final int HOUR_SCALE = 4;

    /** Fator de conversão de kWh → Wh (kWh × 1000 = Wh). */
    private static final BigDecimal KWH_TO_WH = new BigDecimal("1000");

    private RegistryCalculator() {
    }

    /**
     * Horas equivalentes por ano: {@code H_eq = 1000 * E_year / P}.
     *
     * <p>Port direto de
     * {@code energy_collector.collector.normalization.compute_equivalent_hours_year}.
     *
     * @param avgPowerW       potência média do produto (W); {@code null} se ausente
     * @param annualEnergyKwh energia anual (kWh/ano); {@code null} se ausente
     * @return horas/ano ou {@code null} se algum input ausente ou P ≤ 0
     */
    public static BigDecimal computeEquivalentHoursYear(
            BigDecimal avgPowerW,
            BigDecimal annualEnergyKwh) {
        if (avgPowerW == null || annualEnergyKwh == null) {
            return null;
        }
        if (avgPowerW.signum() <= 0) {
            return null;
        }
        return safeDivide(KWH_TO_WH.multiply(annualEnergyKwh), avgPowerW);
    }

    /**
     * Horas equivalentes por dia: {@code H_eq_day = H_eq / 365}.
     *
     * <p>Port direto de
     * {@code energy_collector.collector.normalization.compute_equivalent_hours_year_day}.
     *
     * @param equivalentHoursYear horas equivalentes por ano; {@code null} se ausente
     * @return horas/dia (arredondado para 4 casas) ou {@code null} se ausente
     */
    public static BigDecimal computeEquivalentHoursYearDay(
            BigDecimal equivalentHoursYear) {
        BigDecimal result = safeDivide(equivalentHoursYear, DAYS_PER_YEAR);
        if (result == null) {
            return null;
        }
        return result.setScale(HOUR_SCALE, RoundingMode.HALF_UP);
    }

    /**
     * Atalhos para o domínio de {@code RegistryUserProduct}.
     *
     * <p>Calcula {@code avgActiveHours} e {@code hoursStandby} diretamente
     * a partir de um {@link Product}, seguindo a mesma lógica do {@code seed.sql}
     * original (que usava thresholds fixos de potência) mas agora com cálculo
     * contínuo e determinístico.
     *
     * <p>Exemplos (validados contra o seed.sql):
     * <ul>
     *   <li>P = 200W, E = 200kWh/ano → ~2.74h ativas/dia, ~21.26h standby/dia</li>
     *   <li>P = 1000W, E = 1460kWh/ano → 4.00h ativas/dia, 20.00h standby/dia
     *       (bate com o threshold "alta potência" do seed.sql)</li>
     * </ul>
     *
     * @param avgPowerW       potência média (W)
     * @param annualEnergyKwh energia anual (kWh/ano)
     * @return array de 2 posições: [0] = avgActiveHours, [1] = hoursStandby.
     *         Qualquer posição pode ser {@code null} se a entrada correspondente
     *         não puder ser calculada.
     */
    public static BigDecimal[] computeDailyHours(
            BigDecimal avgPowerW,
            BigDecimal annualEnergyKwh) {
        BigDecimal eqYear = computeEquivalentHoursYear(avgPowerW, annualEnergyKwh);
        BigDecimal eqDay = computeEquivalentHoursYearDay(eqYear);
        BigDecimal standby = computeHoursStandbyPerDay(eqDay);
        return new BigDecimal[]{eqDay, standby};
    }

    /**
     * Atalhos recebendo um {@link Product} já carregado.
     *
     * <p>Retorna {@code null} para o campo se o produto não tem potência
     * ou energia anual suficientes para o cálculo.
     */
    public static BigDecimal computeAvgActiveHoursPerDay(Product product) {
        if (product == null) {
            return null;
        }
        return computeEquivalentHoursYearDay(
                computeEquivalentHoursYear(
                        product.getAvgPowerW(),
                        product.getAnnualEnergyKwh()
                )
        );
    }

    /**
     * Horas de standby por dia: {@code H_standby = 24 − H_ativo}.
     *
     * <p>Se {@code avgActiveHours} for {@code null} ou estiver fora de
     * {@code [0, 24]}, retorna {@code null} (standby não pode ser negativo
     * nem exceder 24h).
     */
    public static BigDecimal computeHoursStandbyPerDay(BigDecimal avgActiveHours) {
        if (avgActiveHours == null) {
            return null;
        }
        if (avgActiveHours.signum() < 0
                || avgActiveHours.compareTo(HOURS_PER_DAY) > 0) {
            return null;
        }
        return HOURS_PER_DAY.subtract(avgActiveHours)
                .setScale(HOUR_SCALE, RoundingMode.HALF_UP);
    }

    /** Wrapper de {@link #computeHoursStandbyPerDay(BigDecimal)} que recebe um Product. */
    public static BigDecimal computeHoursStandbyPerDay(Product product) {
        return computeHoursStandbyPerDay(computeAvgActiveHoursPerDay(product));
    }

    /**
     * Divisão segura: retorna {@code null} se o denominador for {@code null},
     * zero ou produzir resultado inválido.
     */
    private static BigDecimal safeDivide(BigDecimal numerator, BigDecimal denominator) {
        if (numerator == null || denominator == null) {
            return null;
        }
        if (denominator.signum() == 0) {
            return null;
        }
        try {
            return numerator.divide(denominator, HOUR_SCALE, RoundingMode.HALF_UP);
        } catch (ArithmeticException e) {
            return null;
        }
    }
}
