package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ResultDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics.ConsumeMetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffQuote;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.TariffUnavailableException;

/**
 * Testes do hub {@link ConsumeMetricsService} — contrato decision_004
 * (nunca null, Optional.empty() quando não calculável) e unidades da
 * SPEC §8 (kWh/dia para ranking, kWh/ano para médias, R$/dia e R$/ano para
 * custos, standby vazio).
 */
@ExtendWith(MockitoExtension.class)
class ConsumeMetricsServiceTest {

    /** Tarifa de teste em R$/kWh — usada para fixar os custos esperados. */
    private static final String TEST_TARIFF_PER_KWH = "1.06110";

    @Mock
    private RegistryUserProductRepository registryRepository;

    @Mock
    private TariffService tariffService;

    private ConsumeMetricsService service;
    private User user;

    @BeforeEach
    void setUp() {
        service = new ConsumeMetricsService(registryRepository, tariffService);
        user = new User(7);
    }

    // =====================================================================
    // Contrato decision_004 — nunca null, nunca exception por lista vazia
    // =====================================================================

    @Test
    void shouldReturnEmptyListWithoutExceptionWhenUserHasNoRegistries() {
        when(registryRepository.findByUser(user)).thenReturn(List.of());

        List<RegistryUserProduct> result = service.getProductsRegistrys(user);

        assertTrue(result.isEmpty(), "lista vazia é resultado válido, não erro");
    }

    @Test
    void shouldReturnEmptyMetricsWhenUserHasNoRegistries() {
        when(registryRepository.findByUser(user)).thenReturn(List.of());

        assertTrue(service.calculateAverageEnergyByUser(user).isEmpty());
        assertTrue(service.calculateMostConsumerProduct(user).isEmpty());
        assertTrue(service.calculateMostConsumerProductByCategory(user, "electronics").isEmpty());
        assertTrue(service.calculate(user).isEmpty());
    }

    @Test
    void shouldRejectNullUserInsteadOfReturningNull() {
        assertThrows(NullPointerException.class, () -> service.getProductsRegistrys(null));
        assertThrows(NullPointerException.class, () -> service.calculateAverageEnergyByUser(null));
        assertThrows(NullPointerException.class, () -> service.calculateMostConsumerProduct(null));
        assertThrows(NullPointerException.class, () -> service.calculate(null));
    }

    // =====================================================================
    // Média anual por associação — registros inválidos são excluídos
    // =====================================================================

    @Test
    void shouldAverageAnnualConsumptionPerAssociationExcludingInvalidRegistries() {
        // válido: 100W × 5h × 2 / 1000 = 1 kWh/dia → 365 kWh/ano
        RegistryUserProduct validOne = registry(product("A", "electronics", "100"), "5", 2);
        // válido: 1000W × 2h × 1 / 1000 = 2 kWh/dia → 730 kWh/ano
        RegistryUserProduct validTwo = registry(product("B", "electronics", "1000"), "2", 1);
        // inválido: produto sem potência (avgPowerW null) — excluído
        RegistryUserProduct invalidNoPower = registry(productWithoutPower("C", "furniture"), "5", 1);
        // inválido: registro sem horas ativas (avgActiveHours null) — excluído
        RegistryUserProduct invalidNoHours = registry(product("D", "electronics", "500"), null, 1);
        when(registryRepository.findByUser(user))
                .thenReturn(List.of(validOne, validTwo, invalidNoPower, invalidNoHours));

        BigDecimal result = service.calculateAverageEnergyByUser(user).orElseThrow();

        // (365 + 730) / 2 = 547.5 kWh/ano por associação — unidade ANUAL
        // (a média diária seria 1.5; o ×365 prova que o retorno é kWh/ano)
        assertEquals(0, new BigDecimal("547.500000").compareTo(result));
    }

    @Test
    void shouldReturnEmptyAverageWhenAllRegistriesAreInvalid() {
        RegistryUserProduct invalidNoPower = registry(productWithoutPower("C", "furniture"), "5", 1);
        when(registryRepository.findByUser(user)).thenReturn(List.of(invalidNoPower));

        assertTrue(service.calculateAverageEnergyByUser(user).isEmpty());
    }

    // =====================================================================
    // Ranking — quantidade participa do consumo
    // =====================================================================

