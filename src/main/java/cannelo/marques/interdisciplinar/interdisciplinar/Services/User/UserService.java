package cannelo.marques.interdisciplinar.interdisciplinar.Services.User;

import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;

import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics.ConsumeMetricsService;
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
    private final JdbcTemplate jdbcTemplate;

    public UserService(UserRepository repository, ConsumeMetricsService consumeMetricsService, RegistryUserService registryUserService,ProductRepository productRepository, JdbcTemplate jdbcTemplate){
        this.repository = repository;
        this.consumeMetricsService = consumeMetricsService;
        this.registryUserService = registryUserService;
        this.productRepository = productRepository;
        this.jdbcTemplate = jdbcTemplate;
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
        List<RegistryUserProduct> registry = consumeMetricsService.getProductsRegistrys(user);
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

    public Optional<User> create(){
        User user = new User();
        user.setName("test " + UUID.randomUUID().toString());

        repository.save(user);

        return Optional.of(user);
    }

    /**
     * Cria um usuário com o ID explícito enviado pelo cliente no login.
     *
     * <p>Usa SQL nativo porque {@code GenerationType.IDENTITY} faz o
     * Hibernate omitir a coluna {@code id} do INSERT —
     * {@code repository.save(new User(id))} ignoraria o valor informado e
     * o banco geraria outro id. A tabela {@code users} usa
     * {@code SERIAL} (migrations/create.sql), que aceita inserção
     * explícita de id.
     *
     * <p>{@code ON CONFLICT (id) DO NOTHING} torna a operação idempotente:
     * se o id já existir (corrida com {@link #userExists(User)}), nada é
     * inserido e o login prossegue como "usuário já existente".
     *
     * @param id id fornecido pelo cliente
     * @return o usuário com o id informado (criado ou já existente)
     */
    public Optional<User> create(int id){
        String name = "user " + id;

        jdbcTemplate.update(
                "INSERT INTO users (id, name) VALUES (?, ?) ON CONFLICT (id) DO NOTHING",
                id, name);

        return Optional.of(new User(id, name));
    }
}
