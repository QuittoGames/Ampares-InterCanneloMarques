package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

import java.util.UUID;

/// DTO de entrada para a metrica de consumo em standby de um produto especifico
/// do usuario (ex.: consumo em standby de um produto dentro da lista do usuario).
public record MetricsStandbyByProductDTO(int userId, UUID productId) {
}