    @Test
    void shouldRankByDailyConsumptionIncludingQuantity() {
        // mesma potência e mesmas horas; só a quantidade difere
        Product single = product("Single", "electronics", "100"); // 100×5×1/1000 = 0.5 kWh/dia
        Product doubled = product("Doubled", "electronics", "100"); // 100×5×2/1000 = 1.0 kWh/dia
        RegistryUserProduct one = registry(single, "5", 1);
        RegistryUserProduct two = registry(doubled, "5", 2);
        when(registryRepository.findByUser(user)).thenReturn(List.of(one, two));

        Optional<Product> result = service.calculateMostConsumerProduct(user);

        assertEquals(doubled, result.orElseThrow(), "q=2 deve vencer q=1 com potência igual");
    }

    @Test
    void shouldReturnEmptyMostConsumerWhenNoValidRegistries() {
        when(registryRepository.findByUser(user)).thenReturn(List.of());

        assertTrue(service.calculateMostConsumerProduct(user).isEmpty());
    }

    // =====================================================================
    // Categoria — case-insensitive e ordenação DESC
    // =====================================================================

    @Test
    void shouldOrderCategoryProductsDescendingAndIgnoreCase() {
        // 500W × 2h / 1000 = 1.0 kWh/dia (maior)
        Product high = product("High", "Electronics", "500");
        // 100W × 4h / 1000 = 0.4 kWh/dia (menor)
        Product low = product("Low", "electronics", "100");
        // outra categoria — 900W × 5h = 4.5 kWh/dia, mas fora do filtro
        Product other = product("Other", "furniture", "900");
        when(registryRepository.findByUser(user)).thenReturn(List.of(
                registry(low, "4", 1),
                registry(other, "5", 1),
                registry(high, "2", 1)));

        List<Product> result = service.calculateMostConsumerProductByCategory(user, "ELECTRONICS")
                .orElseThrow();

        assertEquals(List.of(high, low), result, "DESC por kWh/dia e equalsIgnoreCase");
    }

    @Test
    void shouldReturnEmptyCategoryWhenCategoryIsBlankOrUnknown() {
        when(registryRepository.findByUser(user))
                .thenReturn(List.of(registry(product("A", "electronics", "100"), "5", 1)));

        assertTrue(service.calculateMostConsumerProductByCategory(user, "kitchen").isEmpty());
        assertTrue(service.calculateMostConsumerProductByCategory(user, "  ").isEmpty());
        assertTrue(service.calculateMostConsumerProductByCategory(user, null).isEmpty());
    }

    // =====================================================================
    // Standby — nunca calculável enquanto não houver dado confiável (SPEC §7)
    // =====================================================================

    @Test
    void shouldNeverUseActivePowerAsStandby() {
        assertTrue(service.calculateStandbyConsumeAvg(user).isEmpty(),
                "standby não calculável: avgPowerW NUNCA é potência de standby");
        assertTrue(service.calculateStandbyConsumesForProduct(user,
                product("Any", "electronics", "900")).isEmpty());
    }

    // =====================================================================
    // ResultDTO geral
    // =====================================================================

    @Test
    void shouldBuildResultDtoWithAveragesInExplicitUnits() {
        user.setName("Quitto");
        // 100W × 5h × 2 / 1000 = 1 kWh/dia → 365 kWh/ano; horas = 5
        RegistryUserProduct validOne = registry(product("A", "electronics", "100"), "5", 2);
        // 1000W × 2h × 1 / 1000 = 2 kWh/dia → 730 kWh/ano; horas = 2
        RegistryUserProduct validTwo = registry(product("B", "electronics", "1000"), "2", 1);
        // inválido: sem horas — entra em productsList mas não nas médias
        RegistryUserProduct invalid = registry(product("C", "furniture", "500"), null, 1);
        when(registryRepository.findByUser(user)).thenReturn(List.of(validOne, validTwo, invalid));
        stubReferenceTariff(TEST_TARIFF_PER_KWH);

        ResultDTO result = service.calculate(user).orElseThrow();

        assertEquals(7, result.id());
        assertEquals("Quitto", result.name());
        // média de consumo diário por associação válida: (1 + 2) / 2 = 1.5 kWh/dia
        assertEquals(0, new BigDecimal("1.500000").compareTo(result.avgDailyKwh()));
        // média anual por associação válida: (365 + 730) / 2 = 547.5 kWh/ano
        assertEquals(0, new BigDecimal("547.500000").compareTo(result.avgUseInYear()));
        // TOTAIS sobre os mesmos válidos: 1 + 2 = 3 kWh/dia e 365 + 730 = 1095 kWh/ano
        assertEquals(0, new BigDecimal("3").compareTo(result.totalDailyKwh()));
        assertEquals(0, new BigDecimal("1095").compareTo(result.totalAnnualKwh()));
        // custos com tarifa 1.06110 R$/kWh (motor, HALF_UP 2 casas):
        // 3 × 1.06110 = 3.18330 → 3.18 R$/dia
        // 1095 × 1.06110 = 1161.9045 → 1161.90 R$/ano
        assertEquals(0, new BigDecimal("3.18").compareTo(result.dailyCost()));
        assertEquals(0, new BigDecimal("1161.90").compareTo(result.annualCost()));
        assertEquals(3, result.productsList().size(), "productsList traz todos os registros");
    }

