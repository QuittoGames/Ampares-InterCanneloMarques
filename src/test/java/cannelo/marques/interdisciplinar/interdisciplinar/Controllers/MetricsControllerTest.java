package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsByUserDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsStandbyByProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.SearchResponseDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.MetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;

@ExtendWith(MockitoExtension.class)
class MetricsControllerTest {

    @Mock
    private MetricsService<User, BigDecimal> metricsService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private ProductRepository productRepository;
    @Mock
    private ProductService productService;
    @Mock
    private UserService userService;

    private MetricsController controller;
    private User user;
    private Product product;

    @BeforeEach
    void setUp() {
        controller = new MetricsController(metricsService, userRepository, productRepository, productService, userService);
        user = new User(11);
        product = new Product(UUID.randomUUID());
    }

    @Test
    void shouldReturnTotalEnergyFromService() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateTotalEnergyByUser(user)).thenReturn(Optional.of(new BigDecimal("12.50")));

        assertEquals(new BigDecimal("12.50"), controller.totalEnergyByUser(new MetricsByUserDTO(11)).getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateTotalEnergyByUser(user);
    }

    @Test
    void shouldReturnZeroWhenTotalEnergyIsEmpty() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateTotalEnergyByUser(user)).thenReturn(Optional.empty());

        assertEquals(BigDecimal.ZERO, controller.totalEnergyByUser(new MetricsByUserDTO(11)).getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateTotalEnergyByUser(user);
    }

    @Test
    void shouldThrowUserNotFoundWhenUserDoesNotExistForTotalEnergy() {
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.totalEnergyByUser(new MetricsByUserDTO(99)));
        verify(userRepository).findById(99);
    }

    @Test
    void shouldReturnAverageEnergyFromService() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateAverageEnergyByUser(user)).thenReturn(Optional.of(new BigDecimal("5.25")));

        assertEquals(new BigDecimal("5.25"), controller.averageEnergyByUser(new MetricsByUserDTO(11)).getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateAverageEnergyByUser(user);
    }

    @Test
    void shouldReturnZeroWhenAverageEnergyIsEmpty() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateAverageEnergyByUser(user)).thenReturn(Optional.empty());

        assertEquals(BigDecimal.ZERO, controller.averageEnergyByUser(new MetricsByUserDTO(11)).getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateAverageEnergyByUser(user);
    }

    @Test
    void shouldThrowUserNotFoundWhenUserDoesNotExistForAverageEnergy() {
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.averageEnergyByUser(new MetricsByUserDTO(99)));
        verify(userRepository).findById(99);
    }

    @Test
    void shouldReturnMostConsumingProductWhenAvailable() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateMostConsumerProduct(user)).thenReturn(Optional.of(product));

        ResponseEntity<Product> result = controller.mostConsumerProduct(new MetricsByUserDTO(11));
        assertEquals(HttpStatus.OK, result.getStatusCode());
        assertEquals(product, result.getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateMostConsumerProduct(user);
    }

    @Test
    void shouldReturnNotFoundWhenMostConsumingProductIsAbsent() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateMostConsumerProduct(user)).thenReturn(Optional.empty());

        assertEquals(404, controller.mostConsumerProduct(new MetricsByUserDTO(11)).getStatusCode().value());
        verify(userRepository).findById(11);
        verify(metricsService).calculateMostConsumerProduct(user);
    }

    @Test
    void shouldThrowUserNotFoundWhenUserDoesNotExistForMostConsumingProduct() {
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.mostConsumerProduct(new MetricsByUserDTO(99)));
        verify(userRepository).findById(99);
    }

    @Test
    void shouldReturnStandbyConsumeAvgFromService() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateStandbyConsumeAvg(user)).thenReturn(Optional.of(new BigDecimal("1.80")));

        assertEquals(new BigDecimal("1.80"), controller.standbyConsumeAvg(new MetricsByUserDTO(11)).getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateStandbyConsumeAvg(user);
    }

    @Test
    void shouldReturnZeroWhenStandbyConsumeAvgIsEmpty() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateStandbyConsumeAvg(user)).thenReturn(Optional.empty());

        assertEquals(BigDecimal.ZERO, controller.standbyConsumeAvg(new MetricsByUserDTO(11)).getBody());
        verify(userRepository).findById(11);
        verify(metricsService).calculateStandbyConsumeAvg(user);
    }

    @Test
    void shouldThrowUserNotFoundWhenUserDoesNotExistForStandbyConsumeAvg() {
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.standbyConsumeAvg(new MetricsByUserDTO(99)));
        verify(userRepository).findById(99);
    }

    @Test
    void shouldResolveBothEntitiesForStandbyByProduct() {
        UUID productId = product.getId();
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(productService.findById(productId)).thenReturn(product);
        when(metricsService.calculateStandbyConsumesForProduct(user, product))
                .thenReturn(Optional.of(new BigDecimal("3.20")));

        assertEquals(new BigDecimal("3.20"), controller.standbyConsumeByProduct(
                new MetricsStandbyByProductDTO(11, productId)).getBody());
        verify(metricsService).calculateStandbyConsumesForProduct(user, product);
    }

    @Test
    void shouldThrowProductNotFoundWhenProductDoesNotExistForStandbyByProduct() {
        UUID productId = UUID.randomUUID();
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(productService.findById(productId)).thenThrow(new ProductNotFoundException("Product not found: " + productId));

        assertThrows(ProductNotFoundException.class,
                () -> controller.standbyConsumeByProduct(new MetricsStandbyByProductDTO(11, productId)));
        verify(userRepository).findById(11);
        verify(productService).findById(productId);
    }

    @Test
    void shouldThrowUserNotFoundWhenUserDoesNotExistForStandbyByProduct() {
        UUID productId = UUID.randomUUID();
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.standbyConsumeByProduct(new MetricsStandbyByProductDTO(99, productId)));
        verify(userRepository).findById(99);
    }

    @Test
    void shouldReturnSearchResponseWhenProductFound() {
        UUID productId = product.getId();
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(productService.searchProduct(user, "test")).thenReturn(Optional.of(List.of(product)));

        SearchResponseDTO result = controller.searchProduct(11, "test");
        assertEquals(productId, result.productId());
        assertEquals(product.getName(), result.productName());
        verify(userRepository).findById(11);
        verify(productService).searchProduct(user, "test");
    }

    @Test
    void shouldThrowProductNotFoundWhenNoProductsFoundForSearch() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(productService.searchProduct(user, "nonexistent")).thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class,
                () -> controller.searchProduct(11, "nonexistent"));
        verify(userRepository).findById(11);
        verify(productService).searchProduct(user, "nonexistent");
    }

    @Test
    void shouldThrowUserNotFoundWhenUserDoesNotExistForSearch() {
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.searchProduct(99, "test"));
        verify(userRepository).findById(99);
    }
}
