package cannelo.marques.interdisciplinar.interdisciplinar.DTO;

import java.util.UUID;

public record ProductDTO(
    UUID registryId,
    String name,
    int quantity
) {

}
