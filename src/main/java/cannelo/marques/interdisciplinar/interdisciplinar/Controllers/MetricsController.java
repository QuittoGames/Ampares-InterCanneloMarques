package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import java.math.BigDecimal;
import java.util.List;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ResultDTO;
import java.util.Optional;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsByUserDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsStandbyByProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.SearchResponseDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductVoltageService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.interfaces.MetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import jakarta.validation.Valid;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;


@RestController
@RequestMapping("/api/metrics")
@Tag(name = "Metrics", description = "Endpoints de cálculo de métricas de consumo")
public class MetricsController {

    private final UserService userService;
    private final MetricsService<User, BigDecimal> metricsService;
    private final UserRepository userRepository;
    private final ProductRepository productRepository;
    private final ProductService productService;
    private final ProductVoltageService productVoltageService;

    public MetricsController(MetricsService<User, BigDecimal> metricsService, UserRepository userRepository,
            ProductRepository productRepository,ProductService productService,UserService userService,
            ProductVoltageService productVoltageService) {
        this.metricsService = metricsService;
        this.userRepository = userRepository;
        this.productRepository = productRepository;
        this.productService = productService;
        this.userService = userService;
        this.productVoltageService = productVoltageService;
    }

    @PostMapping("/users/calculate")
    public ResponseEntity<ResultDTO> calculateUser(@RequestBody @Valid MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        return metricsService.calculate(user)
                .map(result -> {
                    productVoltageService.decorate(
                            result.productsList().stream()
                                    .map(RegistryUserProduct::getProduct)
                                    .toList());
                    return ResponseEntity.ok(result);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(
        summary = "Calcula consumo médio anual por produto",
        description = "Retorna a média do consumo anual em kWh entre os produtos registrados por um usuário."
    )
    @PostMapping("/users/average-energy")
    public ResponseEntity<BigDecimal> averageEnergyByUser(@RequestBody @Valid MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateAverageEnergyByUser(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @Operation(
        summary = "Retorna o produto de maior consumo",
        description = "Retorna o Product (entidade JPA) com maior avgPowerW × avgActiveHours."
    )
    @PostMapping("/users/most-consumer-product")
    public ResponseEntity<Product> mostConsumerProduct(@RequestBody @Valid MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<Product> result = metricsService.calculateMostConsumerProduct(user);
        return result
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(
        summary = "Calcula consumo médio em standby",
        description = "Retorna a média do consumo anual em standby (kWh) entre os produtos do usuário."
    )
    @PostMapping("/users/standby-consumption-avg")
    public ResponseEntity<BigDecimal> standbyConsumeAvg(@RequestBody @Valid MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateStandbyConsumeAvg(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @Operation(
        summary = "Calcula consumo em standby de um produto específico",
        description = "Retorna o consumo anual em standby (kWh) de um produto específico do usuário."
    )
    @PostMapping("/users/standby-consumption-by-product")
    public ResponseEntity<BigDecimal> standbyConsumeByProduct(@RequestBody MetricsStandbyByProductDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Product product = productService.findById(dto.productId());

        Optional<BigDecimal> result = metricsService.calculateStandbyConsumesForProduct(user, product);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @GetMapping("/search/{userId}")
    public SearchResponseDTO searchProduct(
            @PathVariable Integer userId,
            @RequestParam String search
    ) {
        User user = userRepository.findById(userId)
                .orElseThrow(() ->
                        new UserNotFoundException("User not found: " + userId)
                );

        Optional<List<Product>> productsOptional = productService.searchProduct(user, search);
        List<Product> products = productsOptional.orElseThrow(() -> new ProductNotFoundException("No products found for search: " + search));

        if (products.isEmpty()) {
            throw new ProductNotFoundException("No products found for search: " + search);
        }

        Product firstProduct = products.get(0);
        return new SearchResponseDTO(firstProduct.getId(), firstProduct.getName());
    }
}
