package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductVoltageService;

@ExtendWith(MockitoExtension.class)
class ProductControllerTest {

    @Mock
    private ProductRepository productRepository;

    @Mock
    private ProductVoltageService productVoltageService;

    @Mock
    private ProductService productService;

    private ProductController controller;
    private List<Product> products;

    @BeforeEach
    void setUp() {
        controller = new ProductController(productRepository, productVoltageService, productService);
        products = List.of(
                new Product(UUID.randomUUID()),
                new Product(UUID.randomUUID()));
    }

    @Test
    void shouldSearchByTrimmedTermWhenSearchIsProvided() {
        when(productRepository.searchByTerm("television")).thenReturn(products);

        var response = controller.list("  television  ", 10);

        assertEquals(products, response.getBody());
        verify(productRepository).searchByTerm("television");
        verify(productRepository, never()).findAll(any(Pageable.class));
        verify(productVoltageService).decorate(products);
    }

    @Test
    void shouldUseDefaultPositivePageSizeWhenSearchIsBlank() {
        when(productRepository.findAll(argThat((Pageable pageable) ->
                pageable.getPageNumber() == 0 && pageable.getPageSize() == 1000)))
                .thenReturn(new PageImpl<>(products));

        var response = controller.list("   ", 1000);

        assertEquals(products, response.getBody());
        verify(productRepository).findAll(argThat((Pageable pageable) ->
                pageable.getPageNumber() == 0 && pageable.getPageSize() == 1000));
        verify(productVoltageService).decorate(products);
    }

    @Test
    void shouldUseRequestedPositivePageSize() {
        when(productRepository.findAll(argThat((Pageable pageable) ->
                pageable.getPageNumber() == 0 && pageable.getPageSize() == 25)))
                .thenReturn(new PageImpl<>(products));

        var response = controller.list(null, 25);

        assertEquals(products, response.getBody());
        verify(productRepository).findAll(argThat((Pageable pageable) ->
                pageable.getPageNumber() == 0 && pageable.getPageSize() == 25));
    }

    @Test
    void shouldReturnAllProductsWhenSizeIsZero() {
        when(productRepository.findAll()).thenReturn(products);

        var response = controller.list(null, 0);

        assertEquals(products, response.getBody());
        verify(productRepository).findAll();
        verify(productVoltageService).decorate(products);
    }

    @Test
    void shouldReturnAllProductsWhenSizeIsNegative() {
        when(productRepository.findAll()).thenReturn(products);

        var response = controller.list("", -1);

        assertEquals(products, response.getBody());
        verify(productRepository).findAll();
    }

    @Test
    void shouldListDistinctTrimmedValidCategoriesSortedCaseInsensitive() {
        Product geladeira = new Product(UUID.randomUUID());
        geladeira.setCategory("  Geladeira  ");
        Product televisao = new Product(UUID.randomUUID());
        televisao.setCategory("Televisão");
        Product geladeiraDuplicada = new Product(UUID.randomUUID());
        geladeiraDuplicada.setCategory("Geladeira");
        Product invalido = new Product(UUID.randomUUID());
        invalido.setCategory("Ar-condicionado");
        Product semCategoria = new Product(UUID.randomUUID());

        when(productRepository.findAll())
                .thenReturn(List.of(geladeira, televisao, geladeiraDuplicada, invalido, semCategoria));
        when(productService.isValidProduct(any(Product.class)))
                .thenAnswer(invocation -> invocation.getArgument(0) != invalido);

        var response = controller.listCategories();

        assertEquals(List.of("Geladeira", "Televisão"), response.getBody());
    }

    @Test
    void shouldReturnEmptyCategoryListWhenThereAreNoProducts() {
        when(productRepository.findAll()).thenReturn(List.of());

        var response = controller.listCategories();

        assertTrue(response.getBody().isEmpty());
    }
}
