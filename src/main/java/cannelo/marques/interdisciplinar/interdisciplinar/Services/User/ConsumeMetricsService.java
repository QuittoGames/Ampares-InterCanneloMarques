package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.UserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.MetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductEmptyException;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserProductRepository;

@Service
public class ConsumeMetricsService implements MetricsService<User,BigDecimal>{
    private final UserProductRepository repository;
    private final UserService userService;

    public ConsumeMetricsService(UserProductRepository repository, UserService userService){
        this.repository = repository;
        this.userService = userService;
    }

    @Override
    public Optional<BigDecimal> calculateEnergyByUser(User user){
        Objects.requireNonNull(user, "User cant be ");

        userService.userExists(user);

        BigDecimal consumeInYear = BigDecimal.ZERO;

        List<UserProduct> userProductReg = repository.findByUser(user);
        Optional.of(userProductReg)
                .filter(reg -> !reg.isEmpty())
                .orElseThrow(() -> new ProductEmptyException(
                "User product list cannot be empty"));

        for (UserProduct up: userProductReg){
            consumeInYear = consumeInYear.add(userService.calculateConsumption(up,UserProduct::getAvgActiveHours));
        }

        return Optional.of(consumeInYear);
    }

    @Override
    public Optional<BigDecimal> calculateAverageEnergyByUser(User user){
        Objects.requireNonNull(user, "User cant be ");

        userService.userExists(user);

        BigDecimal consumeInYear = BigDecimal.ZERO;

        List<UserProduct> userProductReg = repository.findByUser(user);
        Optional.of(userProductReg)
                .filter(reg -> !reg.isEmpty())
                .orElseThrow(() -> new ProductEmptyException(
                "User product list cannot be empty"));

        for (UserProduct up: userProductReg){
            consumeInYear = consumeInYear.add(userService.calculateConsumption(up,UserProduct::getAvgActiveHours));
        }

         return avg(consumeInYear, userProductReg);
    }

    @Override
    public Optional<Product> calculateMostConsumerProduct(User user){
        Objects.requireNonNull(user, "User cant be null");

        List<UserProduct> userProductReg = getProductRegistry(user);
        Optional<Product> mostConsumerProduct = userProductReg.stream()
            .filter(up -> up.getProduct() != null)
            .filter(up -> up.getProduct().getAvgPowerW() != null)
            .max(Comparator.comparing(
                up -> up.getProduct()
                    .getAvgPowerW()
                    .multiply(up.getAvgActiveHours())
            ))
            .map(UserProduct::getProduct);

        return mostConsumerProduct;
    }

    @Override
    public Optional<List<Product>> mostConsumerProductsForCategory(User user, String category){
        Objects.requireNonNull(user);
        Objects.requireNonNull(category, "Category cant be null");

        List<UserProduct> userProductReg = getProductRegistry(user);
        List<Product> products = userProductReg.stream()
            .filter(up -> up.getProduct() != null)
            .filter(up -> category.equalsIgnoreCase(up.getProduct().getCategory()))
            .filter(up -> up.getProduct().getAvgPowerW() != null)
            .filter(up -> up.getAvgActiveHours() != null)

            .sorted(Comparator.comparing(
                up -> up.getProduct().getAvgPowerW().multiply(up.getAvgActiveHours()),
                Comparator.reverseOrder()))

            .map(UserProduct::getProduct)
            .collect(Collectors.toList());

        return Optional.of(products);
    }

    @Override
    public Optional<BigDecimal> calculateStandbyConsumeAvg(User user){
        Objects.requireNonNull(user);

        List<UserProduct> userProducts = getProductRegistry(user);
        BigDecimal inactiveConsumption = userProducts.stream()
            .map(up -> userService.calculateConsumption(
                    up,
                    UserProduct::getHoursStandby
            ))
            .reduce(BigDecimal.ZERO, BigDecimal::add);

         return avg(inactiveConsumption, userProducts);
    }

    @Override
    public Optional<BigDecimal> calculateStandbyConsumesForProduct(User user , Product product){
        Objects.requireNonNull(user);
        Objects.requireNonNull(product);

        List<UserProduct> userProducts = getProductRegistry(user);

        BigDecimal inactiveConsumption = userProducts.stream()
            .filter(up -> up.getProduct().getId().equals(product.getId()))
            .map(up -> userService.calculateConsumption(
                up,
                UserProduct::getHoursStandby
            ))
            .reduce(BigDecimal.ZERO, BigDecimal::add);

        return Optional.of(inactiveConsumption);
    }

    @Override
    public List<UserProduct> getProductRegistry(User user){
        List<UserProduct> userProductReg = repository.findByUser(user);
        Optional.of(userProductReg)
                .filter(reg -> !reg.isEmpty())
                .orElseThrow(() -> new ProductEmptyException(
                    "User product list cannot be empty"));
        return userProductReg;
    }

    @Override
    public Optional<BigDecimal> avg(BigDecimal value, List<?> arry){
        return Optional.of(
                value.divide(
                    BigDecimal.valueOf(arry.size()),
                    2,
                    RoundingMode.HALF_UP
                )
            );
    }
}
