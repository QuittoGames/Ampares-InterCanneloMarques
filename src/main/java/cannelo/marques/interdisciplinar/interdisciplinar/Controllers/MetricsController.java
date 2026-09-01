package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsByCategoryDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsByUserDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.DTO.MetricsStandbyByProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.MetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

@RestController
@RequestMapping("/api/metrics")
@Tag(name = "Metrics", description = "Endpoints de cálculo de métricas de consumo")
public class MetricsController {

    private final MetricsService<User, BigDecimal> metricsService;
    private final UserRepository userRepository;
    private final ProductRepository productRepository;

    public MetricsController(MetricsService<User, BigDecimal> metricsService, UserRepository userRepository,
            ProductRepository productRepository) {
        this.metricsService = metricsService;
        this.userRepository = userRepository;
        this.productRepository = productRepository;
    }

    @Operation(
        summary = "Calcula consumo médio de energia por produto",
        description = "Retorna a média do consumo anual em kWh dos produtos registrados por um usuário."
    )
    @PostMapping("/users/average-energy")
    public ResponseEntity<BigDecimal> averageEnergyByUser(@RequestBody MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateAverageEnergyByUser(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @Operation(
        summary = "Calcula consumo total de energia",
        description = "Retorna a soma do consumo anual em kWh de todos os produtos registrados por um usuário."
    )
    @PostMapping("/users/total-energy")
    public ResponseEntity<BigDecimal> totalEnergyByUser(@RequestBody MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateEnergyByUser(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @Operation(
        summary = "Retorna o produto de maior consumo",
        description = "Retorna o Product (entidade JPA) com maior avgPowerW × avgActiveHours."
    )
    @PostMapping("/users/most-consumer-product")
    public ResponseEntity<Product> mostConsumerProduct(@RequestBody MetricsByUserDTO dto) {
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
    public ResponseEntity<BigDecimal> standbyConsumeAvg(@RequestBody MetricsByUserDTO dto) {
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

        Product product = productRepository.findById(dto.productId())
                .orElseThrow(() -> new ProductNotFoundException("Product not found: " + dto.productId()));

        Optional<BigDecimal> result = metricsService.calculateStandbyConsumesForProduct(user, product);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }
}
