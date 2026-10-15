package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;

/**
 * Testes unitários para {@link StandbyMetricsService}.
 *
 * <p>Serviço concreto, mas os testes constroem a instância diretamente
 * ({@code new HourService()} real, sem Spring context) — rápido e
 * determinístico, no estilo de {@link HourServiceTest}.
 *
 * <p>Fórmula sob teste (delegada ao Formula Bank
 * {@link ConsumptionCalculator}):
 * {@code standbyDailyKwh = P_standby (W) × h_standby × q / 1000} e
 * {@code standbyAnnualKwh = standbyDailyKwh × 365}. Cobrem: valores
 * válidos (exemplo da spec 2W × 8h × 3 = 0.048 kWh/dia), q aplicada
 * exatamente uma vez, 0 h de standby → ZERO válido (≠ vazio), potência
 * fracionária, precisão decimal, dados ausentes → vazio (null nunca vira
 * zero), entradas inválidas → exceção e consistência de períodos
 * (Hactive + Hstandby ≤ 24 h/dia).
 */
class StandbyMetricsServiceTest {

    private StandbyMetricsService standbyMetricsService;

    @BeforeEach
    void setUp() {
        standbyMetricsService = new StandbyMetricsService(new HourService());
    }

    // =====================================================================
    // Valores válidos — standbyDailyKwh = P_standby × h_standby × q / 1000
    // =====================================================================

    @Nested
    @DisplayName("Valores válidos: standbyDailyKwh = P_standby × h_standby × q / 1000")
    class ValoresValidos {

        @Test
        @DisplayName("exemplo da spec: 2W × 8h × 3 un = 0.048 kWh/dia")
        void exemploDaSpec() {
            Optional<BigDecimal> result = standbyMetricsService.calculateDailyStandbyKwh(
                    new BigDecimal("2"), new BigDecimal("8"), new BigDecimal("3"));

            assertEquals(0, new BigDecimal("0.048").compareTo(result.orElseThrow()),
                    "2 × 8 × 3 / 1000 = 0.048 kWh/dia");
        }

        @Test
        @DisplayName("q > 1 aplicada EXATAMENTE uma vez: 2W × 8h × 3 = 0.048 (não 0.144 nem 0.016)")
        void quantidadeAplicadaUmaVez() {
            BigDecimal result = standbyMetricsService.calculateDailyStandbyKwh(
                    new BigDecimal("2"), new BigDecimal("8"), new BigDecimal("3"))
                    .orElseThrow();

            assertEquals(0, new BigDecimal("0.048").compareTo(result),
                    "q entra uma única vez na fórmula — nem q² nem q ausente");
        }

        @Test
        @DisplayName("0 h de standby → resultado ZERO presente (0 é válido, diferente de vazio)")
        void zeroHorasDeStandbyEhZeroNaoVazio() {
            Optional<BigDecimal> result = standbyMetricsService.calculateDailyStandbyKwh(
                    new BigDecimal("10"), BigDecimal.ZERO, BigDecimal.ONE);

            assertTrue(result.isPresent(), "0 h informado é valor válido, não 'desconhecido'");
            assertEquals(0, BigDecimal.ZERO.compareTo(result.orElseThrow()),
                    "10W × 0h × 1 / 1000 = 0 kWh/dia");
        }

        @Test
        @DisplayName("potência fracionária: 2.5W × 3h × 1 = 0.0075 kWh/dia")
        void potenciaFracionaria() {
            Optional<BigDecimal> result = standbyMetricsService.calculateDailyStandbyKwh(
                    new BigDecimal("2.5"), new BigDecimal("3"), BigDecimal.ONE);

            assertEquals(0, new BigDecimal("0.0075").compareTo(result.orElseThrow()));
        }

        @Test
        @DisplayName("precisão decimal: 3.3W × 7h × 2 = 0.0462 kWh/dia (sem arredondamento intermediário)")
        void precisaoDecimal() {
            Optional<BigDecimal> result = standbyMetricsService.calculateDailyStandbyKwh(
                    new BigDecimal("3.3"), new BigDecimal("7"), new BigDecimal("2"));

            assertEquals(0, new BigDecimal("0.0462").compareTo(result.orElseThrow()),
                    "3.3 × 7 × 2 / 1000 = 0.0462, precisão preservada (DECIMAL128)");
        }
    }

    // =====================================================================
    // Overload RegistryUserProduct — lê avgIdleEnergyForHour e hoursStandby
    // =====================================================================

    @Nested
    @DisplayName("Overload RegistryUserProduct — fonte: Product.avgIdleEnergyForHour")
    class OverloadRegistro {

