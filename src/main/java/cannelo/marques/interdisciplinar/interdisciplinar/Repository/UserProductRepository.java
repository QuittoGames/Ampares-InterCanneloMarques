package cannelo.marques.interdisciplinar.interdisciplinar.Repository;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.UserProduct;
import java.math.BigDecimal;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface UserProductRepository extends JpaRepository<UserProduct, UUID> {

    List<UserProduct> findByUser(User user);
    List<UserProduct> findByProduct(Product product);
    List<UserProduct> findByUserAndProduct(User user, Product product);
    List<UserProduct> findByQuantity(int quantity);
    List<UserProduct> findByUserAndQuantityGreaterThan(User user, int quantity);
    long countByUser(User user);
    List<UserProduct> findByAvgActiveHoursGreaterThan(BigDecimal avgActiveHours);
    List<UserProduct> findByHoursStandbyLessThan(BigDecimal hoursStandby);
    List<UserProduct> findByUserAndAvgActiveHoursGreaterThan(User user, BigDecimal avgActiveHours);
    List<UserProduct> findByProductAndQuantityLessThan(Product product, int quantity);
}
