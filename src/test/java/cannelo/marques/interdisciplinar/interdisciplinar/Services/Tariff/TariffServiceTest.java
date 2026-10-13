package cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffQuote.Status;
import cannelo.marques.interdisciplinar.interdisciplinar.config.TariffProperties;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.TariffUnavailableException;

/**
 * Testes unitários para {@link TariffService} — fonte ÚNICA de tarifa
 * (Enel São Paulo, B1 residencial convencional).
 *
 * <p>Sem Spring context (rápido, determinístico): as properties são
 * construídas manualmente com os defaults embutidos em
 * {@link TariffProperties}.
 *
 * <p>Unidade dos retornos: R$/kWh (BigDecimal). O cálculo de custo do
 * consumo em si é responsabilidade do motor de métricas — aqui validamos a
 * tarifa entregue e o arredondamento monetário (HALF_UP, 2 casas) usado como
 * contrato de apresentação.
 */
class TariffServiceTest {

    private static final LocalDate VALID_FROM = LocalDate.of(2026, 7, 4);
    private static final LocalDate VALID_UNTIL = LocalDate.of(2027, 7, 3);

    private static TariffService serviceWithDefaults() {
        return new TariffService(new TariffProperties());
    }

    // ---- conversão de unidade ----

    @Test
    @DisplayName("conversão: 789.38 R$/MWh ÷ 1000 = 0.78938 R$/kWh")
    void conversao_mwhParaKwh() {
        TariffQuote quote = serviceWithDefaults().getReferenceTariff(VALID_FROM);
        assertEquals(0, new BigDecimal("0.78938").compareTo(quote.tariffPerKwh()));
    }

    @Test
    @DisplayName("metadados: distribuidora, classe, modalidade, vigência, origem e URL preservados")
    void metadados_daCotacao() {
        TariffProperties props = new TariffProperties();
        TariffQuote quote = new TariffService(props).getReferenceTariff(VALID_FROM);

        assertEquals("ENEL_SP", quote.distributor());
        assertEquals("B1_RESIDENCIAL", quote.tariffClass());
        assertEquals("CONVENCIONAL", quote.modality());
        assertEquals(VALID_FROM, quote.validFrom());
        assertEquals(VALID_UNTIL, quote.validUntil());
        assertEquals(props.getSourceUrl(), quote.sourceUrl());
        assertEquals("R$/MWh", quote.originUnit());
    }

    // ---- janela de validade (limites inclusivos) ----

    @Test
    @DisplayName("vigência: 2026-07-04 (validFrom) é VALID — limite inicial inclusivo")
    void vigência_limiteInicialInclusivo() {
        TariffQuote quote = serviceWithDefaults().getReferenceTariff(VALID_FROM);
        assertEquals(Status.VALID, quote.status());
    }

    @Test
    @DisplayName("vigência: 2027-07-03 (validUntil) é VALID — limite final inclusivo")
    void vigência_limiteFinalInclusivo() {
        TariffQuote quote = serviceWithDefaults().getReferenceTariff(VALID_UNTIL);
        assertEquals(Status.VALID, quote.status());
    }

    @Test
    @DisplayName("vigência: 2026-07-03 (um dia antes) é OUTDATED")
    void vigência_umDiaAntesDoInicio() {
        TariffQuote quote = serviceWithDefaults()
            .getReferenceTariff(VALID_FROM.minusDays(1));
        assertEquals(Status.OUTDATED, quote.status());
        // OUTDATED NUNCA afirma ser a tarifa atual nem substitui por outra:
        // a cotação continua sendo a mesma referência, apenas sinalizada.
        assertEquals(0, new BigDecimal("0.78938").compareTo(quote.tariffPerKwh()));
    }

    @Test
    @DisplayName("vigência: 2027-07-04 (um dia depois) é OUTDATED")
    void vigência_umDiaDepoisDoFim() {
        TariffQuote quote = serviceWithDefaults()
            .getReferenceTariff(VALID_UNTIL.plusDays(1));
        assertEquals(Status.OUTDATED, quote.status());
        assertEquals(0, new BigDecimal("0.78938").compareTo(quote.tariffPerKwh()));
    }

    // ---- arredondamento monetário (HALF_UP, 2 casas) ----

    @Test
    @DisplayName("arredondamento: 365 kWh × 0.78938 = 288.12370 → HALF_UP 2 casas = 288.12")
    void arredondamento_custoAnual365kwh() {
        BigDecimal tariffPerKwh =
            serviceWithDefaults().getReferenceTariff(VALID_FROM).tariffPerKwh();

        BigDecimal cost = new BigDecimal("365").multiply(tariffPerKwh);
        // 365 × 0.78938 = 288.12370 (exato)
        assertEquals(0, new BigDecimal("288.12370").compareTo(cost));

        BigDecimal rounded = cost.setScale(2, RoundingMode.HALF_UP);
        assertEquals(0, new BigDecimal("288.12").compareTo(rounded));
    }

    @Test
    @DisplayName("arredondamento: 1460 kWh × 0.78938 = 1152.49480 → HALF_UP 2 casas = 1152.49")
    void arredondamento_custoAnual1460kwh() {
        BigDecimal tariffPerKwh =
            serviceWithDefaults().getReferenceTariff(VALID_FROM).tariffPerKwh();

        BigDecimal cost = new BigDecimal("1460").multiply(tariffPerKwh);
        // 1460 × 0.78938 = 1152.49480 (exato)
        assertEquals(0, new BigDecimal("1152.49480").compareTo(cost));

        BigDecimal rounded = cost.setScale(2, RoundingMode.HALF_UP);
        // OPEN QUESTION histórica (SPEC OQ1): o rascunho da SPEC do DEV
        // indicava 1550.41 para este caso, escrito contra a referência
        // anterior (Enel Rio 1061.10 R$/MWh → 1549.21). Com a referência
        // atual (Enel SP 789.38 R$/MWh, decisão do DEV em 13/10/2026) a
        // fórmula dá 1152.49. O teste valida o cálculo CORRETO a partir da
        // fonte única de tarifa; a revisão do rascunho fica com o DEV.
        assertEquals(0, new BigDecimal("1152.49").compareTo(rounded));
    }

    // ---- indisponibilidade da tarifa ----

    @Test
    @DisplayName("tarifa zerada: lança TariffUnavailableException (nunca retorna null nem inventa valor)")
    void tarifaZerada_lancaExcecao() {
        TariffProperties props = new TariffProperties();
        props.setPublishedValuePerMwh(BigDecimal.ZERO);
        TariffService service = new TariffService(props);

        assertThrows(TariffUnavailableException.class,
            () -> service.getReferenceTariff(VALID_FROM));
    }

    @Test
    @DisplayName("tarifa nula: lança TariffUnavailableException")
    void tarifaNula_lancaExcecao() {
        TariffProperties props = new TariffProperties();
        props.setPublishedValuePerMwh(null);
        TariffService service = new TariffService(props);

        assertThrows(TariffUnavailableException.class,
            () -> service.getReferenceTariff(VALID_FROM));
    }
}
