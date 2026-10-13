package cannelo.marques.interdisciplinar.interdisciplinar.exceptions;

/**
 * Falha de validação explícita no fluxo de registro de produto por usuário
 * (ex.: quantity &lt; 1, avgActiveHours fora de [0, 24], hoursStandby fora de
 * [0, 24], valores nulos obrigatórios).
 *
 * <p>Erro EXPLÍCITO: o registro nunca normaliza nem zera silenciosamente um
 * valor inválido.
 */
public class InvalidRegistryException extends RuntimeException {
    public InvalidRegistryException(String message) {
        super(message);
    }
}
