package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductForRegistry;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry.ProductForRegistryConverter;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry.RegistryUserService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InvalidRegistryException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;

/**
 * Contrato HTTP de {@code /registryUserProducts} sobre o DTO
 * {@link ProductForRegistry} (Cenário C do registro coberto ponta a ponta:
 * controller → RegistryUserService real → conversor).
 */
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
    @Mock
    private RegistryUserProductRepository registryRepository;

    private User user;
    private Product product;

    @BeforeEach
    void setUp() {
        user = new User(4);
        product = new Product(UUID.randomUUID(), "Device", "Brand", "Model",
                "electronics", "sub", new BigDecimal("1000"), new BigDecimal("1460"));
    }

    /** Controller com serviço mockado — usado para verificar a delegação. */
    private RegistryUserProductController controllerWithMockedService() {
        return new RegistryUserProductController(registryUserService, userService, userRepository);
    }

    /** Controller com serviço REAL — exercita o Cenário C ponta a ponta. */
    private RegistryUserProductController controllerWithRealService() {
        RegistryUserService realService = new RegistryUserService(
                registryRepository, userRepository, productRepository,
                new ProductForRegistryConverter());
        return new RegistryUserProductController(realService, userService, userRepository);
    }

    private ProductForRegistry request(Integer quantity, BigDecimal active, BigDecimal standby) {
        return new ProductForRegistry(user.getId(), product.getId(),
                quantity == null ? 1 : quantity, active, standby);
    }

    private void givenUserAndProductExist() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(productRepository.findById(product.getId())).thenReturn(Optional.of(product));
    }

    // ------------------------------------------------------------------
    // Delegação do POST /registryUserProducts
    // ------------------------------------------------------------------

    @Test
    @DisplayName("POST: delega o ProductForRegistry exato ao serviço e responde 200 com a entidade")
    void shouldDelegateCreateToServiceWithTheExactDto() {
        ProductForRegistry dto = request(3, new BigDecimal("4.25"), new BigDecimal("19.75"));
        RegistryUserProduct created = new RegistryUserProduct(
                user, 3, new BigDecimal("4.25"), new BigDecimal("19.75"), product);
        when(registryUserService.registerUserProduct(dto)).thenReturn(created);

        var response = controllerWithMockedService().create(dto);

        assertSame(created, response.getBody());
        assertEquals(200, response.getStatusCode().value());
        verify(registryUserService).registerUserProduct(dto);
    }

    // ------------------------------------------------------------------
    // Cenário C — validação ponta a ponta (serviço real)
    // ------------------------------------------------------------------

    @Test
    @DisplayName("Cenário C: quantity 0 → InvalidRegistryException")
    void shouldRejectZeroQuantity() {
        givenUserAndProductExist();

        assertThrows(InvalidRegistryException.class,
                () -> controllerWithRealService().create(
                        request(0, new BigDecimal("4"), null)));
        verifyNoInteractions(registryRepository);
    }

    @Test
    @DisplayName("Cenário C: quantity negativa → InvalidRegistryException")
    void shouldRejectNegativeQuantity() {
        givenUserAndProductExist();

        assertThrows(InvalidRegistryException.class,
                () -> controllerWithRealService().create(
                        request(-3, new BigDecimal("4"), null)));
        verifyNoInteractions(registryRepository);
    }

    @Test
    @DisplayName("Cenário C: avgActiveHours negativa → InvalidRegistryException (nunca zerada)")
    void shouldRejectNegativeAvgActiveHours() {
        givenUserAndProductExist();

        assertThrows(InvalidRegistryException.class,
                () -> controllerWithRealService().create(
                        request(1, new BigDecimal("-0.5"), null)));
        verifyNoInteractions(registryRepository);
    }

    @Test
    @DisplayName("Cenário C: avgActiveHours > 24 → InvalidRegistryException")
    void shouldRejectAvgActiveHoursAbove24() {
        givenUserAndProductExist();

        assertThrows(InvalidRegistryException.class,
                () -> controllerWithRealService().create(
                        request(1, new BigDecimal("30"), null)));
        verifyNoInteractions(registryRepository);
    }

    @Test
    @DisplayName("Cenário C: hoursStandby > 24 → InvalidRegistryException")
    void shouldRejectHoursStandbyAbove24() {
        givenUserAndProductExist();

        assertThrows(InvalidRegistryException.class,
                () -> controllerWithRealService().create(
                        request(1, new BigDecimal("4"), new BigDecimal("24.5"))));
        verifyNoInteractions(registryRepository);
    }

    @Test
    @DisplayName("Cenário C: usuário inexistente → UserNotFoundException antes de tocar no produto")
    void shouldRejectMissingUserWithoutResolvingProduct() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controllerWithRealService().create(
                        request(1, new BigDecimal("4"), null)));

        verifyNoInteractions(productRepository, registryRepository);
    }

    @Test
    @DisplayName("Cenário C: produto inexistente → ProductNotFoundException antes de salvar")
    void shouldRejectMissingProductBeforeSaving() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(productRepository.findById(product.getId())).thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class,
                () -> controllerWithRealService().create(
                        request(1, new BigDecimal("4"), null)));
        verifyNoInteractions(registryRepository);
    }

    @Test
    @DisplayName("Cenário C: registro duplicado → mantém a regra atual (IllegalStateException)")
    void shouldRejectDuplicateRegistry() {
        givenUserAndProductExist();
        when(registryRepository.findByUserAndProduct(user, product))
                .thenReturn(List.of(new RegistryUserProduct(user, 1,
                        new BigDecimal("4"), new BigDecimal("20"), product)));

        assertThrows(IllegalStateException.class,
                () -> controllerWithRealService().create(
                        request(1, new BigDecimal("4"), new BigDecimal("20"))));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("Cenário C: hoursStandby null permanece null (não vira 24 − ativo) e avgActiveHours é o do request")
    void shouldKeepNullHoursStandbyAndRequestAvgActiveHours() {
        givenUserAndProductExist();
        when(registryRepository.findByUserAndProduct(user, product)).thenReturn(List.of());
        when(registryRepository.save(any(RegistryUserProduct.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        // Produto derivaria 4h ativas / 20h standby no fluxo antigo; request manda.
        var response = controllerWithRealService().create(
                request(1, new BigDecimal("6"), null));

        RegistryUserProduct body = response.getBody();
        assertEquals(200, response.getStatusCode().value());
        assertNull(body.getHoursStandby());
        assertEquals(0, new BigDecimal("6").compareTo(body.getAvgActiveHours()));
        assertSame(user, body.getUser());
        assertSame(product, body.getProduct());
    }

    // ------------------------------------------------------------------
    // GET /registryUserProducts/user/{userId}
    // ------------------------------------------------------------------

    @Test
    @DisplayName("GET: retorna a lista completa dos registros do usuário")
    void shouldReturnCompleteUserRegistryList() {
        RegistryUserProduct first = new RegistryUserProduct(user, 2,
                new BigDecimal("4"), new BigDecimal("20"), product);
        RegistryUserProduct second = new RegistryUserProduct(user, 1,
                new BigDecimal("2"), new BigDecimal("22"), product);
        List<RegistryUserProduct> expected = List.of(first, second);
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(userService.findAllProductrs(user)).thenReturn(expected);

        var response = controllerWithMockedService().findByUser(user.getId());

        assertEquals(expected, response.getBody());
        assertEquals(200, response.getStatusCode().value());
        verify(userService).findAllProductrs(user);
    }

    @Test
    @DisplayName("GET: usuário inexistente → UserNotFoundException")
    void shouldRejectMissingUserWhenListingRegistry() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> controllerWithMockedService().findByUser(user.getId()));
        verifyNoInteractions(userService);
    }
}
