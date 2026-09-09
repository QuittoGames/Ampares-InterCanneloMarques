package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.RegistryUserProductDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.UserRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry.RegistryUserService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.ProductNotFoundException;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;

import java.util.List;

@RestController
@RequestMapping("/registryUserProducts")
@Tag(name = "Registry", description = "Endpoints de registro de produto em uso por usuário")
public class RegistryUserProductController {

    private final RegistryUserService registryUserService;
    private final UserService userService;
    private final UserRepository userRepository;
    private final ProductRepository productRepository;

    public RegistryUserProductController(
            RegistryUserService registryUserService,
            UserService userService,
            UserRepository userRepository,
            ProductRepository productRepository) {
        this.registryUserService = registryUserService;
        this.userService = userService;
        this.userRepository = userRepository;
        this.productRepository = productRepository;
    }

    @Operation(
            summary = "Registra um produto em uso para o usuário",
            description = "Resolve userId e productId, valida existência e cria o registro via RegistryUserService. " +
                          "Se avgActiveHours ou hoursStandby vierem null, são calculados pelo RegistryCalculator a partir do produto."
    )
    @PostMapping
    public ResponseEntity<RegistryUserProduct> create(@RequestBody @Valid RegistryUserProductDTO dto) {

        User user = userRepository.findById(dto.userId())
                .orElseThrow(() -> new UserNotFoundException("User not found: " + dto.userId()));

        Product product = productRepository.findById(dto.productId())
                .orElseThrow(() -> new ProductNotFoundException("Product not found: " + dto.productId()));

        int quantity = dto.quantity() <= 0 ? 1 : dto.quantity();

        RegistryUserProduct registry = registryUserService.createRegistry(
                user,
                product,
                quantity,
                dto.avgActiveHours(),
                dto.hoursStandby()
        );

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

        return ResponseEntity.ok(userService.findAllProductrs(user));
    }
}