        @Test
        @DisplayName("registro lê a potência de STANDBY do produto (nunca a ativa) — 2W × 8h × 3 = 0.048")
        void registroUsaPotenciaDeStandbyDoProduto() {
            RegistryUserProduct reg = registry(new BigDecimal("16"), new BigDecimal("8"), 3,
                    new BigDecimal("2"));
            // produto tem avgPowerW=1000 (ativa) — NUNCA deve ser usada como standby

            BigDecimal result = standbyMetricsService.calculateDailyStandbyKwh(reg)
                    .orElseThrow();

            assertEquals(0, new BigDecimal("0.048").compareTo(result),
                    "potência ativa (1000W) jamais substitui a de standby (2W)");
        }

        @Test
        @DisplayName("annual: 0.048 kWh/dia × 365 = 17.52 kWh/ano")
        void annualDeUmRegistro() {
            RegistryUserProduct reg = registry(new BigDecimal("16"), new BigDecimal("8"), 3,
                    new BigDecimal("2"));

            BigDecimal result = standbyMetricsService.calculateAnnualStandbyKwh(reg)
                    .orElseThrow();

            assertEquals(0, new BigDecimal("17.52").compareTo(result),
                    "standbyAnnualKwh = standbyDailyKwh × 365");
        }

        @Test
        @DisplayName("registro nulo → Optional.empty() (não calculável)")
        void registroNulo() {
            assertTrue(standbyMetricsService.calculateDailyStandbyKwh(
                    (RegistryUserProduct) null).isEmpty());
            assertTrue(standbyMetricsService.calculateAnnualStandbyKwh(null).isEmpty());
        }

        @Test
        @DisplayName("registro sem produto → Optional.empty() (não calculável)")
        void registroSemProduto() {
            RegistryUserProduct reg = new RegistryUserProduct(
                    UUID.randomUUID(), null, 1,
                    new BigDecimal("16"), new BigDecimal("8"), null);

            assertTrue(standbyMetricsService.calculateDailyStandbyKwh(reg).isEmpty());
        }
    }

    // =====================================================================
    // Dados ausentes → Optional.empty() (null nunca vira zero)
    // =====================================================================

    @Nested
    @DisplayName("Dados ausentes → Optional.empty() (estado não calculável, nunca zero)")
    class DadosAusentes {

        @Test
        @DisplayName("potência de standby ausente → vazio (NUNCA zero, NUNCA usa a potência ativa)")
        void potenciaDeStandbyAusente() {
            assertTrue(standbyMetricsService.calculateDailyStandbyKwh(
                    null, new BigDecimal("8"), BigDecimal.ONE).isEmpty(),
                    "potência null = desconhecido, não 0 W");
        }

        @Test
        @DisplayName("horas de standby ausentes → vazio (null nunca vira zero)")
        void horasDeStandbyAusentes() {
            assertTrue(standbyMetricsService.calculateDailyStandbyKwh(
                    new BigDecimal("2"), null, BigDecimal.ONE).isEmpty(),
                    "horas null = desconhecido, não 0 h");
        }

        @Test
        @DisplayName("registro com produto sem avgIdleEnergyForHour → vazio (mesmo com potência ativa presente)")
        void registroComProdutoSemPotenciaDeStandby() {
            RegistryUserProduct reg = registry(new BigDecimal("16"), new BigDecimal("8"), 1, null);

            assertTrue(standbyMetricsService.calculateDailyStandbyKwh(reg).isEmpty(),
                    "sem potência de standby o estado é não calculável — nunca a ativa");
            assertTrue(standbyMetricsService.calculateAnnualStandbyKwh(reg).isEmpty());
        }

        @Test
        @DisplayName("registro com hoursStandby null → vazio")
        void registroSemHorasDeStandby() {
            RegistryUserProduct reg = registry(new BigDecimal("16"), null, 1,
                    new BigDecimal("2"));

            assertTrue(standbyMetricsService.calculateDailyStandbyKwh(reg).isEmpty());
            assertTrue(standbyMetricsService.calculateAnnualStandbyKwh(reg).isEmpty());
        }
    }

    // =====================================================================
    // Entradas inválidas → InputValidationException
    // =====================================================================

    @Nested
    @DisplayName("Entradas inválidas → InputValidationException (erro explícito, nunca clamp)")
    class EntradasInvalidas {

