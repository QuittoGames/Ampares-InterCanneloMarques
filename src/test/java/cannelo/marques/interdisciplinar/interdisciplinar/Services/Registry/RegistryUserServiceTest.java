package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductForRegistry;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InvalidRegistryException;
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
        service = new RegistryUserService(registryRepository, userRepository, productRepository,
                new ProductForRegistryConverter());
        user = new User(3);
        // P=1000W / E=1460kWh derivariam 4.0000h ativas e 20.0000h standby
        // no fluxo antigo de derivação de horas — derivação agora proibida.
        product = new Product(UUID.randomUUID(), "Device", "Brand", "Model", "electronics", "sub",
                new BigDecimal("1000"), new BigDecimal("1460"));
        lenient().when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        lenient().when(productRepository.findById(product.getId())).thenReturn(Optional.of(product));
        lenient().when(registryRepository.findByUserAndProduct(user, product)).thenReturn(List.of());
    }

    private ProductForRegistry request(Integer quantity, BigDecimal active, BigDecimal standby) {
        return new ProductForRegistry(user.getId(), product.getId(),
                quantity == null ? 1 : quantity, active, standby);
    }

    @Test
    @DisplayName("registerUserProduct: resolve user/product, converte e salva o request literal")
    void registerUserProductSavesConvertedRequest() {
        when(registryRepository.save(any(RegistryUserProduct.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        RegistryUserProduct result = service.registerUserProduct(
                request(2, new BigDecimal("3.5"), new BigDecimal("20.5")));

        ArgumentCaptor<RegistryUserProduct> captor = ArgumentCaptor.forClass(RegistryUserProduct.class);
        verify(registryRepository).save(captor.capture());
        RegistryUserProduct saved = captor.getValue();
        assertEquals(2, saved.getQuantity());
        assertEquals(0, new BigDecimal("3.5").compareTo(saved.getAvgActiveHours()));
        assertEquals(0, new BigDecimal("20.5").compareTo(saved.getHoursStandby()));
        assertSame(user, saved.getUser());
        assertSame(product, saved.getProduct());
        assertSame(saved, result);
    }

    @Test
    @DisplayName("hoursStandby null permanece null — NUNCA vira 24 − avgActiveHours")
    void hoursStandbyNullStaysNullNeverDerived() {
        when(registryRepository.save(any(RegistryUserProduct.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        // avgActiveHours 6h: o fluxo antigo teria derivado 24−6=18h standby
        // (e 4h/20h do produto). Ambas as derivações estão proibidas.
        RegistryUserProduct result = service.registerUserProduct(
                request(1, new BigDecimal("6"), null));

        assertNull(result.getHoursStandby());
        assertEquals(0, new BigDecimal("6").compareTo(result.getAvgActiveHours()));
    }

    @Test
    @DisplayName("quantity 0 é rejeitada com InvalidRegistryException explícita")
    void rejectsZeroQuantity() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(0, new BigDecimal("4"), null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("quantity negativa é rejeitada com InvalidRegistryException explícita")
    void rejectsNegativeQuantity() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(-5, new BigDecimal("4"), null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("avgActiveHours negativa é rejeitada — nunca zerada silenciosamente")
    void rejectsNegativeAvgActiveHours() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("-1"), null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("avgActiveHours > 24 é rejeitada com InvalidRegistryException explícita")
    void rejectsAvgActiveHoursAbove24() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("24.5"), null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("avgActiveHours null é rejeitada — o backend não deriva do produto")
    void rejectsNullAvgActiveHours() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(1, null, null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("hoursStandby > 24 é rejeitada com InvalidRegistryException explícita")
    void rejectsHoursStandbyAbove24() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("4"), new BigDecimal("25"))));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("hoursStandby negativa é rejeitada com InvalidRegistryException explícita")
    void rejectsNegativeHoursStandby() {
        assertThrows(InvalidRegistryException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("4"), new BigDecimal("-0.5"))));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("usuário inexistente → UserNotFoundException antes de salvar")
    void rejectsUnknownUserBeforeSaving() {
        when(userRepository.findById(user.getId())).thenReturn(Optional.empty());

        assertThrows(UserNotFoundException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("4"), null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("produto inexistente → ProductNotFoundException antes de salvar")
    void rejectsUnknownProductBeforeSaving() {
        when(productRepository.findById(product.getId())).thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("4"), null)));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("par (user, product) duplicado → mantém a regra atual (IllegalStateException)")
    void rejectsDuplicateUserProductRegistry() {
        RegistryUserProduct existing = new RegistryUserProduct(user, 1,
                new BigDecimal("4"), new BigDecimal("20"), product);
        when(registryRepository.findByUserAndProduct(user, product)).thenReturn(List.of(existing));

        assertThrows(IllegalStateException.class,
                () -> service.registerUserProduct(request(1, new BigDecimal("4"), new BigDecimal("20"))));
        verify(registryRepository, never()).save(any());
    }

    @Test
    @DisplayName("rejeita request nulo")
    void rejectsNullRequest() {
        assertThrows(NullPointerException.class, () -> service.registerUserProduct(null));
    }

    @Test
    @DisplayName("createRegistry (legado UserService) delega o contrato para registerUserProduct")
    void legacyCreateRegistryDelegatesToRegisterUserProduct() {
        when(registryRepository.save(any(RegistryUserProduct.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        RegistryUserProduct result = service.createRegistry(user, product, 2,
                new BigDecimal("3.5"), new BigDecimal("20.5"));

        assertEquals(2, result.getQuantity());
        assertEquals(0, new BigDecimal("3.5").compareTo(result.getAvgActiveHours()));
        assertEquals(0, new BigDecimal("20.5").compareTo(result.getHoursStandby()));
        assertSame(user, result.getUser());
        assertNull(result.getId());
    }

    @Test
    @DisplayName("createRegistry legado com horas null lança erro explícito — derivação removida")
    void legacyCreateRegistryNoLongerDerivesHours() {
        assertThrows(InvalidRegistryException.class,
                () -> service.createRegistry(user, product, 1, null, null));
        verify(registryRepository, never()).save(any());
    }
}
