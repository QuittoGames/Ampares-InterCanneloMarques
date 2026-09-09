package cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;

public interface MetricsService<Client extends User , OperationValue extends Number> {
    /// Soma do consumo anual em kWh de todos os produtos do usuário (sem dividir).
    Optional<BigDecimal> calculateTotalEnergyByUser(Client user);

    /// Média do consumo anual por produto do usuário.
    Optional<BigDecimal> calculateAverageEnergyByUser(Client user);

    Optional<Product> calculateMostConsumerProduct(Client user);

    Optional<List<Product>> mostConsumerProductsForCategory(Client user, String category);

    Optional<BigDecimal> calculateStandbyConsumeAvg(Client user);

    Optional<BigDecimal> calculateStandbyConsumesForProduct(Client user, Product product);

    List<RegistryUserProduct> getProductRegistry(Client user);

    Optional<BigDecimal> avg(OperationValue value, List<?> arry);
}
