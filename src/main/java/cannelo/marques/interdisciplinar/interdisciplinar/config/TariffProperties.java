package cannelo.marques.interdisciplinar.interdisciplinar.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * FONTE ÚNICA de tarifa elétrica do projeto — tarifa residencial B1 da
 * Enel Distribuição São Paulo (área de concessão de São Paulo).
 *
 * <p>Todos os custos estimados do motor de consumo devem derivar destas
 * properties. É proibido criar segunda fonte de tarifa, média nacional ou
 * valor alternativo em outro ponto do código.
 *
 * <p>Os valores abaixo são os DEFAULTS EMBUTIDOS EM CÓDIGO (a tarifa publicada
 * não depende de configuração de ambiente para funcionar). As chaves
 * {@code ampares.energy.tariff.*} são <strong>opcionais</strong> e servem
 * apenas para override em {@code application.properties}/env quando a tarifa
 * publicada for atualizada — não são exigidas para a aplicação rodar.
 *
 * <p>Chaves opcionais de override:
 * <ul>
 *   <li>{@code ampares.energy.tariff.distributor} — distribuidora (padrão {@code ENEL_SP})</li>
 *   <li>{@code ampares.energy.tariff.tariff-class} — classe tarifária (padrão {@code B1_RESIDENCIAL})</li>
 *   <li>{@code ampares.energy.tariff.modality} — modalidade (padrão {@code CONVENCIONAL})</li>
 *   <li>{@code ampares.energy.tariff.published-value-per-mwh} — valor publicado em R$/MWh (padrão {@code 789.38})</li>
 *   <li>{@code ampares.energy.tariff.valid-from} — início da vigência (padrão {@code 2026-07-04})</li>
 *   <li>{@code ampares.energy.tariff.valid-until} — fim da vigência (padrão {@code 2027-07-03})</li>
 *   <li>{@code ampares.energy.tariff.source-url} — URL do documento oficial de referência</li>
 * </ul>
 *
 * <p>Unidades: {@link #getPublishedValuePerMwh()} é a unidade ORIGINAL
 * publicada pela distribuidora ({@value #UNIT_PUBLISHED}); a conversão para
 * {@code R$/kWh} é feita por {@code TariffService}
 * ({@value #UNIT_PUBLISHED} ÷ 1000 = R$/kWh).
 *
 * <p>Nota: {@code application.properties} está sob escopo humano ativo —
 * estas properties NÃO foram adicionadas lá; os defaults vivem em código.
 */
@ConfigurationProperties(prefix = "ampares.energy.tariff")
public class TariffProperties {

    /** Unidade original da tarifa publicada ({@value}). */
    public static final String UNIT_PUBLISHED = "R$/MWh";

    /** Unidade de trabalho do motor de custos ({@value}). */
    public static final String UNIT_PER_KWH = "R$/kWh";

    /** 1 MWh = 1000 kWh — divisor da conversão de unidade. */
    public static final BigDecimal MWH_TO_KWH_DIVISOR = new BigDecimal("1000");

    private String distributor = "ENEL_SP";

    private String tariffClass = "B1_RESIDENCIAL";

    private String modality = "CONVENCIONAL";

    /**
     * Valor publicado pela Enel São Paulo em R$/MWh — B1 residencial
     * convencional da Resolução Homologatória ANEEL nº 3.596/2026
     * (TUSD 472,42 + TE 316,96 = 789,38 R$/MWh), válida a partir de 04/07/2026.
     */
    private BigDecimal publishedValuePerMwh = new BigDecimal("789.38");

    /** Início da vigência da tarifa publicada (inclusivo). */
    private LocalDate validFrom = LocalDate.of(2026, 7, 4);

    /**
     * Fim da vigência da tarifa publicada (inclusivo) — janela de 1 ano até o
     * próximo reajuste tarifário anual esperado (~jun/jul 2027). Fora dela a
     * cotação é sinalizada como {@code OUTDATED}, nunca substituída.
     */
    private LocalDate validUntil = LocalDate.of(2027, 7, 3);

    /** Documento oficial de onde o valor foi extraído. */
    private String sourceUrl = "https://www.enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html";

    public String getDistributor() {
        return distributor;
    }

    public void setDistributor(String distributor) {
        this.distributor = distributor;
    }

    public String getTariffClass() {
        return tariffClass;
    }

    public void setTariffClass(String tariffClass) {
        this.tariffClass = tariffClass;
    }

    public String getModality() {
        return modality;
    }

    public void setModality(String modality) {
        this.modality = modality;
    }

    public BigDecimal getPublishedValuePerMwh() {
        return publishedValuePerMwh;
    }

    public void setPublishedValuePerMwh(BigDecimal publishedValuePerMwh) {
        this.publishedValuePerMwh = publishedValuePerMwh;
    }

    public LocalDate getValidFrom() {
        return validFrom;
    }

    public void setValidFrom(LocalDate validFrom) {
        this.validFrom = validFrom;
    }

    public LocalDate getValidUntil() {
        return validUntil;
    }

    public void setValidUntil(LocalDate validUntil) {
        this.validUntil = validUntil;
    }

    public String getSourceUrl() {
        return sourceUrl;
    }

    public void setSourceUrl(String sourceUrl) {
        this.sourceUrl = sourceUrl;
    }
}