    // =====================================================================
    // Custos (R$/dia e R$/ano) — motor cost() + tarifa do TariffService
    // =====================================================================

    @Test
    void shouldCalculateMonetaryCostsFromEngineWithReferenceTariff() {
        // registro conhecido: 100W × 5h × 2 / 1000 = 1.0 kWh/dia → 365 kWh/ano
        when(registryRepository.findByUser(user))
                .thenReturn(List.of(registry(product("A", "electronics", "100"), "5", 2)));
        stubReferenceTariff(TEST_TARIFF_PER_KWH);

        ResultDTO result = service.calculate(user).orElseThrow();

        assertEquals(0, new BigDecimal("1").compareTo(result.totalDailyKwh()),
                "total diário = Σ calculateDailyKwh = 1.0 kWh/dia");
        assertEquals(0, new BigDecimal("365").compareTo(result.totalAnnualKwh()),
                "total anual = Σ calculateAnnualKwh = 365 kWh/ano (motor, não ×365 inline)");
        // 1.0 kWh/dia × 1.06110 R$/kWh = 1.06110 → HALF_UP 2 casas = 1.06
        assertEquals(0, new BigDecimal("1.06").compareTo(result.dailyCost()));
        assertEquals(2, result.dailyCost().scale(), "dinheiro = escala 2, HALF_UP");
        // 365 kWh/ano × 1.06110 R$/kWh = 387.3015 → HALF_UP 2 casas = 387.30
        assertEquals(0, new BigDecimal("387.30").compareTo(result.annualCost()));
        assertEquals(2, result.annualCost().scale(), "dinheiro = escala 2, HALF_UP");
    }

    @Test
    void shouldPropagateTariffUnavailableExceptionInsteadOfInventingTariff() {
        when(registryRepository.findByUser(user))
                .thenReturn(List.of(registry(product("A", "electronics", "100"), "5", 2)));
        when(tariffService.getReferenceTariff(any(LocalDate.class)))
                .thenThrow(new TariffUnavailableException("Tarifa indisponível (teste)"));

        assertThrows(TariffUnavailableException.class, () -> service.calculate(user),
                "tarifa indisponível propaga — o hub NUNCA inventa tarifa");
    }

    @Test
    void shouldReturnEmptyResultWhenUserHasOnlyInvalidRegistries() {
        RegistryUserProduct invalid = registry(productWithoutPower("C", "furniture"), "5", 1);
        when(registryRepository.findByUser(user)).thenReturn(List.of(invalid));

        assertTrue(service.calculate(user).isEmpty());
    }

    // =====================================================================
    // avg(List<?>) — curinga defensivo (decision_004 OQ)
    // =====================================================================

    @Test
    void shouldAverageOnlyNumericElementsOfTheList() {
        Optional<BigDecimal> result = service.avg(BigDecimal.ONE, List.of(1, 2, 3));

        assertEquals(0, new BigDecimal("2.000000").compareTo(result.orElseThrow()));
    }

    @Test
    void shouldIgnoreNonNumericAndNullElements() {
        Optional<BigDecimal> result = service.avg(BigDecimal.ONE, Arrays.asList(1, "x", null, 3));

        assertEquals(0, new BigDecimal("2.000000").compareTo(result.orElseThrow()));
    }

