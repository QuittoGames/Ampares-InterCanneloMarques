package cannelo.marques.interdisciplinar.interdisciplinar.Services.Consumption;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;

import java.math.BigDecimal;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;

/**
 * Testes unitários para {@link ConsumptionCalculator}.
 *
 * <p>Função pura → testes sem Spring context (rápido, determinístico).
 * Valida a fórmula P(W) × horas / 1000 = kWh e o comportamento defensivo
 * (inputs ausentes → ZERO).
 */
class ConsumptionCalculatorTest {

    @Test
    @DisplayName("calculate: 1000W × 4h / 1000 = 4 kWh")
    void calculate_basico_altaPotencia() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("1000"), new BigDecimal("4"));
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertEquals(0, new BigDecimal("4.0000").compareTo(result));
    }

    @Test
    @DisplayName("calculate: 200W × 8h / 1000 = 1.6 kWh")
    void calculate_basico_mediaPotencia() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("200"), new BigDecimal("8"));
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertEquals(0, new BigDecimal("1.6000").compareTo(result));
    }

    @Test
    @DisplayName("calculate: 50W × 24h / 1000 = 1.2 kWh (low power 24h)")
    void calculate_basico_baixaPotencia24h() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("50"), new BigDecimal("24"));
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertEquals(0, new BigDecimal("1.2000").compareTo(result));
    }

    @Test
    @DisplayName("calculate: ZERO quando product é null")
    void calculate_zero_quandoProductNull() {
        RegistryUserProduct reg = new RegistryUserProduct(
            UUID.randomUUID(), new User(1), 1,
            new BigDecimal("4"), new BigDecimal("20"),
            null
        );
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertSame(BigDecimal.ZERO, result);
    }

    @Test
    @DisplayName("calculate: ZERO quando product.avgPowerW é null")
    void calculate_zero_quandoAvgPowerWNull() {
        Product product = new Product(
            UUID.randomUUID(), "Test", "Brand", "Model", "cat", "sub",
            null, new BigDecimal("100")
        );
        RegistryUserProduct reg = new RegistryUserProduct(
            UUID.randomUUID(), new User(1), 1,
            new BigDecimal("4"), new BigDecimal("20"),
            product
        );
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertSame(BigDecimal.ZERO, result);
    }

    @Test
    @DisplayName("calculate: ZERO quando hoursProvider retorna null")
    void calculate_zero_quandoHoursNull() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("1000"), null);
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertSame(BigDecimal.ZERO, result);
    }

    @Test
    @DisplayName("calculate: ZERO quando userProduct é null")
    void calculate_zero_quandoUserProductNull() {
        BigDecimal result = ConsumptionCalculator.calculate(
            null, RegistryUserProduct::getAvgActiveHours);
        assertSame(BigDecimal.ZERO, result);
    }

    @Test
    @DisplayName("calculate: ZERO quando hoursProvider é null")
    void calculate_zero_quandoHoursProviderNull() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("1000"), new BigDecimal("4"));
        BigDecimal result = ConsumptionCalculator.calculate(reg, null);
        assertSame(BigDecimal.ZERO, result);
    }

    @Test
    @DisplayName("calculate: suporta hoursStandby como provider (consumo de standby)")
    void calculate_standbyProvider() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("1000"), new BigDecimal("20"));
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getHoursStandby);
        // 1000W × 20h / 1000 = 20 kWh standby
        assertEquals(0, new BigDecimal("20.0000").compareTo(result));
    }

    @Test
    @DisplayName("calculate: zero horas → zero kWh")
    void calculate_zeroHoras() {
        RegistryUserProduct reg = registryWithProduct(
            new BigDecimal("1000"), BigDecimal.ZERO);
        BigDecimal result = ConsumptionCalculator.calculate(
            reg, RegistryUserProduct::getAvgActiveHours);
        assertSame(BigDecimal.ZERO, result);
    }

    // ---- helpers ----

    private static RegistryUserProduct registryWithProduct(
            BigDecimal avgPowerW, BigDecimal hours) {
        Product product = new Product(
            UUID.randomUUID(), "Test", "Brand", "Model", "cat", "sub",
            avgPowerW, new BigDecimal("100")
        );
        return new RegistryUserProduct(
            UUID.randomUUID(), new User(1), 1,
            hours, new BigDecimal("20"),
            product
        );
    }
}
