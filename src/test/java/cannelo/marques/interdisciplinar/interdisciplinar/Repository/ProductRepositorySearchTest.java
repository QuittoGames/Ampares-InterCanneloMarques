package cannelo.marques.interdisciplinar.interdisciplinar.Repository;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.test.context.TestPropertySource;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;

/**
 * Valida a semântica da busca server-side usada pelo ProductController:
 * case-insensitive, múltiplos campos e tolerância a campos nulos.
 */
@DataJpaTest
@TestPropertySource(properties = "spring.jpa.database-platform=org.hibernate.dialect.H2Dialect")
class ProductRepositorySearchTest {

    @Autowired
    private ProductRepository repository;

    @Autowired
    private TestEntityManager entityManager;

    private Product television;
    private Product refrigerator;
    private Product fan;

    @BeforeEach
    void setUp() {
        television = persistProduct("Smart TV 43 polegadas", "Samsung", "UN43AU7700",
                "Eletronicos", "TVs", new BigDecimal("120"));
        refrigerator = persistProduct("Geladeira Frost Free", "Brastemp", "BRM44",
                "Eletrodomesticos", "Refrigeracao", new BigDecimal("90"));
        fan = persistProduct("Ventilador de teto", null, null, null, null, new BigDecimal("60"));

        entityManager.flush();
    }

    @Test
    void shouldMatchNameIgnoringCase() {
        assertOnlyMatch("sMaRt tV", television);
        assertOnlyMatch("GELADEIRA", refrigerator);
    }

    @Test
    void shouldMatchBrandModelCategoryAndSubcategory() {
        assertOnlyMatch("SAMSUNG", television);
        assertOnlyMatch("un43au", television);
        assertOnlyMatch("ELETRONICOS", television);
        assertOnlyMatch("refrigeracao", refrigerator);
    }

    @Test
    void shouldReturnEmptyListWhenNoProductMatches() {
        assertTrue(repository.searchByTerm("produto inexistente").isEmpty());
    }

    @Test
    void shouldIgnoreNullFieldsWithoutFailing() {
        assertOnlyMatch("VENTILADOR", fan);
        assertOnlyMatch("samsung", television);
    }

    private void assertOnlyMatch(String term, Product expected) {
        List<Product> results = repository.searchByTerm(term);

        assertEquals(1, results.size(), () -> "termo '" + term + "' deveria casar exatamente 1 produto");
        assertEquals(expected.getId(), results.get(0).getId(), () -> "termo '" + term + "' casou o produto errado");
    }

    private Product persistProduct(String name, String brand, String model,
                                   String category, String subcategory, BigDecimal avgPowerW) {
        Product product = new Product();
        product.setName(name);
        product.setBrand(brand);
        product.setModel(model);
        product.setCategory(category);
        product.setSubcategory(subcategory);
        product.setAvgPowerW(avgPowerW);

        return entityManager.persist(product);
    }
}
