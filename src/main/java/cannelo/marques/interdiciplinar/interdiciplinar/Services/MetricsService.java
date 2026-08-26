package cannelo.marques.interdiciplinar.interdiciplinar.Services;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

import org.springframework.stereotype.Service;

import cannelo.marques.interdiciplinar.interdiciplinar.Models.Product;
import cannelo.marques.interdiciplinar.interdiciplinar.Models.User;
import cannelo.marques.interdiciplinar.interdiciplinar.Models.UserProduct;
import cannelo.marques.interdiciplinar.interdiciplinar.execepitons.ProductEmptyException;
import cannelo.marques.interdiciplinar.interdiciplinar.execepitons.UserNotFoundException;
import cannelo.marques.interdiciplinar.interdiciplinar.Repository.ProductRepository;
import cannelo.marques.interdiciplinar.interdiciplinar.Repository.UserProductRepository;
import cannelo.marques.interdiciplinar.interdiciplinar.Repository.UserReository;


@Service
public class MetricsService{
    private final UserProductRepository repository;
    private final UserReository userReository;
    private final ProductRepository productRepository;

    public MetricsService(UserProductRepository repository, UserReository userReository, ProductRepository productRepository){
        this.repository = repository;
        this.userReository = userReository;
        this.productRepository = productRepository;
    }

    public Optional<BigDecimal> calculateAverageEnergyByUser(User user){
        Objects.requireNonNull(user, "User cant be null");

        Optional.of(user)
                .filter(u -> userReository.existsById(u.getId()))
                .orElseThrow(() -> new UserNotFoundException(
                    "Parameter user can't be found in database"));

        List<UserProduct> userProductReg = repository.findByUser(user);
        Optional.of(userProductReg)
                .filter(reg -> !reg.isEmpty())
                .orElseThrow(() -> new ProductEmptyException(
                    "User product list cannot be empty"));

        BigDecimal consumeInYear = BigDecimal.ZERO;

        for (UserProduct up : userProductReg) {
            if (up.getProduct() != null && up.getProduct().getAvgPowerW() != null && up.getAvgActiveHours() != null) {
                BigDecimal consumption = up.getProduct().getAvgPowerW()
                        .multiply(up.getAvgActiveHours());

                consumeInYear = consumeInYear.add(
                        consumption.divide(BigDecimal.valueOf(1000))
                );
            }
        }

        return Optional.of(consumeInYear);
    }
}
