package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import jakarta.validation.constraints.NotNull;

@Service
public class ProductService {
    private ProductRepository repository;

    public ProductService(ProductRepository repository){
        this.repository = repository;
    }

    public Optional<List<Product>> searchProduct(User user, String splitSearch) throws ProductNotFoundException{
        Objects.requireNonNull(user);
        Objects.requireNonNull(splitSearch);

        Optional<List<Product>> products = repository.searchByName(splitSearch);

        return products;
    }

    public Product findById(@NotNull UUID id) throws ProductNotFoundException{
        return repository.findById(id)
                .orElseThrow(() -> new ProductNotFoundException("Product not found: " + id));

    }
}
