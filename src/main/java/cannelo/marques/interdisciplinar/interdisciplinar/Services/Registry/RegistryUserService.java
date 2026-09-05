package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import java.math.BigDecimal;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Consumption.ConsumptionCalculator;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import jakarta.transaction.Transactional;


@Service
public class RegistryUserService{
    private final RegistryUserProductRepository registryRepository;
    private final UserRepository userRepository;
    private final ProductRepository productRepository;

    public RegistryUserService(RegistryUserProductRepository registryRepository, UserRepository userRepository, ProductRepository productRepository){
        this.registryRepository = registryRepository;
        this.userRepository = userRepository;
        this.productRepository = productRepository;
    }

    @Transactional
    public RegistryUserProduct createRegistry(User user, Product product, int quantity, BigDecimal avgActiveHours, BigDecimal hoursStandby){

        Objects.requireNonNull(user, "user cannot be null");
        Objects.requireNonNull(product, "product cannot be null");

        if (!userRepository.existsById(user.getId())){
            throw new UserNotFoundException("User not found: " + user.getId());
        }

        if (!productRepository.existsById(product.getId())){
            throw new ProductNotFoundException("Product not found: " + product.getId());
        }

        Optional<RegistryUserProduct> existing = registryRepository.findByUserAndProduct(user, product)
                                                                   .stream()
                                                                   .findFirst();
        if (existing.isPresent()){
            throw new IllegalStateException(
                "Registry already exists for user " + user.getId()
                    + " and product " + product.getId());
        }

        // Se avgActiveHours ou hoursStandby vierem null, calcula a partir do
        // product usando as fórmulas determinísticas do energy_collector
        // (equivalent_hours_year / 365 = horas ativas por dia, e 24 − ativo
        // = horas de standby). Nenhum valor é inventado: se o produto não
        // tiver avgPowerW/annualEnergyKwh suficientes, o resultado fica null
        // (persistido como NULL no banco).
        BigDecimal resolvedAvgActiveHours = avgActiveHours != null
            ? avgActiveHours
            : RegistryCalculator.computeAvgActiveHoursPerDay(product);

        BigDecimal resolvedHoursStandby = hoursStandby;

        if (resolvedHoursStandby == null){
            resolvedHoursStandby = RegistryCalculator.computeHoursStandbyPerDay(product);
        }

        RegistryUserProduct registry = new RegistryUserProduct(
            UUID.randomUUID(),
            user,
            quantity,
            resolvedAvgActiveHours,
            resolvedHoursStandby,
            product);

        //Falllback if dont exits the avg value in database
        if (registry.getHoursStandby() == null){
            registry.setAvgActiveHours(ConsumptionCalculator.calculate(registry, RegistryUserProduct::getAvgActiveHours));
        }

        return registryRepository.save(registry);
    }
}
