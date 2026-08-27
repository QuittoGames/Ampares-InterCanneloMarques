package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

/// DTO de entrada para metricas filtradas por categoria de produto
/// (ex.: produtos de maior consumo dentro de uma categoria).
public record MetricsByCategoryDTO(int userId, String category) {
}
