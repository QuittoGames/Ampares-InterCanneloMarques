package cannelo.marques.interdisciplinar.interdisciplinar.exceptions;

/**
 * Lançada quando a fonte única de tarifa não pode fornecer um valor
 * utilizável (tarifa ausente, nula ou zerada na configuração).
 *
 * <p>Regra do domínio: o sistema NUNCA retorna null, NUNCA inventa um valor
 * e NUNCA substitui por tarifa de outra área/classe — ele falha de forma
 * explícita para que o problema seja tratado na origem.
 */
public class TariffUnavailableException extends RuntimeException {

    public TariffUnavailableException(String message) {
        super(message);
    }
}
