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

@RestController
@RequestMapping("/api/metrics")
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

    @PostMapping("/users/average-energy")
    public ResponseEntity<BigDecimal> averageEnergyByUser(@RequestBody MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateAverageEnergyByUser(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @PostMapping("/users/total-energy")
    public ResponseEntity<BigDecimal> totalEnergyByUser(@RequestBody MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateEnergyByUser(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

    @PostMapping("/users/most-consumer-product")
    public ResponseEntity<Product> mostConsumerProduct(@RequestBody MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<Product> result = metricsService.calculateMostConsumerProduct(user);
        return result
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/users/most-consumer-products")
    public ResponseEntity<List<Product>> mostConsumerProductsForCategory(
            @RequestBody MetricsByCategoryDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<List<Product>> result =
                metricsService.mostConsumerProductsForCategory(user, dto.category());
        return result
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/users/standby-consumption-avg")
    public ResponseEntity<BigDecimal> standbyConsumeAvg(@RequestBody MetricsByUserDTO dto) {
        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Optional<BigDecimal> result = metricsService.calculateStandbyConsumeAvg(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }

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
