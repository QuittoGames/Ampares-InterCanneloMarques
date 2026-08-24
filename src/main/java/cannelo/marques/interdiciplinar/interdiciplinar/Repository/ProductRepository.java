package cannelo.marques.interdiciplinar.interdiciplinar.Repository;

import cannelo.marques.interdiciplinar.interdiciplinar.Models.Product;
import cannelo.marques.interdiciplinar.interdiciplinar.Models.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ProductRepository extends JpaRepository<Product, UUID> {

    List<Product> findByUser(User user);

    List<Product> findByUser_Id(int userId);

    List<Product> findByUserAndQuantityGreaterThan(User user, int quantity);

    long countByUser(User user);

    List<Product> findByQuantityGreaterThanEqual(int quantity);
}
