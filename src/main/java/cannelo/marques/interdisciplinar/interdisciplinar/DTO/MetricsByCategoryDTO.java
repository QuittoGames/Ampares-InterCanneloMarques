package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/// DTO de entrada para metricas filtradas por categoria de produto
/// (ex.: produtos de maior consumo dentro de uma categoria).
public record MetricsByCategoryDTO(
    @NotNull int userId,
    @NotNull @Size(min = 0,max = 30 , message = "invalid string") String category) {
}
