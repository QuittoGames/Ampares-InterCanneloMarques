package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductForRegistry;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry.RegistryUserService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.ProductVoltageService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;

import java.util.List;

/**
 * Contrato HTTP de registro de produto por usuário (endpoints preservados):
 *
 * <ul>
 *   <li><b>POST /registryUserProducts</b> — corpo {@link ProductForRegistry}
 *       ({@code userId: Integer, productId: UUID, quantity: int,
 *       avgActiveHours: BigDecimal, hoursStandby: BigDecimal?}). Resolve
 *       User/Product no serviço, valida faixas (quantity ≥ 1;
 *       avgActiveHours ∈ [0, 24]; hoursStandby ∈ [0, 24] quando informado),
 *       checa duplicidade do par (user, product) e responde
 *       <b>200</b> com a entidade persistida. Falhas de faixa/nulidade são
 *       rejeitadas em <b>400</b> pela validação de bean do próprio DTO
 *       ({@code @Min/@Max/@NotNull}) e, em chamada de serviço direta, por
 *       {@code InvalidRegistryException}. Usuário/produto inexistente e
 *       registro duplicado seguem o comportamento existente
 *       ({@code UserNotFoundException} / {@code ProductNotFoundException} /
 *       {@code IllegalStateException}).</li>
 *   <li><b>GET /registryUserProducts/user/{userId}</b> — <b>200</b> com a
 *       lista de registros do usuário; <b>erro</b> se o usuário não
 *       existir.</li>
 * </ul>
 *
 * <p>{@code hoursStandby} ausente permanece {@code null} persistido — o
 * backend NÃO calcula {@code 24 − avgActiveHours} (SPEC do registro).
 */
@RestController
@RequestMapping("/registryUserProducts")
@Tag(name = "Registry", description = "Endpoints de registro de produto em uso por usuário")
public class RegistryUserProductController {

    private final RegistryUserService registryUserService;
    private final UserService userService;
    private final UserRepository userRepository;
    private final ProductVoltageService productVoltageService;

    public RegistryUserProductController(
            RegistryUserService registryUserService,
            UserService userService,
            UserRepository userRepository,
            ProductVoltageService productVoltageService) {
        this.registryUserService = registryUserService;
        this.userService = userService;
        this.userRepository = userRepository;
        this.productVoltageService = productVoltageService;
    }

    @Operation(
            summary = "Registra um produto em uso para o usuário",
            description = "Contrato ProductForRegistry: quantity ≥ 1, avgActiveHours ∈ [0, 24] (estimativa do "
                          + "usuário, nunca derivada) e hoursStandby ∈ [0, 24] quando informado. hoursStandby ausente "
                          + "permanece null (o backend não calcula 24 − avgActiveHours). Resolve userId/productId, "
                          + "valida, checa duplicidade e cria o registro via RegistryUserService."
    )
    @PostMapping
    public ResponseEntity<RegistryUserProduct> create(@RequestBody @Valid ProductForRegistry dto) {

        RegistryUserProduct registry = registryUserService.registerUserProduct(dto);

        return ResponseEntity.ok(registry);
    }

    @Operation(
            summary = "Lista os produtos registrados pelo usuário",
            description = "Retorna os registros completos, incluindo quantidade, horários e os dados do produto associado."
    )
    @GetMapping("/user/{userId}")
    public ResponseEntity<List<RegistryUserProduct>> findByUser(@PathVariable int userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserNotFoundException("User not found: " + userId));

        List<RegistryUserProduct> registries = userService.findAllProductrs(user);

        productVoltageService.decorate(
                registries.stream().map(RegistryUserProduct::getProduct).toList());

        return ResponseEntity.ok(registries);
    }
}
