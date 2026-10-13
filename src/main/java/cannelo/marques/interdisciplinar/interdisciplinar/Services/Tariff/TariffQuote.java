package cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Cotação imutável da tarifa de referência.
 *
 * <p>Unidades:
 * <ul>
 *   <li>{@link #tariffPerKwh()} — <strong>R$/kWh</strong> (unidade de trabalho
 *       do motor de custos, convertida a partir do valor publicado em
 *       {@value #ORIGIN_UNIT}).</li>
 *   <li>{@link #originUnit()} — unidade ORIGINAL em que a tarifa foi publicada
 *       pela distribuidora ({@value #ORIGIN_UNIT}), preservada para auditoria
 *       e rastreabilidade da origem do número.</li>
 * </ul>
 *
 * <p>{@link Status#OUTDATED} significa que a referência está fora da vigência
 * publicada — o sistema sinaliza a desatualização, mas NUNCA afirma que este é
 * o valor vigente nem substitui automaticamente por outra tarifa.
 *
 * @param tariffPerKwh   tarifa em R$/kWh
 * @param distributor    distribuidora (ex.: ENEL_SP)
 * @param tariffClass    classe tarifária (ex.: B1_RESIDENCIAL)
 * @param modality       modalidade (ex.: CONVENCIONAL)
 * @param validFrom      início da vigência (inclusivo)
 * @param validUntil     fim da vigência (inclusivo)
 * @param sourceUrl      documento oficial de referência
 * @param originUnit     unidade original publicada (R$/MWh)
 * @param status         situação da cotação em relação à data consultada
 */
public record TariffQuote(
    BigDecimal tariffPerKwh,
    String distributor,
    String tariffClass,
    String modality,
    LocalDate validFrom,
    LocalDate validUntil,
    String sourceUrl,
    String originUnit,
    Status status
) {

    /** Unidade original da tarifa publicada pela distribuidora. */
    public static final String ORIGIN_UNIT = "R$/MWh";

    /**
     * Situação da cotação em relação à data consultada.
     */
    public enum Status {
        /** Data consultada DENTRO da vigência publicada (limites inclusivos). */
        VALID,
        /** Data consultada FORA da vigência — referência possivelmente desatualizada. */
        OUTDATED
    }
}
