package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
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

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.RegistryUserProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry.RegistryUserService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;

@ExtendWith(MockitoExtension.class)
class RegistryUserProductControllerTest {

    @Mock
    private RegistryUserService registryUserService;
    @Mock
    private UserService userService;
    @Mock
    private UserRepository userRepository;
    @Mock
    private ProductRepository productRepository;

    private RegistryUserProductController controller;
    private User user;
    private Product product;

    @BeforeEach
    void setUp() {
        controller = new RegistryUserProductController(
                registryUserService, userService, userRepository, productRepository);
        user = new User(4);
        product = new Product(UUID.randomUUID());
    }

    @Test
    void shouldResolveEntitiesAndPropagateAllCreateFields() {
        BigDecimal activeHours = new BigDecimal("4.25");
        BigDecimal standbyHours = new BigDecimal("19.75");
        RegistryUserProduct created = new RegistryUserProduct(
                user, 3, activeHours, standbyHours, product);
        givenEntitiesExist();
        when(registryUserService.createRegistry(
                user, product, 3, activeHours, standbyHours)).thenReturn(created);

        var response = controller.create(new RegistryUserProductDTO(
                user.getId(), product.getId(), 3, activeHours, standbyHours));

        assertSame(created, response.getBody());
        verify(registryUserService).createRegistry(
                user, product, 3, activeHours, standbyHours);
    }

    @Test
    void shouldNormalizeZeroQuantityToOne() {
        BigDecimal activeHours = new BigDecimal("4");
        givenEntitiesExist();
        RegistryUserProduct created = new RegistryUserProduct(
                user, 1, activeHours, null, product);
        when(registryUserService.createRegistry(
                user, product, 1, activeHours, null)).thenReturn(created);

        controller.create(new RegistryUserProductDTO(
                user.getId(), product.getId(), 0, activeHours, null));

        verify(registryUserService).createRegistry(user, product, 1, activeHours, null);
    }

    @Test
    void shouldNormalizeNegativeQuantityToOne() {
        BigDecimal activeHours = new BigDecimal("2");
        givenEntitiesExist();
        when(registryUserService.createRegistry(user, product, 1, activeHours, null))
                .thenReturn(new RegistryUserProduct(user, 1, activeHours, null, product));

        controller.create(new RegistryUserProductDTO(
                user.getId(), product.getId(), -5, activeHours, null));

        verify(registryUserService).createRegistry(user, product, 1, activeHours, null);
    }

    @Test
    void shouldRejectMissingUserWithoutResolvingProductOrCreatingRegistry() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class, () -> controller.create(
                new RegistryUserProductDTO(user.getId(), product.getId(), 1,
                        new BigDecimal("4"), null)));

        verifyNoInteractions(productRepository, registryUserService);
    }

    @Test
    void shouldRejectMissingProductBeforeCreatingRegistry() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(productRepository.findById(product.getId())).thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class, () -> controller.create(
                new RegistryUserProductDTO(user.getId(), product.getId(), 1,
                        new BigDecimal("4"), null)));

        verifyNoInteractions(registryUserService);
    }

    @Test
    void shouldReturnCompleteUserRegistryList() {
        RegistryUserProduct first = new RegistryUserProduct(user, 2,
                new BigDecimal("4"), new BigDecimal("20"), product);
        RegistryUserProduct second = new RegistryUserProduct(user, 1,
                new BigDecimal("2"), new BigDecimal("22"), product);
        List<RegistryUserProduct> expected = List.of(first, second);
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(userService.findAllProductrs(user)).thenReturn(expected);

        var response = controller.findByUser(user.getId());

        assertEquals(expected, response.getBody());
        assertEquals(200, response.getStatusCode().value());
        verify(userService).findAllProductrs(user);
    }

    @Test
    void shouldRejectMissingUserWhenListingRegistry() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class, () -> controller.findByUser(user.getId()));
        verifyNoInteractions(userService);
    }

    private void givenEntitiesExist() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(productRepository.findById(product.getId())).thenReturn(Optional.of(product));
    }
}
