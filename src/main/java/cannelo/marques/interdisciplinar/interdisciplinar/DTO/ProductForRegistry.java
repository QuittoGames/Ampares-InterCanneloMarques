package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

import java.math.BigDecimal;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/// Contrato de entrada para registrar um produto em uso por um usuário.
/// Usado pelo endpoint POST /registryUserProducts (substitui
/// `RegistryUserProductDTO`).
///
/// Regras do contrato (SPEC de refactor do registro):
/// - `avgActiveHours` é uma estimativa vinda DO USUÁRIO (anotação no diagrama:
///   "Avg Active Hours represent only estimative been got for user") — o
///   backend NUNCA deriva esse valor;
/// - `hoursStandby` é opcional: quando ausente permanece `null` persistido —
///   o backend NÃO calcula `24 − avgActiveHours` (derivação proibida pela
///   SPEC; cálculo de standby pertence ao hub MetricsService/Consumption
///   Calculator, DECISION 001);
/// - faixas validadas: quantity ≥ 1; avgActiveHours ∈ [0, 24];
///   hoursStandby ∈ [0, 24] quando informado.
public record ProductForRegistry(

        @NotNull
        Integer userId,

        @NotNull
        UUID productId,

        @Min(1)
        int quantity,

        /// Horas ativas por dia — estimativa do usuário. Faixa [0, 24].
        @NotNull
        @Min(0)
        @Max(24)
        BigDecimal avgActiveHours,

        /// Horas em standby por dia — opcional, faixa [0, 24] quando
        /// informado. Se `null`, permanece `null` no banco (sem derivação).
        @Min(0)
        @Max(24)
        BigDecimal hoursStandby
) {
        public ProductForRegistry(Integer userId, UUID productId, int quantity,
                                                          BigDecimal avgActiveHours, BigDecimal hoursStandby) {
                this.userId = userId;
                this.productId = productId;
                this.quantity = quantity;
                this.avgActiveHours = avgActiveHours;
                this.hoursStandby = hoursStandby;
        }
}
