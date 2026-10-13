package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;

/**
 * Testes unitários para {@link ConsumptionCalculator}.
 *
 * <p>Função pura → testes sem Spring context (rápido, determinístico).
 *
 * <p>Cobrem o Formula Bank (BigDecimal): dailyKwh, monthlyKwh,
 * averageMonthKwh, annualKwh, source*, cost, standby*, inverseDailyHours,
 * incluindo a consistência F1↔F7 (ida e volta consumo ↔ horas).
 */
class ConsumptionCalculatorTest {

    /** Tarifa Enel SP (B1 residencial) de referência nos cenários (R$/kWh). */
    private static final BigDecimal TARIFF = new BigDecimal("0.78938");

    // =====================================================================
    // Cenário A — P=100W, h_d=5, q=2
    // =====================================================================

    @Nested
    @DisplayName("Cenário A: 100W × 5h/dia × 2 unidades")
    class CenarioA {

        @Test
        @DisplayName("dailyKwh: 100 × 5 × 2 / 1000 = 1 kWh/dia")
        void dailyKwh() {
            BigDecimal result = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("100"), new BigDecimal("5"), new BigDecimal("2"));
            assertEquals(0, BigDecimal.ONE.compareTo(result));
        }

        @Test
        @DisplayName("annualKwh: 1 kWh/dia × 365 = 365 kWh/ano")
        void annualKwh() {
            BigDecimal daily = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("100"), new BigDecimal("5"), new BigDecimal("2"));
            BigDecimal result = ConsumptionCalculator.annualKwh(daily);
            assertEquals(0, new BigDecimal("365").compareTo(result));
        }

        @Test
        @DisplayName("cost anual: 365 × 0.78938 = 288.12370 → HALF_UP 2 casas → R$ 288.12")
        void costAnual() {
            BigDecimal annual = new BigDecimal("365");
            BigDecimal result = ConsumptionCalculator.cost(annual, TARIFF);
            assertEquals(0, new BigDecimal("288.12").compareTo(result));
            assertEquals(2, result.scale());
        }
    }

    // =====================================================================
    // Cenário B — P=1000W, h_d=2, q=2
    // =====================================================================

    @Nested
    @DisplayName("Cenário B: 1000W × 2h/dia × 2 unidades")
    class CenarioB {

        @Test
        @DisplayName("dailyKwh: 1000 × 2 × 2 / 1000 = 4 kWh/dia")
        void dailyKwh() {
            BigDecimal result = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("1000"), new BigDecimal("2"), new BigDecimal("2"));
            assertEquals(0, new BigDecimal("4").compareTo(result));
        }

        @Test
        @DisplayName("annualKwh: 4 kWh/dia × 365 = 1460 kWh/ano")
        void annualKwh() {
            BigDecimal daily = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("1000"), new BigDecimal("2"), new BigDecimal("2"));
            BigDecimal result = ConsumptionCalculator.annualKwh(daily);
            assertEquals(0, new BigDecimal("1460").compareTo(result));
        }

        @Test
        @DisplayName("cost anual: 1460 × 0.78938 = 1152.49480 → HALF_UP 2 casas → R$ 1152.49")
        void costAnual() {
            // OPEN QUESTION histórica (SPEC OQ1): o rascunho do DEV indicava
            // R$ 1550.41, escrito contra a referência anterior (Enel Rio
            // 1061.10 R$/MWh → calculado 1549.21). Com a referência atual
            // (Enel SP 789.38 R$/MWh, decisão do DEV em 13/10/2026) a fórmula
            // dá 1152.49. NÃO forçamos o rascunho — a fórmula é a autoridade
            // e a divergência segue registrada como open question.
            BigDecimal annual = new BigDecimal("1460");
            BigDecimal result = ConsumptionCalculator.cost(annual, TARIFF);
            assertEquals(0, new BigDecimal("1152.49").compareTo(result));
            assertEquals(2, result.scale());
        }
    }

    // =====================================================================
    // Cenário C — validações, estados não calculáveis e arredondamento
    // =====================================================================

    @Nested
    @DisplayName("Cenário C: validações do motor")
    class CenarioC {

        @Test
        @DisplayName("dailyKwh: horas negativas → InputValidationException")
        void horasNegativas() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(
                            new BigDecimal("100"), new BigDecimal("-1"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("dailyKwh: horas > 24 → InputValidationException")
        void horasAcimaDe24() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(
                            new BigDecimal("100"), new BigDecimal("25"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("dailyKwh: 24h exatas é válido (limite inclusivo)")
        void horas24Exatas() {
            BigDecimal result = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("100"), new BigDecimal("24"), BigDecimal.ONE);
            assertEquals(0, new BigDecimal("2.4").compareTo(result));
        }

        @Test
        @DisplayName("dailyKwh: quantidade < 1 → InputValidationException")
        void quantidadeInvalida() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(
                            new BigDecimal("100"), new BigDecimal("5"), new BigDecimal("0.5")));
        }

        @Test
        @DisplayName("dailyKwh: potência negativa → InputValidationException")
        void potenciaNegativa() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(
                            new BigDecimal("-100"), new BigDecimal("5"), BigDecimal.ONE));
        }

        @Test
        @DisplayName("dailyKwh: null → InputValidationException (nunca ZERO silencioso)")
        void nullExplcito() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(null, new BigDecimal("5"), BigDecimal.ONE));
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(new BigDecimal("100"), null, BigDecimal.ONE));
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.dailyKwh(new BigDecimal("100"), new BigDecimal("5"), null));
        }

        @Test
        @DisplayName("standbyDailyKwh: potência de standby null → estado não calculável (Optional vazio)")
        void standbySemPotenciaNaoCalculavel() {
            Optional<BigDecimal> result = ConsumptionCalculator.standbyDailyKwh(
                    null, new BigDecimal("20"), BigDecimal.ONE);
            assertTrue(result.isEmpty(),
                    "standby sem potência deve ser não calculável, nunca zero nem potência ativa");
        }

        @Test
        @DisplayName("standbyAnnualKwh/cost: null na potência → vazio; com potência → valores")
        void standbyAnual() {
            assertTrue(ConsumptionCalculator.standbyAnnualKwh(
                    null, new BigDecimal("20"), BigDecimal.ONE).isEmpty());
            assertTrue(ConsumptionCalculator.standbyAnnualCost(
                    null, new BigDecimal("20"), BigDecimal.ONE, TARIFF).isEmpty());

            // 10W standby × 20h × 2 unid / 1000 = 0.4 kWh/dia → × 365 = 146 kWh/ano
            Optional<BigDecimal> annual = ConsumptionCalculator.standbyAnnualKwh(
                    new BigDecimal("10"), new BigDecimal("20"), new BigDecimal("2"));
            assertEquals(0, new BigDecimal("146").compareTo(annual.orElseThrow()));

            Optional<BigDecimal> cost = ConsumptionCalculator.standbyAnnualCost(
                    new BigDecimal("10"), new BigDecimal("20"), new BigDecimal("2"), TARIFF);
            // 146 × 0.78938 = 115.24948 → HALF_UP → R$ 115.25
            assertEquals(0, new BigDecimal("115.25").compareTo(cost.orElseThrow()));
        }

        @Test
        @DisplayName("inverseDailyHours: potência zero → InputValidationException (divisão por zero)")
        void inversaPotenciaZero() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.inverseDailyHours(
                            new BigDecimal("1460"), BigDecimal.ZERO, BigDecimal.ONE));
        }

        @Test
        @DisplayName("inverseDailyHours: quantidade zero → InputValidationException")
        void inversaQuantidadeZero() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.inverseDailyHours(
                            new BigDecimal("1460"), new BigDecimal("1000"), BigDecimal.ZERO));
        }

        @Test
        @DisplayName("inverseDailyHours: resultado > 24h → não calculável (NÃO clampa em 24)")
        void inversaAcimaDe24NaoCalculavel() {
            // 100000 kWh/ano ÷ (100W × 1) → 2739.7 h/dia, absurdo → vazio
            Optional<BigDecimal> result = ConsumptionCalculator.inverseDailyHours(
                    new BigDecimal("100000"), new BigDecimal("100"), BigDecimal.ONE);
            assertTrue(result.isEmpty(), "resultado fora de [0,24] deve ser não calculável, sem clamp");
        }

        @Test
        @DisplayName("inverseDailyHours: 24h exatas é aceito (limite inclusivo)")
        void inversa24Exatas() {
            // 8760 kWh/ano ÷ (1000W × 1) × 1000 / 365 = 24 h/dia
            Optional<BigDecimal> result = ConsumptionCalculator.inverseDailyHours(
                    new BigDecimal("8760"), new BigDecimal("1000"), BigDecimal.ONE);
            assertEquals(0, new BigDecimal("24.0000").compareTo(result.orElseThrow()));
        }

        @Test
        @DisplayName("inverseDailyHours: 1460 kWh/ano, 1000W, q=2 → 2.0000 h/dia")
        void inversaValida() {
            Optional<BigDecimal> result = ConsumptionCalculator.inverseDailyHours(
                    new BigDecimal("1460"), new BigDecimal("1000"), new BigDecimal("2"));
            assertEquals(0, new BigDecimal("2.0000").compareTo(result.orElseThrow()));
        }

        @Test
        @DisplayName("inversa × forward são consistentes: 1460 kWh/ano → 4.0000 h/dia → 4 kWh/dia → 1460 kWh/ano")
        void inversaConsistenteComForward() {
            Optional<BigDecimal> hours = ConsumptionCalculator.inverseDailyHours(
                    new BigDecimal("1460"), new BigDecimal("1000"), BigDecimal.ONE);
            assertEquals(0, new BigDecimal("4.0000").compareTo(hours.orElseThrow()));
            BigDecimal daily = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("1000"), hours.orElseThrow(), BigDecimal.ONE);
            BigDecimal annual = ConsumptionCalculator.annualKwh(daily);
            assertEquals(0, new BigDecimal("1460").compareTo(annual));
        }

        @Test
        @DisplayName("cost: arredondamento HALF_UP — 0.005 → 0.01 e 387.3015 → 387.30")
        void arredondamentoHalfUp() {
            assertEquals(0, new BigDecimal("0.01").compareTo(
                    ConsumptionCalculator.cost(new BigDecimal("0.005"), BigDecimal.ONE)));
            assertEquals(0, new BigDecimal("387.30").compareTo(
                    ConsumptionCalculator.cost(new BigDecimal("387.3015"), BigDecimal.ONE)));
        }

        @Test
        @DisplayName("unidades: dailyKwh retorna kWh/dia (100W × 5h × 1 = 0.5 kWh/dia, não kWh/mês)")
        void unidadesDailyKwh() {
            BigDecimal result = ConsumptionCalculator.dailyKwh(
                    new BigDecimal("100"), new BigDecimal("5"), BigDecimal.ONE);
            assertEquals(0, new BigDecimal("0.5").compareTo(result));
        }

        @Test
        @DisplayName("monthlyKwh: 1 kWh/dia × 30 dias = 30 kWh no período")
        void monthlyKwh() {
            BigDecimal result = ConsumptionCalculator.monthlyKwh(
                    BigDecimal.ONE, new BigDecimal("30"));
            assertEquals(0, new BigDecimal("30").compareTo(result));
        }

        @Test
        @DisplayName("monthlyKwh: dias < 1 → InputValidationException")
        void monthlyKwhDiasInvalidos() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.monthlyKwh(BigDecimal.ONE, BigDecimal.ZERO));
        }

        @Test
        @DisplayName("averageMonthKwh: 24 kWh/ano ÷ 12 = 2 kWh/mês (divisão exata)")
        void averageMonthKwhExato() {
            BigDecimal result = ConsumptionCalculator.averageMonthKwh(new BigDecimal("24"));
            assertEquals(0, new BigDecimal("2").compareTo(result));
        }

        @Test
        @DisplayName("averageMonthKwh: 365 kWh/ano ÷ 12 → mês médio ≈ 30.4167 kWh/mês")
        void averageMonthKwhInexacto() {
            // 365/12 não termina em decimal; comparamos após arredondar a 9 casas.
            BigDecimal result = ConsumptionCalculator.averageMonthKwh(new BigDecimal("365"));
            assertEquals(0, new BigDecimal("30.416666667").compareTo(
                    result.setScale(9, java.math.RoundingMode.HALF_UP)));
        }

        @Test
        @DisplayName("source: 1460 kWh/ano × q=2 → 2920 kWh/ano, 8 kWh/dia, 243.33.. kWh/mês")
        void sourceTrio() {
            BigDecimal annual = ConsumptionCalculator.sourceAnnualKwh(
                    new BigDecimal("1460"), new BigDecimal("2"));
            assertEquals(0, new BigDecimal("2920").compareTo(annual));

            BigDecimal daily = ConsumptionCalculator.sourceDailyKwh(
                    new BigDecimal("1460"), new BigDecimal("2"));
            assertEquals(0, BigDecimal.valueOf(8).compareTo(daily));

            BigDecimal avgMonth = ConsumptionCalculator.sourceAverageMonthKwh(
                    new BigDecimal("1460"), new BigDecimal("2"));
            // 2920/12 = 243.333... não termina; comparamos após arredondar a 9 casas.
            assertEquals(0, new BigDecimal("243.333333333").compareTo(
                    avgMonth.setScale(9, java.math.RoundingMode.HALF_UP)));
        }

        @Test
        @DisplayName("source: quantidade < 1 → InputValidationException")
        void sourceQuantidadeInvalida() {
            assertThrows(InputValidationException.class, () ->
                    ConsumptionCalculator.sourceAnnualKwh(
                            new BigDecimal("1460"), new BigDecimal("0")));
        }
    }

    // =====================================================================
    // Casos-limite da inversa e do consumo diário (F1 ↔ F7)
    // =====================================================================

    @Test
    @DisplayName("dailyKwh: 0 horas/dia → 0 kWh/dia (zero é válido, não exceção)")
    void dailyKwh_zeroHoras() {
        BigDecimal result = ConsumptionCalculator.dailyKwh(
                new BigDecimal("1000"), BigDecimal.ZERO, BigDecimal.ONE);
        assertEquals(0, BigDecimal.ZERO.compareTo(result));
    }

    @Test
    @DisplayName("inverseDailyHours: potência negativa → InputValidationException")
    void inversaPotenciaNegativa() {
        assertThrows(InputValidationException.class, () ->
                ConsumptionCalculator.inverseDailyHours(
                        new BigDecimal("1460"), new BigDecimal("-1000"), BigDecimal.ONE));
    }

    @Test
    @DisplayName("inverseDailyHours: energia anual negativa → InputValidationException")
    void inversaEnergiaNegativa() {
        assertThrows(InputValidationException.class, () ->
                ConsumptionCalculator.inverseDailyHours(
                        new BigDecimal("-1460"), new BigDecimal("1000"), BigDecimal.ONE));
    }

    @Test
    @DisplayName("inverseDailyHours: 200W × 200 kWh/ano, q=1 → 2.7397 h/dia (escala 4, divisão não exata)")
    void inversaFracionaria() {
        Optional<BigDecimal> result = ConsumptionCalculator.inverseDailyHours(
                new BigDecimal("200"), new BigDecimal("200"), BigDecimal.ONE);
        // 200000 / (200 × 365) = 2.7397260... → HALF_UP 4 casas
        assertEquals(0, new BigDecimal("2.7397").compareTo(result.orElseThrow()));
    }
}
