package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import java.math.BigDecimal;
import java.util.Objects;
import java.util.Optional;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;

/**
 * Serviço de cálculo de horas diárias de um registro (DECISION 005).
 *
 * <p>Substitui a antiga anotação {@code @HoursProvider}, que foi REMOVIDA
 * ({@code interfaces/HoursProvider.java} deletado, anotações removidas de
 * {@link RegistryUserProduct}). A regra de soma de horas vive inteiramente
 * aqui: {@link RegistryUserProduct} é uma entidade burra (só dados/getters)
 * e NÃO possui métodos de cálculo.
 *
 * <p><b>Fórmula (unidades em h/dia):</b>
 * <pre>Hday = Hactive + Hstandby</pre>
 * onde {@code Hactive} é a média de horas ativas do dia
 * ({@code avgActiveHours}) e {@code Hstandby} é a horas de standby do dia
 * ({@code hoursStandby}).
 *
 * <p><b>Semântica (SPEC §8.4 + §7):</b>
 * <ul>
 *   <li>Componente {@code null} → <b>não calculável</b>
 *       ({@link Optional#empty()}); null NUNCA vira zero;</li>
 *   <li>Componente negativo ou fora de [0, 24] h/dia →
 *       {@link InputValidationException} (entrada inválida é erro explícito);</li>
 *   <li>Soma {@code Hday} &gt; 24 h/dia → inconsistência sinalizada com
 *       {@link InputValidationException}; NUNCA clamp silencioso;</li>
 *   <li>Sempre {@link BigDecimal}; sem arredondamento neste nível
 *       (arredondamento é responsabilidade de quem exibe).</li>
 * </ul>
 */
@Service
public class HourService {

    /** Limite físico de horas por dia (h/dia), inclusivo. */
    private static final BigDecimal MAX_DAILY_HOURS = new BigDecimal("24");

    /**
     * Calcula as horas totais diárias de um registro.
     *
     * <p>Fórmula (h/dia): {@code Hday = Hactive + Hstandby}.
     *
     * @param activeHours  horas ativas no dia ({@code Hactive}, h/dia);
     *                     deve estar em [0, 24]; {@code null} → não calculável
     * @param standbyHours horas de standby no dia ({@code Hstandby}, h/dia);
     *                     deve estar em [0, 24]; {@code null} → não calculável
     *                     (null nunca vira zero)
     * @return {@code Hactive + Hstandby} em h/dia, ou {@link Optional#empty()}
     *         quando qualquer componente é {@code null} (estado não calculável)
     * @throws InputValidationException se algum componente for negativo ou
     *         &gt; 24 h/dia, ou se a soma {@code Hday} exceder 24 h/dia
     *         (inconsistência explícita, sem clamp)
     */
    public Optional<BigDecimal> totalDailyHours(BigDecimal activeHours, BigDecimal standbyHours) {
        // Null nunca vira zero: componente ausente = estado não calculável.
        if (activeHours == null || standbyHours == null) {
            return Optional.empty();
        }

        validateComponent("Hactive", activeHours);
        validateComponent("Hstandby", standbyHours);

        BigDecimal hday = activeHours.add(standbyHours);
        if (hday.compareTo(MAX_DAILY_HOURS) > 0) {
            throw new InputValidationException(
                    "Hday = Hactive + Hstandby excede 24h/dia: " + hday.toPlainString());
        }
        return Optional.of(hday);
    }

    /**
     * Calcula as horas totais diárias de um registro de associação
     * usuário–produto, lendo {@code Hactive} de
     * {@link RegistryUserProduct#getAvgActiveHours()} e {@code Hstandby} de
     * {@link RegistryUserProduct#getHoursStandby()}.
     *
     * <p>A entidade permanece burra: a matemática é responsabilidade
     * exclusiva deste serviço.
     *
     * <p>Fórmula (h/dia): {@code Hday = Hactive + Hstandby}.
     *
     * @param registration registro cujas horas serão somadas; pode ser
     *                     {@code null} (não calculável)
     * @return {@code Hactive + Hstandby} em h/dia, ou {@link Optional#empty()}
     *         quando o registro ou qualquer componente de horas é
     *         {@code null} (null nunca vira zero)
     * @throws InputValidationException conforme
     *         {@link #totalDailyHours(BigDecimal, BigDecimal)}
     */
    public Optional<BigDecimal> totalDailyHours(RegistryUserProduct registration) {
        if (registration == null) {
            return Optional.empty();
        }
        return totalDailyHours(registration.getAvgActiveHours(), registration.getHoursStandby());
    }

    private Optional<BigDecimal> getStandyByHours(BigDecimal acitveHours){
        Objects.requireNonNull(acitveHours);
        return Optional.of(new BigDecimal("24").subtract(acitveHours));
    }

    /**
     * Valida um componente de horas isoladamente: deve estar em [0, 24] h/dia.
     *
     * @param name  nome do componente para a mensagem ("Hactive"/"Hstandby")
     * @param value valor em h/dia (não nulo)
     */
    private static void validateComponent(String name, BigDecimal value) {
        if (value.signum() < 0) {
            throw new InputValidationException(
                    name + " negativo (" + value.toPlainString()
                            + " h/dia): horas devem estar em [0,24] h/dia");
        }
        if (value.compareTo(MAX_DAILY_HOURS) > 0) {
            throw new InputValidationException(
                    name + " acima de 24h/dia (" + value.toPlainString()
                            + " h/dia): horas devem estar em [0,24] h/dia");
        }
    }
}