    @Test
    void shouldReturnEmptyWhenValueIsNullOrListHasNoNumbers() {
        assertTrue(service.avg(null, List.of(1, 2)).isEmpty(), "value null → não calculável");
        assertTrue(service.avg(BigDecimal.ONE, List.of("a", "b")).isEmpty());
        assertTrue(service.avg(BigDecimal.ONE, List.of()).isEmpty());
        assertTrue(service.avg(BigDecimal.ONE, null).isEmpty());
    }

    @Test
    void shouldKeepAvgResultAsBigDecimalNeverDouble() {
        Optional<BigDecimal> result = service.avg(BigDecimal.ONE, List.of(1.5, 2.5));

        assertTrue(result.isPresent());
        assertFalse(result.get().toString().contains("E"),
                "resultado deve ser BigDecimal com escala, nunca notação de ponto flutuante");
        assertEquals(0, new BigDecimal("2.000000").compareTo(result.get()));
    }

    // =====================================================================
    // Registros inconsistentes (horas fora de [0,24]) — SPEC §6
    // =====================================================================

    @Test
    void shouldExcludeRegistryWithImpossibleHoursFromCalculate() {
        Product ok = product("Geladeira", "Cozinha", "100");
        Product bad = product("Legado", "Cozinha", "100");
        when(registryRepository.findByUser(user)).thenReturn(List.of(
                registry(ok, "5", 2),
                registry(bad, "316.12", 1)));
        stubReferenceTariff(TEST_TARIFF_PER_KWH);

        Optional<ResultDTO> result = service.calculate(user);

        assertTrue(result.isPresent(), "o registro válido ainda gera resultado");
        assertEquals(0, new BigDecimal("365.000000").compareTo(result.get().avgUseInYear()),
                "só o registro de 100W×5h×2 entra no agregado (365 kWh/ano)");
        assertEquals(0, new BigDecimal("1").compareTo(result.get().totalDailyKwh()),
                "o registro impossível também fica fora dos TOTAIS (1 kWh/dia)");
        assertEquals(0, new BigDecimal("365").compareTo(result.get().totalAnnualKwh()),
                "o registro impossível também fica fora dos TOTAIS (365 kWh/ano)");
    }

    @Test
    void shouldReturnEmptyWhenAllRegistriesHaveImpossibleHours() {
        Product bad = product("Legado", "Cozinha", "100");
        when(registryRepository.findByUser(user)).thenReturn(List.of(
                registry(bad, "316.12", 1)));

        assertTrue(service.calculate(user).isEmpty());
        assertTrue(service.calculateAverageEnergyByUser(user).isEmpty());
        assertTrue(service.calculateMostConsumerProduct(user).isEmpty());
    }

    // =====================================================================
    // Helpers de construção
    // =====================================================================

    /**
     * Simula a FONTE ÚNICA de tarifa: {@code TariffService} devolve uma
     * {@link TariffQuote} VALID com a tarifa informada em R$/kWh.
     */
    private void stubReferenceTariff(String tariffPerKwh) {
        when(tariffService.getReferenceTariff(any(LocalDate.class))).thenReturn(
                new TariffQuote(
                        new BigDecimal(tariffPerKwh),
                        "ENEL_SP",
                        "B1_RESIDENCIAL",
                        "CONVENCIONAL",
                        LocalDate.of(2026, 3, 15),
                        LocalDate.of(2027, 3, 14),
                        "https://www.enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html",
                        TariffQuote.ORIGIN_UNIT,
                        TariffQuote.Status.VALID));
    }

    private static RegistryUserProduct registry(Product product, String activeHours, int quantity) {
        BigDecimal hours = activeHours == null ? null : new BigDecimal(activeHours);
        return new RegistryUserProduct(new User(7), quantity, hours, null, product);
    }

    private static Product product(String name, String category, String power) {
        return new Product(UUID.randomUUID(), name, "Brand", "Model", category, "sub",
                new BigDecimal(power), new BigDecimal("100"));
    }

    private static Product productWithoutPower(String name, String category) {
        return new Product(UUID.randomUUID(), name, "Brand", "Model", category, "sub",
                null, new BigDecimal("100"));
    }
}
