package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;

@ExtendWith(MockitoExtension.class)
class RegistryUserServiceTest {

    @Mock
    private RegistryUserProductRepository registryRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private ProductRepository productRepository;

    private RegistryUserService service;
    private User user;
    private Product product;

    @BeforeEach
    void setUp() {
        service = new RegistryUserService(registryRepository, userRepository, productRepository);
        user = new User(3);
        product = new Product(null, "Device", "Brand", "Model", "electronics", "sub",
                new BigDecimal("1000"), new BigDecimal("1460"));
        lenient().when(userRepository.existsById(user.getId())).thenReturn(true);
        lenient().when(productRepository.existsById(product.getId())).thenReturn(true);
        lenient().when(registryRepository.findByUserAndProduct(user, product)).thenReturn(List.of());
    }

    @Test
    void shouldPreserveExplicitHoursAndQuantityWhenCreatingRegistry() {
        RegistryUserProduct saved = new RegistryUserProduct(user, 2,
                new BigDecimal("3.5"), new BigDecimal("20.5"), product);
        when(registryRepository.save(any(RegistryUserProduct.class))).thenReturn(saved);

        RegistryUserProduct result = service.createRegistry(user, product, 2,
                new BigDecimal("3.5"), new BigDecimal("20.5"));

        assertSame(saved, result);
        ArgumentCaptor<RegistryUserProduct> captor = ArgumentCaptor.forClass(RegistryUserProduct.class);
        verify(registryRepository).save(captor.capture());
        assertEquals(2, captor.getValue().getQuantity());
        assertEquals(new BigDecimal("3.5"), captor.getValue().getAvgActiveHours());
        assertEquals(new BigDecimal("20.5"), captor.getValue().getHoursStandby());
    }

    @Test
    void shouldDeriveBothHourValuesWhenTheyAreAbsent() {
        when(registryRepository.save(any(RegistryUserProduct.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        RegistryUserProduct result = service.createRegistry(user, product, 1, null, null);

        assertEquals(0, new BigDecimal("4.0000").compareTo(result.getAvgActiveHours()));
        assertEquals(0, new BigDecimal("20.0000").compareTo(result.getHoursStandby()));
    }

    @Test
    void shouldRejectDuplicateUserProductRegistry() {
        RegistryUserProduct existing = new RegistryUserProduct(user, 1,
                new BigDecimal("4"), new BigDecimal("20"), product);
        when(registryRepository.findByUserAndProduct(user, product)).thenReturn(List.of(existing));

        assertThrows(IllegalStateException.class,
                () -> service.createRegistry(user, product, 1, new BigDecimal("4"), new BigDecimal("20")));
    }

    @Test
    void shouldRejectUnknownUserBeforeSaving() {
        when(userRepository.existsById(user.getId())).thenReturn(false);

        assertThrows(UserNotFoundException.class,
                () -> service.createRegistry(user, product, 1, null, null));
    }

    @Test
    void shouldRejectUnknownProductBeforeSaving() {
        when(productRepository.existsById(product.getId())).thenReturn(false);

        assertThrows(ProductNotFoundException.class,
                () -> service.createRegistry(user, product, 1, null, null));
    }

    @Test
    void shouldRejectNullUserAndProduct() {
        assertThrows(NullPointerException.class, () -> service.createRegistry(null, product, 1, null, null));
        assertThrows(NullPointerException.class, () -> service.createRegistry(user, null, 1, null, null));
    }
}
