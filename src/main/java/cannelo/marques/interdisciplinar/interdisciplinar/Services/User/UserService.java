package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Consumption.ConsumptionCalculator;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry.RegistryUserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import tools.jackson.databind.exc.MismatchedInputException;

@Service
public class UserService {
    private final UserRepository repository;
    private final ConsumeMetricsService consumeMetricsService;
    private final RegistryUserService registryUserService;
    private final ProductRepository productRepository;

    public UserService(UserRepository repository, ConsumeMetricsService consumeMetricsService, RegistryUserService registryUserService,ProductRepository productRepository){
        this.repository = repository;
        this.consumeMetricsService = consumeMetricsService;
        this.registryUserService = registryUserService;
        this.productRepository = productRepository;
    }

    public void addProduct(ProductDTO productDataRaw, int user_id) throws MismatchedInputException{
        Objects.requireNonNull(productDataRaw);
        Objects.requireNonNull(user_id);

        Optional<User> userOptional = getUser(user_id);

        User user = userOptional.get();

        Product product = productRepository
            .findById(productDataRaw.registryId())
            .orElseThrow(() -> new ProductNotFoundException("Product not found"));

        int quantity = productDataRaw.quantity() == 0
            ? 1
            : productDataRaw.quantity() ;

        RegistryUserProduct registryUserProduct = registryUserService.createRegistry(user, product,quantity,null,null);
    }

    public void removeProduct(ProductDTO productDTO, int user_id){
        Objects.requireNonNull(productDTO);

        Optional<User> userOptional = getUser(user_id);

        User user = userOptional.get();

        Optional<RegistryUserProduct> registryProduct = getProduct(productDTO.registryId(), user);

        RegistryUserProduct userProduct = registryProduct.orElseThrow(() ->
            new ProductNotFoundException("Product not found in user registry: " + productDTO.registryId())
        );
    }

    public Optional<RegistryUserProduct> getProduct(UUID RegistryId, User user){
        List<RegistryUserProduct> registry = findAllProductrs(user);
        for(RegistryUserProduct product : registry){
            if(product.getId().equals(RegistryId)){
                return Optional.of(product);
            }
        }
        return Optional.empty();
    }

    public List<RegistryUserProduct> findAllProductrs(User user){
        List<RegistryUserProduct> registry =  consumeMetricsService.getProductRegistry(user);
        Objects.requireNonNull(registry);
        return registry;
    }

    public boolean userExists(User user){
        return Optional.ofNullable(user)
                .map(User::getId)
                .map(repository::existsById)
                .orElse(false);
    }

    public Optional<User> getUser(int user_id) throws UserNotFoundException{
        Objects.requireNonNull(user_id);

        Optional<User> user = repository.findById(user_id);
        if (user == null || user.isEmpty()){
            throw new UserNotFoundException("id not foud in database");
        }
        return user;
    }
}
