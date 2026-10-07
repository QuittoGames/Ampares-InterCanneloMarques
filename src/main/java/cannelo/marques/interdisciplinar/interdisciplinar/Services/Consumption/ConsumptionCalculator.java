package cannelo.marques.interdisciplinar.interdisciplinar.Services.Consumption;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.function.Function;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;

/**
 * Função pura de cálculo de consumo energético de um registro
 * {@link RegistryUserProduct}.
 *
 * <p>Port direto (e migração de localização) do método
 * {@code UserService.calculateConsumption(...)} — extraído para esta
 * classe a fim de quebrar a dependência cíclica
 * {@code UserService ↔ ConsumeMetricsService}.
 *
 * <p>Princípios:
 * <ul>
 *   <li>Pura: nenhum estado, nenhum I/O, nenhum bean Spring.</li>
 *   <li>Determinística: mesmos inputs → mesmo output.</li>
 *   <li>Defensiva: inputs inválidos → {@link BigDecimal#ZERO} (não nulo,
 *       para que somatórios em stream não quebrem — comportamento
 *       preservado da versão original).</li>
 * </ul>
 *
 * <p>Fórmula:
 * <pre>
 *     P (W) × horas × quantity
 * consumo = ──────────────────
 *                 1000
 * </pre>
 * Onde {@code horas} vem do {@code hoursProvider} (em geral
 * {@code RegistryUserProduct::getAvgActiveHours} ou
 * {@code RegistryUserProduct::getHoursStandby}).
 */
public final class ConsumptionCalculator {

    /** Fator de conversão W → kW (dividir por 1000). */
    private static final BigDecimal W_TO_KW = new BigDecimal("1000");

    /** Fator de conversão kWh → Wh (multiplicar por 1000). */
    private static final BigDecimal KWH_TO_WH = new BigDecimal("1000");

    /** Dias em um ano (base para converter kWh/ano em horas/dia). */
    private static final BigDecimal DAYS_PER_YEAR = new BigDecimal("365");

    /** Escala padrão para resultados fracionários de horas/dia. */
    private static final int HOUR_SCALE = 4;

    private ConsumptionCalculator() {
    }

    /**
     * Calcula o consumo (kWh) de um {@link RegistryUserProduct} usando as
     * horas fornecidas pelo {@code hoursProvider}.
     *
     * <p>Comportamento defensivo (preservado da versão original):
     * <ul>
     *   <li>{@code userProduct.getProduct() == null} → {@link BigDecimal#ZERO}</li>
     *   <li>{@code userProduct.getProduct().getAvgPowerW() == null} → ZERO</li>
     *   <li>{@code hoursProvider.apply(...) == null} → ZERO</li>
     * </ul>
     *
     * @param userProduct  registro de produto do usuário
     * @param hoursProvider provedor das horas (ex.: {@code RegistryUserProduct::getAvgActiveHours})
     * @return consumo em kWh ou {@link BigDecimal#ZERO} se algum input essencial for ausente
     */
    public static BigDecimal calculate(
            RegistryUserProduct userProduct,
            Function<RegistryUserProduct, BigDecimal> hoursProvider) {

        if (userProduct == null
                || userProduct.getProduct() == null
                || userProduct.getProduct().getAvgPowerW() == null
                || hoursProvider == null) {
            return BigDecimal.ZERO;
        }

        BigDecimal hours = hoursProvider.apply(userProduct);
        if (hours == null) {
            return BigDecimal.ZERO;
        }

        return userProduct.getProduct()
                .getAvgPowerW()
                .multiply(hours)
                .multiply(BigDecimal.valueOf(userProduct.getQuantity()))
                .divide(W_TO_KW);
    }

    /**
     * Calcula as horas ativas por dia a partir da potência média (W) e da
     * energia anual (kWh/ano) de um produto.
     *
     * <p>É a <b>inversa</b> de {@link #calculate(...)}: em vez de converter
     * horas → kWh, reconverte energia em horas/dia:
     * <pre>
     *            E_ano (kWh) × 1000
     * H/dia = ─────────────────────
     *             P (W) × 365
     * </pre>
     *
     * <p>Nenhum valor é inventado: entrada ausente, potência não positiva ou
     * cálculo inválido → {@code null} (incapaz de derivar as horas).
     *
     * @param avgPowerW       potência média do produto (W)
     * @param annualEnergyKwh energia anual do produto (kWh/ano)
     * @return horas ativas por dia (escala 4) ou {@code null} se não calculável
     */
    public static BigDecimal calculateDailyActiveHours(
            BigDecimal avgPowerW,
            BigDecimal annualEnergyKwh) {
        if (avgPowerW == null || annualEnergyKwh == null) {
            return null;
        }
        if (avgPowerW.signum() <= 0) {
            return null;
        }
        try {
            BigDecimal hoursPerYear = annualEnergyKwh
                    .multiply(KWH_TO_WH)
                    .divide(avgPowerW, HOUR_SCALE, RoundingMode.HALF_UP);
            return hoursPerYear
                    .divide(DAYS_PER_YEAR, HOUR_SCALE, RoundingMode.HALF_UP)
                    .setScale(HOUR_SCALE, RoundingMode.HALF_UP);
        } catch (ArithmeticException e) {
            return null;
        }
    }
}
