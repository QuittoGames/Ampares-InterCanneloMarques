package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import java.math.BigDecimal;
import java.util.Objects;
import java.util.Optional;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductForRegistry;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InvalidRegistryException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import jakarta.transaction.Transactional;


@Service
public class RegistryUserService{
    /** Horas em um dia — limite superior das faixas de horas validadas. */
    private static final BigDecimal HOURS_PER_DAY = new BigDecimal("24");

    private final RegistryUserProductRepository registryRepository;
    private final UserRepository userRepository;
    private final ProductRepository productRepository;
    private final ProductForRegistryConverter converter;

    public RegistryUserService(RegistryUserProductRepository registryRepository,
                               UserRepository userRepository,
                               ProductRepository productRepository,
                               ProductForRegistryConverter converter){
        this.registryRepository = registryRepository;
        this.userRepository = userRepository;
        this.productRepository = productRepository;
        this.converter = converter;
    }

    /**
     * Registra um produto em uso para um usuário (relação N:N
     * {@code User (1:N) -> RegistryUserProduct <- (N:1) Product}).
     *
     * <p>Pipeline: resolver {@code User} e {@code Product} por id → validar
     * faixas → checar duplicidade do par (user, product) → converter via
     * {@link ProductForRegistryConverter} → {@code save} → retornar a entidade
     * persistida.
     *
     * <p>Regras de horas (SPEC do registro):
     * <ul>
     *   <li>{@code avgActiveHours} vem DO REQUEST como estimativa do usuário —
     *       nunca é derivado pelo backend;</li>
     *   <li>{@code hoursStandby} ausente permanece {@code null} persistido —
     *       NUNCA vira {@code 24 − avgActiveHours};</li>
     *   <li>valores fora da faixa geram {@link InvalidRegistryException}
     *       explícita (nunca zero silencioso nem clamp).</li>
     * </ul>
     *
     * <p>Regra de duplicidade mantida: o par (user, product) duplicado lança
     * {@link IllegalStateException}.
     */
    @Transactional
    public RegistryUserProduct registerUserProduct(ProductForRegistry request){
        Objects.requireNonNull(request, "request cannot be null");

        if (request.userId() == null){
            throw new InvalidRegistryException("userId must not be null");
        }
        if (request.productId() == null){
            throw new InvalidRegistryException("productId must not be null");
        }

        User user = userRepository.findById(request.userId())
                .orElseThrow(() -> new UserNotFoundException(
                        "User not found: " + request.userId()));

        Product product = productRepository.findById(request.productId())
                .orElseThrow(() -> new ProductNotFoundException(
                        "Product not found: " + request.productId()));

        validate(request);

        Optional<RegistryUserProduct> existing = registryRepository.findByUserAndProduct(user, product)
                                                                   .stream()
                                                                   .findFirst();
        if (existing.isPresent()){
            throw new IllegalStateException(
                "Registry already exists for user " + user.getId()
                    + " and product " + product.getId());
        }

        RegistryUserProduct registry = converter.toEntity(request, user, product);

        return registryRepository.save(registry);
    }

    /**
     * Valida as faixas do request com erro EXPLÍCITO.
     *
     * @throws InvalidRegistryException quantity &lt; 1, avgActiveHours nulo ou
     *         fora de [0, 24], hoursStandby fora de [0, 24] quando informado
     */
    private void validate(ProductForRegistry request){
        if (request.quantity() < 1){
            throw new InvalidRegistryException(
                "quantity must be at least 1, got: " + request.quantity());
        }

        BigDecimal avgActiveHours = request.avgActiveHours();
        if (avgActiveHours == null){
            throw new InvalidRegistryException(
                "avgActiveHours must not be null (user estimation; backend never derives it)");
        }
        if (avgActiveHours.signum() < 0 || avgActiveHours.compareTo(HOURS_PER_DAY) > 0){
            throw new InvalidRegistryException(
                "avgActiveHours must be within [0, 24], got: " + avgActiveHours);
        }

        BigDecimal hoursStandby = request.hoursStandby();
        if (hoursStandby != null
                && (hoursStandby.signum() < 0 || hoursStandby.compareTo(HOURS_PER_DAY) > 0)){
            throw new InvalidRegistryException(
                "hoursStandby must be within [0, 24], got: " + hoursStandby);
        }
    }

    /**
     * Caminho legado usado por {@code UserService.addProduct} (HUMAN SCOPE).
     *
     * <p>Delega integralmente para {@link #registerUserProduct(ProductForRegistry)}.
     * A derivação de horas foi REMOVIDA (SPEC do registro): {@code avgActiveHours}
     * ou {@code hoursStandby} nulos agora geram {@link InvalidRegistryException}
     * explícita em vez de serem calculados via {@code RegistryCalculator} /
     * {@code ConsumptionCalculator}.
     *
     * @deprecated use {@link #registerUserProduct(ProductForRegistry)} — o
     *             contrato de registro é {@code ProductForRegistry}. Mantido
     *             apenas para não quebrar o fluxo legado de UserService.
     */
    @Deprecated
    @Transactional
    public RegistryUserProduct createRegistry(User user, Product product, int quantity, BigDecimal avgActiveHours, BigDecimal hoursStandby){
        Objects.requireNonNull(user, "user cannot be null");
        Objects.requireNonNull(product, "product cannot be null");

        return registerUserProduct(new ProductForRegistry(
                user.getId(),
                product.getId(),
                quantity,
                avgActiveHours,
                hoursStandby));
    }
}
