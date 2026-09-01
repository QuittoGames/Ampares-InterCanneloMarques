package cannelo.marques.interdisciplinar.interdisciplinar.Services.Consumption;

import java.math.BigDecimal;
import java.util.function.Function;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.HoursProvider;

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
 *     P (W) × horas
 * consumo = ─────────────
 *               1000
 * </pre>
 * Onde {@code horas} vem do {@code hoursProvider} (em geral
 * {@code RegistryUserProduct::getAvgActiveHours} ou
 * {@code RegistryUserProduct::getHoursStandby}).
 */
public final class ConsumptionCalculator {

    /** Fator de conversão W → kW. */
    private static final BigDecimal W_TO_KW = new BigDecimal("1000");

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
                .divide(W_TO_KW);
    }
}
