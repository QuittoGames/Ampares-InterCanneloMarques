package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsByUserDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsStandbyByProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.MetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
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

    private MetricsController controller;
    private User user;
    private Product product;

    @BeforeEach
    void setUp() {
        controller = new MetricsController(metricsService, userRepository, productRepository);
        user = new User(11);
        product = new Product(UUID.randomUUID());
    }

    @Test
    void shouldReturnTotalEnergyFromService() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateTotalEnergyByUser(user)).thenReturn(Optional.of(new BigDecimal("12.50")));

        assertEquals(new BigDecimal("12.50"), controller.totalEnergyByUser(new MetricsByUserDTO(11)).getBody());
    }

    @Test
    void shouldReturnZeroWhenTotalEnergyIsEmpty() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateTotalEnergyByUser(user)).thenReturn(Optional.empty());

        assertEquals(BigDecimal.ZERO, controller.totalEnergyByUser(new MetricsByUserDTO(11)).getBody());
    }

    @Test
    void shouldReturnNotFoundWhenMostConsumingProductIsAbsent() {
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(metricsService.calculateMostConsumerProduct(user)).thenReturn(Optional.empty());

        assertEquals(404, controller.mostConsumerProduct(new MetricsByUserDTO(11)).getStatusCode().value());
    }

    @Test
    void shouldResolveBothEntitiesForStandbyByProduct() {
        UUID productId = product.getId();
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(productRepository.findById(productId)).thenReturn(Optional.of(product));
        when(metricsService.calculateStandbyConsumesForProduct(user, product))
                .thenReturn(Optional.of(new BigDecimal("3.20")));

        assertEquals(new BigDecimal("3.20"), controller.standbyConsumeByProduct(
                new MetricsStandbyByProductDTO(11, productId)).getBody());
        verify(metricsService).calculateStandbyConsumesForProduct(user, product);
    }

    @Test
    void shouldRejectUnknownUserBeforeCallingMetricsService() {
        when(userRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controller.averageEnergyByUser(new MetricsByUserDTO(99)));
    }

    @Test
    void shouldRejectUnknownProductForStandbyByProduct() {
        UUID productId = UUID.randomUUID();
        when(userRepository.findById(11)).thenReturn(Optional.of(user));
        when(productRepository.findById(productId)).thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class,
                () -> controller.standbyConsumeByProduct(new MetricsStandbyByProductDTO(11, productId)));
    }
}
