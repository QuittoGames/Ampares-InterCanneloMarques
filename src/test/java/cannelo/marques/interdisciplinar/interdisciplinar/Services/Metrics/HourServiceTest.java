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

import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;

/**
 * Testes unitários para {@link HourService} (DECISION 005).
 *
 * <p>{@code HourService} é um {@code @Service} concreto, mas os testes
 * constroem a instância diretamente (sem Spring context) — rápido e
 * determinístico.
 *
 * <p>Fórmula sob teste (h/dia): {@code Hday = Hactive + Hstandby}.
 * Cobrem: soma simples e borda 24h, zero explícito vs null, null não
 * calculável (nunca zero), componentes inválidos (negativo / >24), soma
 * inconsistente (>24h, sem clamp), a semântica de unidade h/dia e o overload
 * que lê os getters da entidade burra {@code RegistryUserProduct}.
 */
class HourServiceTest {

    private HourService hourService;

    @BeforeEach
    void setUp() {
        hourService = new HourService();
    }

    // =====================================================================
    // Soma válida
    // =====================================================================

    @Nested
    @DisplayName("Soma válida: Hday = Hactive + Hstandby (h/dia)")
    class SomaValida {

        @Test
        @DisplayName("5 + 19 = 24 h/dia (borda: 24 exatos é aceito, limite inclusivo)")
        void somaBorda24h() {
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    new BigDecimal("5"), new BigDecimal("19"));
            assertEquals(0, new BigDecimal("24").compareTo(result.orElseThrow()),
                    "5 + 19 = 24 h/dia deve ser aceito (limite inclusivo)");
        }

