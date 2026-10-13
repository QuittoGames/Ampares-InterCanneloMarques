package cannelo.marques.interdisciplinar.interdisciplinar.interfaces;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ResultDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;

public interface MetricsService<Client extends User , OperationValue extends Number> {
    Optional<ResultDTO> calculate(Client user);

    /// Média do consumo anual por produto do usuário.
    Optional<BigDecimal> calculateAverageEnergyByUser(Client user);

    Optional<Product> calculateMostConsumerProduct(Client user);

    Optional<List<Product>> calculateMostConsumerProductByCategory(Client user, String category);

    Optional<BigDecimal> calculateStandbyConsumeAvg(Client user); // Return in Year value

    Optional<BigDecimal> calculateStandbyConsumesForProduct(Client user, Product product); // Return in Year value

    List<RegistryUserProduct> getProductsRegistrys(Client user);

    Optional<BigDecimal> avg(OperationValue value, List<?> arry);
}
