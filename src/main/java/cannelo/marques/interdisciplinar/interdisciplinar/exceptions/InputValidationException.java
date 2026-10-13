package cannelo.marques.interdisciplinar.interdisciplinar.exceptions;

/**
 * Exceção lançada quando um input de cálculo é nulo ou inválido
 * (faixa, sinal ou unidade fora do contrato da fórmula).
 *
 * <p>Usada pelos métodos do Formula Bank em
 * {@code Services.Metrics.ConsumptionCalculator}: neles, input inválido
 * NUNCA vira {@link java.math.BigDecimal#ZERO} silencioso — a falha é
 * explícita para que o chamador decida o que reportar.
 */
public class InputValidationException extends RuntimeException {

    public InputValidationException(String message) {
        super(message);
    }
}
