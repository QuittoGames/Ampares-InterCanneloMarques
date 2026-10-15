package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import java.math.BigDecimal;
import java.util.Optional;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;

/**
 * Serviço de métricas de STANDBY (modo espera) — responsabilidade
 * EXCLUSIVA do cálculo de standby.
 *
 * <p><b>Zero fórmula duplicada:</b> toda aritmética delega ao Formula Bank
 * {@link ConsumptionCalculator} ({@code standbyDailyKwh},
 * {@code standbyAnnualKwh}). Este serviço apenas extrai os dados do
 * registro/parâmetros, valida consistência de períodos (via
 * {@link HourService}) e adapta a chamada.
 *
 * <p><b>Fonte da potência de standby:</b>
 * {@link Product#getAvgIdleEnergyForHour()} — atributo DISTINTO da
 * potência ATIVA ({@code avgPowerW}). <b>NUNCA</b> usar a potência ativa
 * como standby.
 *
 * <p><b>Semântica de dados ausentes (decision_004 / SPEC §7):</b>
 * <ul>
 *   <li>potência de standby {@code null} → {@link Optional#empty()}
 *       (não calculável; NUNCA zero);</li>
 *   <li>{@code hoursStandby} {@code null} → {@link Optional#empty()}
 *       (null = desconhecido, nunca vira zero);</li>
 *   <li>potência presente porém ≤ 0, horas fora de [0, 24] ou quantidade
 *       &lt; 1 → {@link InputValidationException} (entrada inválida é
 *       erro explícito, nunca corrigido/clampado).</li>
 * </ul>
 *
 * <p><b>Consistência de períodos:</b> quando {@code avgActiveHours} e
 * {@code hoursStandby} estão ambos presentes, a soma
 * {@code Hactive + Hstandby} deve ser ≤ 24 h/dia — delegado a
 * {@link HourService#totalDailyHours(RegistryUserProduct)}, com
 * {@link InputValidationException} propagando (nunca clamp).
 *
 * <p>Sem dependência de repositório, tarifa ou custo financeiro — custo
 * de standby é responsabilidade de quem o solicitar (Formula Bank tem
 * {@code standbyAnnualCost}, mas este serviço não o expõe).
 */
@Service
public class StandbyMetricsService {

    private final HourService hourService;

    public StandbyMetricsService(HourService hourService) {
        this.hourService = hourService;
    }

    /**
     * Consumo diário de standby a partir dos componentes avulsos.
     *
     * <p>Fórmula (delegada ao Formula Bank):
     * {@code standbyDailyKwh = P_standby (W) × h_standby × q / 1000}.
     *
     * @param standbyPowerW     potência em standby (W); {@code null} → não
     *                          calculável; ≤ 0 → exceção
     * @param standbyHoursPerDay horas em standby por dia; {@code null} →
     *                          não calculável; fora de [0,24] → exceção
     * @param quantity          quantidade de unidades; deve ser ≥ 1
     * @return consumo diário de standby em <b>kWh/dia</b>, ou
     *         {@link Optional#empty()} se a potência ou as horas de
     *         standby forem ausentes (não calculável — nunca zero)
     * @throws InputValidationException se potência/horas/quantidade
     *         presentes forem inválidos
     */
    public Optional<BigDecimal> calculateDailyStandbyKwh(BigDecimal standbyPowerW,
            BigDecimal standbyHoursPerDay, BigDecimal quantity) {
        // Null nunca vira zero: componente ausente = estado não calculável.
        if (standbyPowerW == null || standbyHoursPerDay == null) {
            return Optional.empty();
        }
        return ConsumptionCalculator.standbyDailyKwh(standbyPowerW, standbyHoursPerDay, quantity);
    }

    /**
     * Consumo diário de standby de um registro de associação
     * usuário–produto.
     *
     * <p>Lê {@code Product.avgIdleEnergyForHour} (potência de standby),
     * {@code hoursStandby} e a quantidade do registro; delega à overload
     * de componentes avulsos ({@code q} aplicada UMA vez, pelo Formula
     * Bank).
     *
     * <p>Antes de calcular, valida a consistência de períodos via
     * {@link HourService#totalDailyHours(RegistryUserProduct)}
     * ({@code Hactive + Hstandby ≤ 24 h/dia}); a exceção propaga — o
     * registro nunca é corrigido nem clampado.
     *
     * @param registro registro cujo standby será calculado; {@code null}
     *                 → não calculável
     * @return consumo diário de standby em <b>kWh/dia</b>, ou
     *         {@link Optional#empty()} se o registro for nulo, a potência
     *         de standby for ausente ou {@code hoursStandby} for ausente
     * @throws InputValidationException se a soma de horas exceder 24
     *         h/dia ou os inputs presentes forem inválidos
     */
    public Optional<BigDecimal> calculateDailyStandbyKwh(RegistryUserProduct registro) {
        if (registro == null) {
            return Optional.empty();
        }
        // Consistência de períodos: Hactive + Hstandby ≤ 24 (propaga exceção).
        hourService.totalDailyHours(registro);

        Product product = registro.getProduct();
        BigDecimal standbyPowerW = product == null ? null : product.getAvgIdleEnergyForHour();
        return calculateDailyStandbyKwh(
                standbyPowerW,
                registro.getHoursStandby(),
                BigDecimal.valueOf(registro.getQuantity()));
    }

    /**
     * Consumo ANUAL de standby de um registro — <b>kWh/ano</b> (a
     * interface MetricsService define standby como "Return in Year
     * value").
     *
     * <p>Fórmula (delegada ao Formula Bank):
     * {@code standbyAnnualKwh = standbyDailyKwh × 365}.
     *
     * @param registro registro cujo standby anual será calculado;
     *                 {@code null} → não calculável
     * @return consumo anual de standby em <b>kWh/ano</b>, ou
     *         {@link Optional#empty()} se não calculável (mesmas regras
     *         da overload diária)
     * @throws InputValidationException conforme
     *         {@link #calculateDailyStandbyKwh(RegistryUserProduct)}
     */
    public Optional<BigDecimal> calculateAnnualStandbyKwh(RegistryUserProduct registro) {
        if (registro == null) {
            return Optional.empty();
        }
        hourService.totalDailyHours(registro);
        // Null nunca vira zero: horas de standby ausentes = não calculável
        // (mesmo guarda da overload diária — o motor lançaria exceção).
        if (registro.getHoursStandby() == null) {
            return Optional.empty();
        }

        Product product = registro.getProduct();
        BigDecimal standbyPowerW = product == null ? null : product.getAvgIdleEnergyForHour();
        return ConsumptionCalculator.standbyAnnualKwh(
                standbyPowerW,
                registro.getHoursStandby(),
                BigDecimal.valueOf(registro.getQuantity()));
    }
}
