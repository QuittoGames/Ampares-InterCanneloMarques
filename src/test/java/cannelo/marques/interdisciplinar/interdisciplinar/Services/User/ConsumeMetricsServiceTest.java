package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductEmptyException;

@ExtendWith(MockitoExtension.class)
class ConsumeMetricsServiceTest {

    @Mock
    private RegistryUserProductRepository registryRepository;

    @Mock
    private UserRepository userRepository;

    private ConsumeMetricsService service;
    private User user;
    private Product lowConsumptionProduct;
    private Product highConsumptionProduct;

    @BeforeEach
    void setUp() {
        service = new ConsumeMetricsService(registryRepository, userRepository);
        user = new User(7);
        lowConsumptionProduct = product("Low", "electronics", "100");
        highConsumptionProduct = product("High", "electronics", "500");
    }

    @Test
    void shouldSumActiveConsumptionForAllRegisteredProducts() {
        RegistryUserProduct first = registry(lowConsumptionProduct, "4", "20");
        RegistryUserProduct second = registry(highConsumptionProduct, "2", "22");
        givenExistingUserWith(first, second);
        when(userRepository.existsById(user.getId())).thenReturn(true);

        BigDecimal result = service.calculateTotalEnergyByUser(user).orElseThrow();

        assertEquals(0, new BigDecimal("1.4000").compareTo(result));
    }

    @Test
    void shouldIncludeQuantityInActiveConsumption() {
        RegistryUserProduct registry = registry(lowConsumptionProduct, "4", "20", 3);
        givenExistingUserWith(registry);
        when(userRepository.existsById(user.getId())).thenReturn(true);

        BigDecimal result = service.calculateTotalEnergyByUser(user).orElseThrow();

        assertEquals(0, new BigDecimal("1.2000").compareTo(result));
    }

    @Test
    void shouldReturnZeroForAnExistingUserWithoutProductsWhenCalculatingTotal() {
        when(userRepository.existsById(user.getId())).thenReturn(true);
        when(registryRepository.findByUser(user)).thenReturn(List.of());

        assertEquals(BigDecimal.ZERO, service.calculateTotalEnergyByUser(user).orElseThrow());
    }

    @Test
    void shouldCalculateAverageActiveConsumptionWithTwoProducts() {
        RegistryUserProduct first = registry(lowConsumptionProduct, "4", "20");
        RegistryUserProduct second = registry(highConsumptionProduct, "2", "22");
        givenExistingUserWith(first, second);
        when(userRepository.existsById(user.getId())).thenReturn(true);

        BigDecimal result = service.calculateAverageEnergyByUser(user).orElseThrow();

        assertEquals(0, new BigDecimal("0.7000").compareTo(result));
    }

    @Test
    void shouldCalculateAverageStandbyConsumptionRoundedToTwoDecimals() {
        RegistryUserProduct first = registry(lowConsumptionProduct, "4", "20");
        RegistryUserProduct second = registry(highConsumptionProduct, "2", "21");
        givenExistingUserWith(first, second);

        BigDecimal result = service.calculateStandbyConsumeAvg(user).orElseThrow();

        assertEquals(0, new BigDecimal("6.25").compareTo(result));
    }

    @Test
    void shouldReturnMostConsumingProductUsingPowerTimesActiveHours() {
        RegistryUserProduct first = registry(lowConsumptionProduct, "4", "20");
        RegistryUserProduct second = registry(highConsumptionProduct, "2", "22");
        givenExistingUserWith(first, second);

        assertEquals(highConsumptionProduct, service.calculateMostConsumerProduct(user).orElseThrow());
    }

    @Test
    void shouldOrderCategoryProductsByConsumptionAndIgnoreOtherCategories() {
        RegistryUserProduct first = registry(lowConsumptionProduct, "4", "20");
        RegistryUserProduct second = registry(highConsumptionProduct, "2", "22");
        Product otherCategory = product("Other", "furniture", "900");
        RegistryUserProduct other = registry(otherCategory, "24", "0");
        givenExistingUserWith(first, second, other);

        List<Product> result = service.mostConsumerProductsForCategory(user, "ELECTRONICS").orElseThrow();

        assertEquals(List.of(highConsumptionProduct, lowConsumptionProduct), result);
    }

    @Test
    void shouldCalculateStandbyConsumptionForTheRequestedProductOnly() {
        RegistryUserProduct first = registry(lowConsumptionProduct, "4", "20");
        RegistryUserProduct second = registry(highConsumptionProduct, "2", "22");
        givenExistingUserWith(first, second);

        BigDecimal result = service.calculateStandbyConsumesForProduct(user, highConsumptionProduct).orElseThrow();

        assertEquals(0, new BigDecimal("11.0000").compareTo(result));
    }

    @Test
    void shouldRejectMissingUserForTotalConsumption() {
        when(userRepository.existsById(user.getId())).thenReturn(false);

        assertThrows(IllegalStateException.class, () -> service.calculateTotalEnergyByUser(user));
    }

    @Test
    void shouldRejectNullUser() {
        assertThrows(NullPointerException.class, () -> service.calculateTotalEnergyByUser(null));
    }

    @Test
    void shouldRejectEmptyProductListWhenAverageIsRequested() {
        when(userRepository.existsById(user.getId())).thenReturn(true);
        when(registryRepository.findByUser(user)).thenReturn(List.of());

        assertThrows(ProductEmptyException.class, () -> service.calculateAverageEnergyByUser(user));
    }

    private void givenExistingUserWith(RegistryUserProduct... products) {
        when(registryRepository.findByUser(user)).thenReturn(List.of(products));
    }

    private static RegistryUserProduct registry(Product product, String activeHours, String standbyHours) {
        return registry(product, activeHours, standbyHours, 1);
    }

    private static RegistryUserProduct registry(
            Product product, String activeHours, String standbyHours, int quantity) {
        return new RegistryUserProduct(userForRegistry(), quantity,
                new BigDecimal(activeHours), new BigDecimal(standbyHours), product);
    }

    private static User userForRegistry() {
        return new User(7);
    }

    private static Product product(String name, String category, String power) {
        return new Product(java.util.UUID.randomUUID(), name, "Brand", "Model", category, "sub",
                new BigDecimal(power), new BigDecimal("100"));
    }
}
