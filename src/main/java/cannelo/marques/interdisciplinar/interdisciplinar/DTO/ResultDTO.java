package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

import java.math.BigDecimal;
import java.util.List;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import jakarta.validation.constraints.NotBlank;

/**
 * Resultado geral do cálculo de consumo do usuário
 * ({@code POST /api/metrics/users/calculate}).
 *
 * <p><b>Unidades (contrato de saída):</b>
 * <ul>
 *   <li>{@link #avgDailyKwh()} — média de <b>consumo diário</b> por
 *       associação válida, em <b>kWh/dia</b> (escala 6, HALF_UP);</li>
 *   <li>{@link #avgUseInYear()} — média de <b>consumo anual</b> por
 *       associação válida, em <b>kWh/ano</b> (escala 6, HALF_UP);</li>
 *   <li>{@link #totalDailyKwh()} — <b>TOTAL diário</b> do usuário em
 *       <b>kWh/dia</b>: Σ dos consumos diários dos registros válidos
 *       (precisão natural do motor {@code ConsumptionCalculator}, sem
 *       arredondamento forçado — é uma soma);</li>
 *   <li>{@link #totalAnnualKwh()} — <b>TOTAL anual</b> do usuário em
 *       <b>kWh/ano</b>: Σ dos consumos anuais dos mesmos registros válidos
 *       (calculados pelo motor, ≡ total diário × 365);</li>
 *   <li>{@link #dailyCost()} — <b>gasto diário</b> em <b>R$/dia</b>
 *       ({@code totalDailyKwh × tarifa R$/kWh}, 2 casas HALF_UP);</li>
 *   <li>{@link #annualCost()} — <b>gasto anual</b> em <b>R$/ano</b>
 *       ({@code totalAnnualKwh × tarifa R$/kWh}, 2 casas HALF_UP).</li>
 * </ul>
 *
 * <p>Os valores monetários derivam da FONTE ÚNICA de tarifa
 * ({@code TariffService}) aplicada sobre o motor de custos
 * {@code ConsumptionCalculator#cost} — nenhuma tarifa é inventada aqui.
 *
 * @param id              identificador do usuário
 * @param name            nome do usuário
 * @param avgDailyKwh     média de consumo diário por associação (kWh/dia)
 * @param avgUseInYear    média de consumo anual por associação (kWh/ano)
 * @param totalDailyKwh   total diário do usuário (kWh/dia)
 * @param totalAnnualKwh  total anual do usuário (kWh/ano)
 * @param dailyCost       gasto diário (R$/dia, 2 casas HALF_UP)
 * @param annualCost      gasto anual (R$/ano, 2 casas HALF_UP)
 * @param productsList    todos os registros do usuário (exibição)
 */
public record ResultDTO(
    @NotBlank
    int id,

    String name,

    @NotBlank
    BigDecimal avgDailyKwh,

    @NotBlank
    BigDecimal avgUseInYear,

    BigDecimal totalDailyKwh,

    BigDecimal totalAnnualKwh,

    BigDecimal dailyCost,

    BigDecimal annualCost,

    List<RegistryUserProduct> productsList

) {
}
