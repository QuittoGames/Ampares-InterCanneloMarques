package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.math.BigDecimal;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;

/**
 * Testes unitários para {@link RegistryCalculator}.
 *
 * <p>Funções puras → testes sem Spring context (rápido, determinístico).
 * Asserções refletem o mesmo contrato do normalizer Python:
 * nenhum valor inventado, divisão por zero → null.
 */
class RegistryCalculatorTest {

    private static final BigDecimal W_100 = new BigDecimal("100");
    private static final BigDecimal W_200 = new BigDecimal("200");
    private static final BigDecimal W_1000 = new BigDecimal("1000");
    private static final BigDecimal KWH_200 = new BigDecimal("200");
    private static final BigDecimal KWH_1460 = new BigDecimal("1460");

    @Test
    @DisplayName("computeEquivalentHoursYear: 1000 * E / P — bate com seed.sql (alta potência)")
    void equivalentHoursYear_altaPotencia_bateComSeed() {
        // P=1000W, E=1460kWh/ano → 1000*1460/1000 = 1460 h/ano
        BigDecimal result = RegistryCalculator.computeEquivalentHoursYear(W_1000, KWH_1460);
        assertNotNull(result);
        assertEquals(0, new BigDecimal("1460.0000").compareTo(result));
    }

    @Test
    @DisplayName("computeEquivalentHoursYear: null quando P ausente")
    void equivalentHoursYear_nullQuandoPAusente() {
        assertNull(RegistryCalculator.computeEquivalentHoursYear(null, KWH_200));
    }

    @Test
    @DisplayName("computeEquivalentHoursYear: null quando E ausente")
    void equivalentHoursYear_nullQuandoEAusente() {
        assertNull(RegistryCalculator.computeEquivalentHoursYear(W_200, null));
    }

    @Test
    @DisplayName("computeEquivalentHoursYear: null quando P é zero (sem divisão por zero)")
    void equivalentHoursYear_nullQuandoPZero() {
        assertNull(RegistryCalculator.computeEquivalentHoursYear(BigDecimal.ZERO, KWH_200));
    }

    @Test
    @DisplayName("computeEquivalentHoursYear: null quando P é negativo")
    void equivalentHoursYear_nullQuandoPNegativo() {
        assertNull(
            RegistryCalculator.computeEquivalentHoursYear(new BigDecimal("-100"), KWH_200));
    }

    @Test
    @DisplayName("computeEquivalentHoursYearDay: 1460 h/ano / 365 = 4.0000 h/dia")
    void equivalentHoursYearDay_altaPotencia() {
        BigDecimal result =
            RegistryCalculator.computeEquivalentHoursYearDay(new BigDecimal("1460"));
        assertNotNull(result);
        assertEquals(0, new BigDecimal("4.0000").compareTo(result));
    }

    @Test
    @DisplayName("computeEquivalentHoursYearDay: null quando entrada null")
    void equivalentHoursYearDay_nullQuandoEntradaNull() {
        assertNull(RegistryCalculator.computeEquivalentHoursYearDay(null));
    }

    @Test
    @DisplayName("computeHoursStandbyPerDay: 24 - 4 = 20 h/dia (alta potência do seed)")
    void hoursStandby_altaPotencia_bateComSeed() {
        BigDecimal standby = RegistryCalculator.computeHoursStandbyPerDay(
            new BigDecimal("4.0000"));
        assertNotNull(standby);
        assertEquals(0, new BigDecimal("20.0000").compareTo(standby));
    }

    @Test
    @DisplayName("computeHoursStandbyPerDay: null quando ativo null")
    void hoursStandby_nullQuandoAtivoNull() {
        assertNull(RegistryCalculator.computeHoursStandbyPerDay((BigDecimal) null));
    }

    @Test
    @DisplayName("computeHoursStandbyPerDay: null quando ativo > 24 (impossível)")
    void hoursStandby_nullQuandoAtivoExcede24() {
        assertNull(RegistryCalculator.computeHoursStandbyPerDay(
            new BigDecimal("25")));
    }

    @Test
    @DisplayName("computeHoursStandbyPerDay: null quando ativo negativo")
    void hoursStandby_nullQuandoAtivoNegativo() {
        assertNull(RegistryCalculator.computeHoursStandbyPerDay(
            new BigDecimal("-1")));
    }

    @Test
    @DisplayName("computeDailyHours: 200W, 200kWh/ano → ~2.74h ativas, ~21.26h standby")
    void dailyHours_mediaPotencia() {
        BigDecimal[] result = RegistryCalculator.computeDailyHours(W_200, KWH_200);
        assertNotNull(result[0]);
        assertNotNull(result[1]);
        // 1000*200/200 = 1000 h/ano → 1000/365 = 2.7397 h/dia
        assertEquals(0, new BigDecimal("2.7397").compareTo(result[0]));
        // 24 - 2.7397 = 21.2603 h/dia
        assertEquals(0, new BigDecimal("21.2603").compareTo(result[1]));
    }

    @Test
    @DisplayName("computeAvgActiveHoursPerDay: extrai do Product e calcula")
    void avgActiveHours_deProduct() {
        Product product = new Product(
            UUID.randomUUID(), "Test", "Brand", "Model", "cat", "sub",
            W_1000, KWH_1460
        );
        BigDecimal result = RegistryCalculator.computeAvgActiveHoursPerDay(product);
        assertNotNull(result);
        assertEquals(0, new BigDecimal("4.0000").compareTo(result));
    }

    @Test
    @DisplayName("computeAvgActiveHoursPerDay: null quando Product é null")
    void avgActiveHours_nullQuandoProductNull() {
        assertNull(RegistryCalculator.computeAvgActiveHoursPerDay(null));
    }

    @Test
    @DisplayName("computeAvgActiveHoursPerDay: null quando Product sem avgPowerW")
    void avgActiveHours_nullQuandoProductSemPotencia() {
        Product product = new Product(
            UUID.randomUUID(), "Test", "Brand", "Model", "cat", "sub",
            null, KWH_1460
        );
        assertNull(RegistryCalculator.computeAvgActiveHoursPerDay(product));
    }

    @Test
    @DisplayName("computeHoursStandbyPerDay(Product): 24 - ativo = standby")
    void hoursStandby_deProduct() {
        Product product = new Product(
            UUID.randomUUID(), "Test", "Brand", "Model", "cat", "sub",
            W_1000, KWH_1460
        );
        BigDecimal result = RegistryCalculator.computeHoursStandbyPerDay(product);
        assertNotNull(result);
        assertEquals(0, new BigDecimal("20.0000").compareTo(result));
    }
}
