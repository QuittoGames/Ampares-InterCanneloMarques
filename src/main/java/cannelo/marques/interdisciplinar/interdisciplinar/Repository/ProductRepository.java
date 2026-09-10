package cannelo.marques.interdisciplinar.interdisciplinar.Repository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;


public interface ProductRepository extends JpaRepository<Product, UUID>{

    List<Product> findByBrand(String brand);

    @Query("""
            SELECT p
            FROM Product p
            WHERE LOWER(p.name) LIKE LOWER(CONCAT('%', :name, '%'))
        """)
    Optional<List<Product>> searchByName(@Param("name") String name);

    List<Product> findByCategory(String category);

    List<Product> findByAvgPowerWGreaterThan(BigDecimal power);

    List<Product> findByAvgPowerWLessThan(BigDecimal power);

    List<Product> findByAnnualEnergyKwhGreaterThan(BigDecimal kwh);

    List<Product> findByAnnualEnergyKwhBetween(BigDecimal minKwh, BigDecimal maxKwh);

    long countByAvgPowerWBetween(BigDecimal minPower, BigDecimal maxPower);

    List<Product> findByNameContaining(String name);

    List<Product> findByModelContaining(String model);
}
