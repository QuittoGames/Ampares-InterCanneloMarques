package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import java.math.BigDecimal;
import java.util.Optional;
import java.util.function.Function;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.UserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;

@Service
public class UserService {

    private final UserProductRepository repository;
    private final UserRepository UserRepository;
    private final ProductRepository productRepository;

    public UserService(UserProductRepository repository, UserRepository UserRepository, ProductRepository productRepository){
        this.repository = repository;
        this.UserRepository = UserRepository;
        this.productRepository = productRepository;
    }

    public BigDecimal calculateConsumption(UserProduct userProduct,Function<UserProduct, BigDecimal> hoursProvider) {
        BigDecimal hours = hoursProvider.apply(userProduct);

        if (userProduct.getProduct() == null ||
            userProduct.getProduct().getAvgPowerW() == null ||
            hours == null) {
            return BigDecimal.ZERO;
        }

        return userProduct.getProduct()
                .getAvgPowerW()
                .multiply(hours)
                .divide(BigDecimal.valueOf(1000));
    }

    public boolean userExists(User user){
        return Optional.ofNullable(user)
                .map(User::getId)
                .map(UserRepository::existsById)
                .orElse(false);
    }
}
