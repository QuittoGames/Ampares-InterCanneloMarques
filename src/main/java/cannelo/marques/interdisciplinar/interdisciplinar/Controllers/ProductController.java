package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import java.util.List;

import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

@RestController
@RequestMapping("/products")
@Tag(name = "Products", description = "Endpoints de listagem de produtos cadastrados")
public class ProductController {

    private final ProductRepository productRepository;

    public ProductController(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    @Operation(
            summary = "Lista produtos cadastrados",
            description = "Suporta paginação via 'size' e filtro por nome via 'search'. " +
                          "A busca por nome usa findByNameContaining (LIKE %x%) do JPA. " +
                          "Futuramente será otimizada com índice B-Tree no PostgreSQL."
    )
    @GetMapping
    public ResponseEntity<List<Product>> list(
            @RequestParam(required = false) String search,
            @RequestParam(required = false, defaultValue = "1000") int size) {

        List<Product> products;

        if (search != null && !search.isBlank()) {
            products = productRepository.findByNameContaining(search.trim());
        } else if (size > 0) {
            products = productRepository.findAll(PageRequest.of(0, size)).getContent();
        } else {
            products = productRepository.findAll();
        }

        return ResponseEntity.ok(products);
    }
}
