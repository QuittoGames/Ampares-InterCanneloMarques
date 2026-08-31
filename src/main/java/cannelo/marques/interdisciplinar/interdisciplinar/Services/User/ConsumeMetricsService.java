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
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.MetricsService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Consumption.ConsumptionCalculator;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductEmptyException;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;

@Service
public class ConsumeMetricsService implements MetricsService<User,BigDecimal>{
    private final RegistryUserProductRepository registryRepository;
    private final UserRepository userRepository;

    public ConsumeMetricsService(
            RegistryUserProductRepository registryRepository,
            UserRepository userRepository){
        this.registryRepository = registryRepository;
        this.userRepository = userRepository;
    }

    @Override
    public Optional<BigDecimal> calculateEnergyByUser(User user){
        Objects.requireNonNull(user, "User cant be ");

        if (!userRepository.existsById(user.getId())) {
            throw new IllegalStateException("User not found: " + user.getId());
        }

        BigDecimal consumeInYear = BigDecimal.ZERO;

        List<RegistryUserProduct> userProductReg = registryRepository.findByUser(user);
        Optional.of(userProductReg)
                .filter(reg -> !reg.isEmpty())
                .orElseThrow(() -> new ProductEmptyException(
                "User product list cannot be empty"));

        for (RegistryUserProduct up: userProductReg){
            consumeInYear = consumeInYear.add(
                ConsumptionCalculator.calculate(up, RegistryUserProduct::getAvgActiveHours)
            );
        }

        return Optional.of(consumeInYear);
    }

    @Override
    public Optional<BigDecimal> calculateAverageEnergyByUser(User user){
        Objects.requireNonNull(user, "User cant be ");

        if (!userRepository.existsById(user.getId())) {
            throw new IllegalStateException("User not found: " + user.getId());
        }

        BigDecimal consumeInYear = BigDecimal.ZERO;

        List<RegistryUserProduct> userProductReg = registryRepository.findByUser(user);
        Optional.of(userProductReg)
                .filter(reg -> !reg.isEmpty())
                .orElseThrow(() -> new ProductEmptyException(
                "User product list cannot be empty"));

        for (RegistryUserProduct up: userProductReg){
            consumeInYear = consumeInYear.add(
                ConsumptionCalculator.calculate(up, RegistryUserProduct::getAvgActiveHours)
            );
        }

         return avg(consumeInYear, userProductReg);
    }

    @Override
    public Optional<Product> calculateMostConsumerProduct(User user){
        Objects.requireNonNull(user, "User cant be null");

        List<RegistryUserProduct> userProductReg = getProductRegistry(user);
        Optional<Product> mostConsumerProduct = userProductReg.stream()
            .filter(up -> up.getProduct() != null)
            .filter(up -> up.getProduct().getAvgPowerW() != null)
            .max(Comparator.comparing(
                up -> up.getProduct()
                    .getAvgPowerW()
                    .multiply(up.getAvgActiveHours())
            ))
            .map(RegistryUserProduct::getProduct);

        return mostConsumerProduct;
    }

    @Override
    public Optional<List<Product>> mostConsumerProductsForCategory(User user, String category){
        Objects.requireNonNull(user);
        Objects.requireNonNull(category, "Category cant be null");

        List<RegistryUserProduct> userProductReg = getProductRegistry(user);
        List<Product> products = userProductReg.stream()
            .filter(up -> up.getProduct() != null)
            .filter(up -> category.equalsIgnoreCase(up.getProduct().getCategory()))
            .filter(up -> up.getProduct().getAvgPowerW() != null)
            .filter(up -> up.getAvgActiveHours() != null)

            .sorted(Comparator.comparing(
                up -> up.getProduct().getAvgPowerW().multiply(up.getAvgActiveHours()),
                Comparator.reverseOrder()))

            .map(RegistryUserProduct::getProduct)
            .collect(Collectors.toList());

        return Optional.of(products);
    }

    @Override
    public Optional<BigDecimal> calculateStandbyConsumeAvg(User user){
        Objects.requireNonNull(user);

        List<RegistryUserProduct> userProducts = getProductRegistry(user);
        BigDecimal inactiveConsumption = userProducts.stream()
            .map(up -> ConsumptionCalculator.calculate(
                    up,
                    RegistryUserProduct::getHoursStandby
            ))
            .reduce(BigDecimal.ZERO, BigDecimal::add);

         return avg(inactiveConsumption, userProducts);
    }

    @Override
    public Optional<BigDecimal> calculateStandbyConsumesForProduct(User user , Product product){
        Objects.requireNonNull(user);
        Objects.requireNonNull(product);

        List<RegistryUserProduct> userProducts = getProductRegistry(user);

        BigDecimal inactiveConsumption = userProducts.stream()
            .filter(up -> up.getProduct().getId().equals(product.getId()))
            .map(up -> ConsumptionCalculator.calculate(
                up,
                RegistryUserProduct::getHoursStandby
            ))
            .reduce(BigDecimal.ZERO, BigDecimal::add);

        return Optional.of(inactiveConsumption);
    }

    @Override
    public List<RegistryUserProduct> getProductRegistry(User user){
        List<RegistryUserProduct> userProductReg = registryRepository.findByUser(user);
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
