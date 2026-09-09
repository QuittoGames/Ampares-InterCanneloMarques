package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

import java.math.BigDecimal;
import java.util.UUID;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/// DTO de entrada para registrar um produto em uso por um usuário.
/// Usado pelo endpoint POST /registryUserProducts.
public record RegistryUserProductDTO(

        @NotNull
        Integer userId,

        @NotNull
        UUID productId,

        @Min(1)
        int quantity,

        @NotNull
        @Min(0)
        BigDecimal avgActiveHours,

        /// Opcional: se null, o backend calcula via RegistryCalculator
        BigDecimal hoursStandby
) {
}
