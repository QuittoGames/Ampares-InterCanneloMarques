package cannelo.marques.interdisciplinar.interdisciplinar.exceptions;

/**
 * Exceção de domínio para a regra "exigir pelo menos um produto
 * registrado" (decision_004 / SPEC §8.2).
 *
 * <p>Reserva clara e explícita em relação ao genérico
 * {@code IllegalStateException}: usar quando uma regra de negócio exigir
 * ≥1 produto registrado. Enquanto os cálculos atuais cobrem a ausência de
 * registros com {@code Optional.empty()}, esta exceção permanece
 * disponível para a regra futura.
 */
public class NoRegisteredProductsException extends RuntimeException {

    public NoRegisteredProductsException(String message) {
        super(message);
    }
}
