package cannelo.marques.interdiciplinar.interdiciplinar.Repository;

import cannelo.marques.interdiciplinar.interdiciplinar.Models.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface UserReository extends JpaRepository<User, Integer>{

	List<User> findByName(String name);

	List<User> findByNameContainingIgnoreCase(String name);

	boolean existsByName(String name);
	boolean existsById(String name);

}
