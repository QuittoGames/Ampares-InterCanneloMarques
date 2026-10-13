package cannelo.marques.interdisciplinar.interdisciplinar.Services.Registry;

import java.util.Objects;

import org.springframework.stereotype.Component;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ProductForRegistry;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;

/**
 * Conversor puro de {@link ProductForRegistry} → {@link RegistryUserProduct}.
 *
 * <p>APENAS mapeamento: sem repositórios, sem SQL, sem regras de negócio.
 * O {@code User} e o {@code Product} chegam já resolvidos pelo
 * {@link RegistryUserService} e são apenas associados à entidade.
 *
 * <p>Invariantes:
 * <ul>
 *   <li>A PK (UUID) da associação NÃO é setada aqui — fica por conta do JPA
 *       ({@code GenerationType.UUID});</li>
 *   <li>{@code hoursStandby == null} permanece {@code null}: este conversor
 *       NUNCA deriva {@code 24 − avgActiveHours} (derivação proibida pela
 *       SPEC do registro);</li>
 *   <li>{@code avgActiveHours} é copiado literalmente do request — é a
 *       estimativa do usuário.</li>
 * </ul>
 */
@Component
public class ProductForRegistryConverter {

    /**
     * Converte o request de registro em entidade ainda não persistida.
     *
     * @param request contrato de entrada (campos escalares)
     * @param user    instância {@link User} já resolvida e persistente
     * @param product instância {@link Product} já resolvida e persistente
     * @return entidade {@link RegistryUserProduct} com id {@code null}
     *         (gerado pelo JPA no {@code save})
     */
    public RegistryUserProduct toEntity(ProductForRegistry request, User user, Product product) {
        Objects.requireNonNull(request, "request cannot be null");
        Objects.requireNonNull(user, "user cannot be null");
        Objects.requireNonNull(product, "product cannot be null");

        RegistryUserProduct registry = new RegistryUserProduct(
                user,
                request.quantity(),
                request.avgActiveHours(),
                request.hoursStandby(),
                product);

        // PK intencionalmente não setada: geração é responsabilidade do JPA.
        return registry;
    }
}
