package cannelo.marques.interdisciplinar.interdisciplinar.Repository;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.test.context.TestPropertySource;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;

/**
 * Valida a persistência e o carregamento do relacionamento
 * {@code User (1:N) -> RegistryUserProduct <- (N:1) Product} DEPOIS da
 * remoção da coleção {@code @OneToMany} de {@link User} (decisão 003).
 *
 * <p>A associação é unidirecional: {@code RegistryUserProduct} é o lado dono
 * (FKs {@code user_id} e {@code product_id}) e as consultas do usuário usam
 * {@code findByUser} — sem coleção JPA em {@link User}.
 */
@DataJpaTest
@TestPropertySource(properties = "spring.jpa.database-platform=org.hibernate.dialect.H2Dialect")
class RegistryUserProductRepositoryRelationshipTest {

    @Autowired
    private RegistryUserProductRepository repository;

    @Autowired
    private TestEntityManager entityManager;

    private User user;
    private Product television;

    @BeforeEach
    void setUp() {
        user = entityManager.persist(new User(0, "Quitto"));
        television = entityManager.persist(new Product(null, "Smart TV 43", "Samsung", "UN43AU7700",
                "Eletronicos", "TVs", new BigDecimal("120"), null));
        entityManager.flush();
    }

    @Test
    @DisplayName("persiste registro com FKs user_id/product_id e carrega via findByUser")
    void shouldPersistAndLoadRegistryByUser() {
        RegistryUserProduct registry = entityManager.persist(
                new RegistryUserProduct(user, 2, new BigDecimal("5"), null, television));
        entityManager.flush();
        entityManager.clear();

        List<RegistryUserProduct> loaded = repository.findByUser(user);

        assertEquals(1, loaded.size());
        RegistryUserProduct item = loaded.get(0);
        assertEquals(registry.getId(), item.getId(), "PK UUID própria preservada");
        assertNotNull(item.getUser(), "FK user_id carregada");
        assertEquals(user.getId(), item.getUser().getId(), "user_id aponta para o mesmo usuário");
        assertNotNull(item.getProduct(), "FK product_id carregada");
        assertEquals(television.getId(), item.getProduct().getId(), "product_id aponta para o mesmo produto");
        assertEquals(2, item.getQuantity());
        assertEquals(0, new BigDecimal("5").compareTo(item.getAvgActiveHours()));
    }

    @Test
    @DisplayName("carrega todos os registros de um usuário e nenhum de outro")
    void shouldLoadOnlyRegistriesOwnedByUser() {
        User otherUser = entityManager.persist(new User(0, "Maria"));
        entityManager.persist(new RegistryUserProduct(user, 1, new BigDecimal("4"), null, television));
        entityManager.persist(new RegistryUserProduct(otherUser, 3, new BigDecimal("8"), null, television));
        entityManager.flush();
        entityManager.clear();

        assertEquals(1, repository.findByUser(user).size(), "só o registro do usuário consultado");
        assertEquals(1, repository.findByUser(otherUser).size());
        assertEquals(2, repository.findAll().size());
    }

    @Test
    @DisplayName("usuário sem registros retorna lista vazia (nunca null) — decision_004")
    void shouldReturnEmptyListWhenUserHasNoRegistries() {
        List<RegistryUserProduct> loaded = repository.findByUser(user);

        assertNotNull(loaded);
        assertTrue(loaded.isEmpty());
    }

    @Test
    @DisplayName("findByUserAndProduct encontra apenas a associação do par exato")
    void shouldFindByUserAndProductPair() {
        Product fridge = entityManager.persist(new Product(null, "Geladeira", "Brastemp", null,
                "Eletrodomesticos", null, new BigDecimal("90"), null));
        entityManager.persist(new RegistryUserProduct(user, 1, new BigDecimal("24"), null, fridge));
        entityManager.persist(new RegistryUserProduct(user, 1, new BigDecimal("5"), null, television));
        entityManager.flush();
        entityManager.clear();

        List<RegistryUserProduct> pair = repository.findByUserAndProduct(user, television);

        assertEquals(1, pair.size());
        assertEquals(television.getId(), pair.get(0).getProduct().getId());
    }

    @Test
    @DisplayName("hours_standby do perfil individual persiste e carrega normalmente")
    void shouldPersistRegistryForProductWithoutStandbyData() {
        television.setAvgPowerW(new BigDecimal("120"));
        entityManager.persist(new RegistryUserProduct(user, 1, new BigDecimal("5"), new BigDecimal("19"), television));
        entityManager.flush();
        entityManager.clear();

        RegistryUserProduct loaded = repository.findByUser(user).get(0);

        assertEquals(0, new BigDecimal("19").compareTo(loaded.getHoursStandby()),
                "hours_standby do perfil individual persistido normalmente");
    }
}
