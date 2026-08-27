package cannelo.marques.interdisciplinar.interdisciplinar.Repository;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface UserRepository extends JpaRepository<User, Integer>{

	List<User> findByName(String name);

	List<User> findByNameContainingIgnoreCase(String name);

	boolean existsByName(String name);
}
