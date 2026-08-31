package cannelo.marques.interdisciplinar.interdisciplinar.Repository;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import java.math.BigDecimal;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface RegistryUserProductRepository extends JpaRepository<RegistryUserProduct, UUID> {

    List<RegistryUserProduct> findByUser(User user);
    List<RegistryUserProduct> findByProduct(Product product);
    List<RegistryUserProduct> findByUserAndProduct(User user, Product product);
    List<RegistryUserProduct> findByQuantity(int quantity);
    List<RegistryUserProduct> findByUserAndQuantityGreaterThan(User user, int quantity);
    long countByUser(User user);
    List<RegistryUserProduct> findByAvgActiveHoursGreaterThan(BigDecimal avgActiveHours);
    List<RegistryUserProduct> findByHoursStandbyLessThan(BigDecimal hoursStandby);
    List<RegistryUserProduct> findByUserAndAvgActiveHoursGreaterThan(User user, BigDecimal avgActiveHours);
    List<RegistryUserProduct> findByProductAndQuantityLessThan(Product product, int quantity);
}