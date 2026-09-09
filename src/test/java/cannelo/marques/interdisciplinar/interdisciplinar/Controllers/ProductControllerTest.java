package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.argThat;
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

@ExtendWith(MockitoExtension.class)
class ProductControllerTest {

    @Mock
    private ProductRepository productRepository;

    private ProductController controller;
    private List<Product> products;

    @BeforeEach
    void setUp() {
        controller = new ProductController(productRepository);
        products = List.of(
                new Product(UUID.randomUUID()),
                new Product(UUID.randomUUID()));
    }

    @Test
    void shouldSearchByTrimmedNameWhenSearchIsProvided() {
        when(productRepository.findByNameContaining("television")).thenReturn(products);

        var response = controller.list("  television  ", 10);

        assertEquals(products, response.getBody());
        verify(productRepository).findByNameContaining("television");
        verify(productRepository).findByNameContaining("television");
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
    }

    @Test
    void shouldReturnAllProductsWhenSizeIsNegative() {
        when(productRepository.findAll()).thenReturn(products);

        var response = controller.list("", -1);

        assertEquals(products, response.getBody());
        verify(productRepository).findAll();
    }
}
