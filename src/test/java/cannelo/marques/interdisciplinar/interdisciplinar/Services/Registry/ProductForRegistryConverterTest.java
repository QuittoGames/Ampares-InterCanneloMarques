package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductForRegistry;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;

/**
 * Testes do conversor puro {@link ProductForRegistryConverter}
 * (mapeamento sem Spring, sem repositórios, sem regra de negócio).
 */
class ProductForRegistryConverterTest {

    private ProductForRegistryConverter converter;
    private User user;
    private Product product;

    @BeforeEach
    void setUp() {
        converter = new ProductForRegistryConverter();
        user = new User(7);
        product = new Product(UUID.randomUUID(), "Device", "Brand", "Model",
                "electronics", "sub", new BigDecimal("1000"), new BigDecimal("1460"));
    }

    @Test
    @DisplayName("mapeia todos os campos escalares e associa as instâncias resolvidas")
    void mapsAllFieldsAndAssociations() {
        ProductForRegistry request = new ProductForRegistry(
                user.getId(), product.getId(), 3,
                new BigDecimal("4.25"), new BigDecimal("19.75"));

        RegistryUserProduct entity = converter.toEntity(request, user, product);

        assertEquals(3, entity.getQuantity());
        assertEquals(0, new BigDecimal("4.25").compareTo(entity.getAvgActiveHours()));
        assertEquals(0, new BigDecimal("19.75").compareTo(entity.getHoursStandby()));
        assertSame(user, entity.getUser());
        assertSame(product, entity.getProduct());
    }

    @Test
    @DisplayName("hoursStandby null permanece null — NUNCA vira 24 − avgActiveHours")
    void keepsNullHoursStandbyNullEvenWhenProductAllowsDerivation() {
        // produto com P/E que permitiriam derivar 4h ativas / 20h standby —
        // o conversor não deve derivar nada.
        ProductForRegistry request = new ProductForRegistry(
                user.getId(), product.getId(), 1,
                new BigDecimal("6"), null);

        RegistryUserProduct entity = converter.toEntity(request, user, product);

        assertNull(entity.getHoursStandby());
        assertEquals(0, new BigDecimal("6").compareTo(entity.getAvgActiveHours()));
    }

    @Test
    @DisplayName("usa avgActiveHours literal do request — não substitui pelo valor derivado do produto")
    void copiesAvgActiveHoursLiterally() {
        ProductForRegistry request = new ProductForRegistry(
                user.getId(), product.getId(), 1,
                new BigDecimal("3.5"), new BigDecimal("20.5"));

        RegistryUserProduct entity = converter.toEntity(request, user, product);

        // P=1000W / E=1460kWh derivaria 4.0000 — o request manda.
        assertEquals(0, new BigDecimal("3.5").compareTo(entity.getAvgActiveHours()));
    }

    @Test
    @DisplayName("PK da associação não é setada — fica por conta do JPA")
    void doesNotSetPrimaryKey() {
        ProductForRegistry request = new ProductForRegistry(
                user.getId(), product.getId(), 1,
                new BigDecimal("4"), new BigDecimal("20"));

        RegistryUserProduct entity = converter.toEntity(request, user, product);

        assertNull(entity.getId());
    }

    @Test
    @DisplayName("rejeita request, user ou product nulos (contrato do conversor)")
    void rejectsNullArguments() {
        ProductForRegistry request = new ProductForRegistry(
                user.getId(), product.getId(), 1,
                new BigDecimal("4"), new BigDecimal("20"));

        assertThrows(NullPointerException.class, () -> converter.toEntity(null, user, product));
        assertThrows(NullPointerException.class, () -> converter.toEntity(request, null, product));
        assertThrows(NullPointerException.class, () -> converter.toEntity(request, user, null));
    }
}
