package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

/// DTO de entrada para metricas que dependem apenas do usuario
/// (ex.: consumo medio, produto de maior consumo, consumo medio em standby).
public record MetricsByUserDTO(int userId) {
}