        @Test
        @DisplayName("5 + 0 = 5 h/dia (standby zero EXPLÍCITO é válido: zero informado ≠ null)")
        void standbyZeroExplicitoEhValido() {
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    new BigDecimal("5"), BigDecimal.ZERO);
            assertEquals(0, new BigDecimal("5").compareTo(result.orElseThrow()),
                    "standby zero informado é um valor válido, diferente de null");
        }

        @Test
        @DisplayName("soma preserva escala dos operandos (add direto, sem arredondamento)")
        void somaPreservaEscala() {
            // 1.50 + 2.25 = 3.75 (escala 2 preservada); quem exibe arredonda.
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    new BigDecimal("1.50"), new BigDecimal("2.25"));
            assertEquals(0, new BigDecimal("3.75").compareTo(result.orElseThrow()));
            assertEquals(2, result.orElseThrow().scale(),
                    "add() de BigDecimal preserva a escala maior dos operandos");
        }

        @Test
        @DisplayName("unidade: retorno é HORAS/DIA — 2 + 3 = 5 h/dia (não h/mês nem kWh)")
        void unidadeHorasPorDia() {
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    BigDecimal.valueOf(2), BigDecimal.valueOf(3));
            assertEquals(0, BigDecimal.valueOf(5).compareTo(result.orElseThrow()),
                    "resultado é Hday em h/dia, conforme fórmula Hactive + Hstandby");
        }
    }

    // =====================================================================
    // Null → não calculável (null nunca vira zero)
    // =====================================================================

    @Nested
    @DisplayName("Null → Optional.empty() (estado não calculável, nunca zero)")
    class NullNaoCalculavel {

        @Test
        @DisplayName("standbyHours null → Optional.empty() (regra §7: null nunca vira zero)")
        void standbyNullVazio() {
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    new BigDecimal("5"), null);
            assertTrue(result.isEmpty(),
                    "standby null deve ser não calculável, nunca 5 + 0 = 5");
        }

        @Test
        @DisplayName("activeHours null → Optional.empty()")
        void activeNullVazio() {
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    null, new BigDecimal("5"));
            assertTrue(result.isEmpty(),
                    "active null deve ser não calculável, nunca 0 + 5 = 5");
        }

        @Test
        @DisplayName("ambos null → Optional.empty()")
        void ambosNullVazio() {
            assertTrue(hourService.totalDailyHours(null, null).isEmpty());
        }
    }

    // =====================================================================
    // Inconsistência: soma > 24h/dia (sinalizada, nunca clamp)
    // =====================================================================

    @Nested
    @DisplayName("Soma > 24h/dia → InputValidationException (sem clamp silencioso)")
    class SomaInconsistente {

        @Test
        @DisplayName("5 + 20 = 25 h/dia → InputValidationException (excede 24)")
        void somaExcede24h() {
            InputValidationException ex = assertThrows(InputValidationException.class,
                    () -> hourService.totalDailyHours(
                            new BigDecimal("5"), new BigDecimal("20")));
            assertTrue(ex.getMessage().contains("24"),
                    "mensagem deve citar o limite de 24h/dia; obtida: " + ex.getMessage());
        }
    }

    // =====================================================================
    // Validação de componentes: [0, 24] h/dia
    // =====================================================================

    @Nested
    @DisplayName("Componente fora de [0,24] h/dia → InputValidationException")
    class ComponenteInvalido {

        @Test
        @DisplayName("componente negativo (-1 h/dia) → InputValidationException")
        void componenteNegativo() {
            assertThrows(InputValidationException.class,
                    () -> hourService.totalDailyHours(
                            new BigDecimal("-1"), new BigDecimal("5")));
            assertThrows(InputValidationException.class,
                    () -> hourService.totalDailyHours(
                            new BigDecimal("5"), new BigDecimal("-1")));
        }

        @Test
        @DisplayName("componente > 24 h/dia (25 h/dia) → InputValidationException")
        void componenteAcimaDe24h() {
            assertThrows(InputValidationException.class,
                    () -> hourService.totalDailyHours(
                            new BigDecimal("25"), new BigDecimal("0")));
            assertThrows(InputValidationException.class,
                    () -> hourService.totalDailyHours(
                            new BigDecimal("0"), new BigDecimal("25")));
        }

        @Test
        @DisplayName("componente = 24 h/dia exatos é válido (limite inclusivo)")
        void componente24Exatos() {
            Optional<BigDecimal> result = hourService.totalDailyHours(
                    new BigDecimal("24"), BigDecimal.ZERO);
            assertEquals(0, new BigDecimal("24").compareTo(result.orElseThrow()));
        }
    }

    // =====================================================================
    // Overload com RegistryUserProduct (entidade burra; só getters)
    // =====================================================================

    @Nested
    @DisplayName("Overload totalDailyHours(RegistryUserProduct) — entidade burra")
    class OverloadRegistro {

        @Test
        @DisplayName("registro com 4 + 20 → 24 h/dia (lê getAvgActiveHours/getHoursStandby)")
        void registroValido() {
            RegistryUserProduct reg = registryWithHours(
                    new BigDecimal("4"), new BigDecimal("20"));
            Optional<BigDecimal> result = hourService.totalDailyHours(reg);
            assertEquals(0, new BigDecimal("24").compareTo(result.orElseThrow()));
        }

        @Test
        @DisplayName("registro com hoursStandby null → Optional.empty() (null nunca vira zero)")
        void registroStandbyNull() {
            RegistryUserProduct reg = registryWithHours(
                    new BigDecimal("4"), null);
            assertTrue(hourService.totalDailyHours(reg).isEmpty());
        }

        @Test
        @DisplayName("registro com avgActiveHours null → Optional.empty()")
        void registroActiveNull() {
            RegistryUserProduct reg = registryWithHours(
                    null, new BigDecimal("20"));
            assertTrue(hourService.totalDailyHours(reg).isEmpty());
        }

        @Test
        @DisplayName("registro null → Optional.empty() (não calculável)")
        void registroNull() {
            assertTrue(hourService.totalDailyHours((RegistryUserProduct) null).isEmpty());
        }

        @Test
        @DisplayName("registro com soma 5 + 20 = 25 h/dia → InputValidationException")
        void registroSomaExcede24h() {
            RegistryUserProduct reg = registryWithHours(
                    new BigDecimal("5"), new BigDecimal("20"));
            assertThrows(InputValidationException.class,
                    () -> hourService.totalDailyHours(reg));
        }
    }

    // ---- helpers ----

    /**
     * Monta um registro só com as horas relevantes; user/product ficam null
     * pois o cálculo de Hday não os utiliza (entidade burra: só getters).
     */
    private static RegistryUserProduct registryWithHours(
            BigDecimal avgActiveHours, BigDecimal hoursStandby) {
        return new RegistryUserProduct(
                UUID.randomUUID(), null, 1, avgActiveHours, hoursStandby, null);
    }
}
