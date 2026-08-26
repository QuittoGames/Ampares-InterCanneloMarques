package cannelo.marques.interdiciplinar.interdiciplinar.Controllers;

import java.math.BigDecimal;
import java.util.Optional;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdiciplinar.interdiciplinar.Models.User;
import cannelo.marques.interdiciplinar.interdiciplinar.Repository.UserReository;
import cannelo.marques.interdiciplinar.interdiciplinar.Services.MetricsService;
import cannelo.marques.interdiciplinar.interdiciplinar.execepitons.UserNotFoundException;

@RestController
@RequestMapping("/api/metrics")
public class MetricsController {

    private final MetricsService metricsService;
    private final UserReository userReository;

    public MetricsController(MetricsService metricsService, UserReository userReository) {
        this.metricsService = metricsService;
        this.userReository = userReository;
    }

    @GetMapping("/users/{userId}/average-energy")
    public ResponseEntity<BigDecimal> averageEnergyByUser(@PathVariable int userId) {
        User user = userReository.findById(userId)
                .orElseThrow(() -> new UserNotFoundException("User not found: " + userId));

        Optional<BigDecimal> result = metricsService.calculateAverageEnergyByUser(user);
        return ResponseEntity.ok(result.orElse(BigDecimal.ZERO));
    }
}