        @Test
        @DisplayName("potência de standby negativa → InputValidationException")
        void potenciaNegativa() {
            assertThrows(InputValidationException.class, () ->
                    standbyMetricsService.calculateDailyStandbyKwh(
                            new BigDecimal("-2"), new BigDecimal("8"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("potência de standby zero → InputValidationException (deve ser > 0)")
        void potenciaZero() {
            assertThrows(InputValidationException.class, () ->
                    standbyMetricsService.calculateDailyStandbyKwh(
                            BigDecimal.ZERO, new BigDecimal("8"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("horas de standby negativas → InputValidationException")
        void horasNegativas() {
            assertThrows(InputValidationException.class, () ->
                    standbyMetricsService.calculateDailyStandbyKwh(
                            new BigDecimal("2"), new BigDecimal("-8"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("horas de standby acima de 24 → InputValidationException")
        void horasAcimaDe24() {
            assertThrows(InputValidationException.class, () ->
                    standbyMetricsService.calculateDailyStandbyKwh(
                            new BigDecimal("2"), new BigDecimal("25"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("quantidade = 0 → InputValidationException (q deve ser >= 1)")
        void quantidadeZero() {
            assertThrows(InputValidationException.class, () ->
                    standbyMetricsService.calculateDailyStandbyKwh(
                            new BigDecimal("2"), new BigDecimal("8"), BigDecimal.ZERO));
        }

        @Test
        @DisplayName("quantidade negativa → InputValidationException")
        void quantidadeNegativa() {
            assertThrows(InputValidationException.class, () ->
                    standbyMetricsService.calculateDailyStandbyKwh(
                            new BigDecimal("2"), new BigDecimal("8"), new BigDecimal("-1")));
        }

        @Test
        @DisplayName("horas de standby inválidas no REGISTRO (30h) → exceção propaga")
        void horasInvalidasNoRegistro() {
            RegistryUserProduct reg = registry(new BigDecimal("5"), new BigDecimal("30"), 1,
                    new BigDecimal("2"));

            assertThrows(InputValidationException.class,
                    () -> standbyMetricsService.calculateDailyStandbyKwh(reg));
            assertThrows(InputValidationException.class,
                    () -> standbyMetricsService.calculateAnnualStandbyKwh(reg));
        }
    }

    // =====================================================================
    // Consistência de períodos — Hactive + Hstandby ≤ 24 h/dia (HourService)
    // =====================================================================

    @Nested
    @DisplayName("Consistência de períodos: Hactive + Hstandby ≤ 24 h/dia (sem clamp)")
    class ConsistenciaDePeriodos {

        @Test
        @DisplayName("5h ativas + 20h standby = 25 h/dia → InputValidationException")
        void somaExcede24h() {
            RegistryUserProduct reg = registry(new BigDecimal("5"), new BigDecimal("20"), 1,
                    new BigDecimal("2"));

            InputValidationException ex = assertThrows(InputValidationException.class,
                    () -> standbyMetricsService.calculateDailyStandbyKwh(reg));
            assertTrue(ex.getMessage().contains("24"),
                    "mensagem deve citar o limite de 24h/dia; obtida: " + ex.getMessage());
        }

        @Test
        @DisplayName("5h ativas + 19h standby = 24 h/dia exatos é aceito (limite inclusivo)")
        void somaExatamente24h() {
            RegistryUserProduct reg = registry(new BigDecimal("5"), new BigDecimal("19"), 1,
                    new BigDecimal("2"));

            BigDecimal result = standbyMetricsService.calculateDailyStandbyKwh(reg)
                    .orElseThrow();

            assertEquals(0, new BigDecimal("0.038").compareTo(result),
                    "2W × 19h × 1 / 1000 = 0.038 kWh/dia");
        }

        @Test
        @DisplayName("soma inconsistente também bloqueia o ANNUAL (mesma validação)")
        void somaInconsistenteNoAnnual() {
            RegistryUserProduct reg = registry(new BigDecimal("16"), new BigDecimal("9"), 1,
                    new BigDecimal("2"));

            assertThrows(InputValidationException.class,
                    () -> standbyMetricsService.calculateAnnualStandbyKwh(reg));
        }
    }

    // ---- helpers ----

    /**
     * Monta um registro com um produto que tem potência ATIVA fixa (1000W,
     * para provar que nunca é usada como standby) e a potência de standby
     * informada (null = ausente). User fica null (não utilizado pelo
     * cálculo de standby).
     */
    private static RegistryUserProduct registry(BigDecimal avgActiveHours, BigDecimal hoursStandby,
            int quantity, BigDecimal standbyPowerW) {
        Product product = new Product(
                UUID.randomUUID(), "Nome", "Brand", "Model", "electronics", "sub",
                new BigDecimal("1000"), new BigDecimal("100"));
        product.setAvgIdleEnergyForHour(standbyPowerW);
        return new RegistryUserProduct(
                UUID.randomUUID(), null, quantity, avgActiveHours, hoursStandby, product);
    }
}
