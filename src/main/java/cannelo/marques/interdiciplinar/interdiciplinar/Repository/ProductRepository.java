package cannelo.marques.interdiciplinar.interdiciplinar.Repository;

import cannelo.marques.interdiciplinar.interdiciplinar.Models.Product;
import cannelo.marques.interdiciplinar.interdiciplinar.Models.User;

import org.hibernate.annotations.processing.SQL;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;
import java.math.BigDecimal;


public interface ProductRepository extends JpaRepository<Product, UUID> {

    List<Product> findByUser(User user);

    List<Product> findByUser_Id(int userId);

    List<Product> findByUserAndQuantityGreaterThan(User user, int quantity);

    long countByUser(User user);

    List<Product> findByQuantityGreaterThanEqual(int quantity);

    List<Product> findByBrand(String brand);
    List<Product> findByCategory(String category);
    List<Product> findByAvgPowerWGreaterThan(double power);
    List<Product> findByAvgPowerWLessThan(double power);
    List<Product> findByAnnualEnergyKwhGreaterThan(double kwh);
    List<Product> findByAnnualEnergyKwhBetween(double minKwh, double maxKwh);
    long countByAvgPowerWBetween(double minPower, double maxPower);
    List<Product> findByNameContaining(String name);
    List<Product> findByModelContaining(String model);
    List<Product> findByAvg_power_w(BigDecimal avg_power_w);
    List<Product> findByAnnual_energy_kwh(BigDecimal annual_energy_kwh);

    @SQL("SELECT * FROM products WHERE id NOT IS NULL")
    List<Product> getAVG_Engergy_w();
}
