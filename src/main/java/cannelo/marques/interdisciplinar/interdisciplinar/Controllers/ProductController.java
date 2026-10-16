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
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductVoltageService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

@RestController
@RequestMapping("/products")
@Tag(name = "Products", description = "Endpoints de listagem de produtos cadastrados")
public class ProductController {

    private final ProductRepository productRepository;
    private final ProductVoltageService productVoltageService;
    private final ProductService productService;

    public ProductController(ProductRepository productRepository,
            ProductVoltageService productVoltageService,ProductService productService) {
        this.productRepository = productRepository;
        this.productVoltageService = productVoltageService;
        this.productService = productService;
    }

    @Operation(
            summary = "Lista produtos cadastrados",
            description = "Suporta paginação via 'size' e busca server-side via 'search'. " +
                          "A busca usa searchByTerm: case-insensitive (LOWER(x) LIKE %termo%) cobrindo " +
                          "nome, marca, modelo, categoria e subcategoria. " +
                          "Futuramente será otimizada com índice B-Tree no PostgreSQL."
    )

    @GetMapping("/category")
    public ResponseEntity<List<Product>> getCategoryByCategory(@RequestParam("name") String categoryName){
        return ResponseEntity.ok(productRepository.findByCategory(categoryName).stream().
        filter(product -> productService.isValidProduct(product))
        .toList());
    }

    @Operation(
            summary = "Lista categorias distintas de produtos disponíveis",
            description = "Retorna as categorias (não nulas, não vazias, sem duplicatas e ordenadas) " +
                          "dos produtos considerados válidos pelo ProductService. Usada pelo frontend " +
                          "para popular o select de filtro de categoria (complementa GET /category?name=...)."
    )
    @GetMapping("/categories")
    public ResponseEntity<List<String>> listCategories() {
        List<String> categories = productRepository.findAll().stream()
                .filter(productService::isValidProduct)
                .map(Product::getCategory)
                .filter(category -> category != null && !category.isBlank())
                .map(String::trim)
                .distinct()
                .sorted(String.CASE_INSENSITIVE_ORDER)
                .toList();

        return ResponseEntity.ok(categories);
    }

    @Deprecated
    @GetMapping
    public ResponseEntity<List<Product>> list(
            @RequestParam(required = false) String search,
            @RequestParam(required = false, defaultValue = "1000") int size) {

        List<Product> products;

        if (search != null && !search.isBlank()) {
            products = productRepository.searchByTerm(search.trim());
        } else if (size > 0) {
            products = productRepository.findAll(PageRequest.of(0, size)).getContent();
        } else {
            products = productRepository.findAll();
        }

        productVoltageService.decorate(products);

        return ResponseEntity.ok(products);
    }
}
