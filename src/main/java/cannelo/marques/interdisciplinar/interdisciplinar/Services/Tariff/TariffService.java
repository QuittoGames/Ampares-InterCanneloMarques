package cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff;

import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffQuote.Status;
import cannelo.marques.interdisciplinar.interdisciplinar.config.TariffProperties;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.TariffUnavailableException;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.MathContext;
import java.time.LocalDate;
import java.util.Objects;

/**
 * FONTE ÚNICA de tarifa elétrica do sistema — expõe a tarifa residencial B1
 * da Enel Distribuição São Paulo ({@link TariffProperties}) já convertida
 * para R$/kWh.
 *
 * <p>Contratos do domínio:
 * <ul>
 *   <li>Retorno sempre em <strong>R$/kWh</strong> (BigDecimal — nunca double/float).</li>
 *   <li>Data dentro da vigência → {@link Status#VALID}; fora →
 *       {@link Status#OUTDATED} (sinaliza desatualização; NUNCA afirma ser a
 *       tarifa atual e NUNCA substitui por outra tarifa).</li>
 *   <li>Tarifa ausente/nula/zerada → {@link TariffUnavailableException}.
 *       NUNCA retorna null, nunca invente valor, nunca usa tarifa de outra
 *       área ou classe.</li>
 * </ul>
 */
@Service
public class TariffService {

    /**
     * Precisão da conversão R$/MWh → R$/kWh. A divisão por 1000 é exata em
     * binário decimal do BigDecimal; DECIMAL128 garante precisão suficiente
     * mesmo para valores publicados arbitrários em overrides.
     */
    private static final MathContext CONVERSION_CONTEXT = MathContext.DECIMAL128;

    private final TariffProperties properties;

    public TariffService(TariffProperties properties) {
        this.properties = Objects.requireNonNull(properties,
            "TariffProperties não registrada — verifique TariffConfig (@EnableConfigurationProperties).");
    }

    /**
     * Retorna a cotação de referência em R$/kWh para a data informada.
     *
     * @param date data de referência para avaliar a vigência (não nula)
     * @return cotação imutável em R$/kWh com metadados de origem e status
     * @throws TariffUnavailableException se a tarifa publicada estiver ausente,
     *         nula, zerada ou negativa na configuração
     * @throws IllegalArgumentException   se {@code date} for nula
     */
    public TariffQuote getReferenceTariff(LocalDate date) {
        Objects.requireNonNull(date, "Data de referência não pode ser nula.");

        BigDecimal published = properties.getPublishedValuePerMwh();
        if (published == null || published.signum() <= 0) {
            throw new TariffUnavailableException(
                "Tarifa de referência indisponível: valor publicado (ampares.energy.tariff"
                    + ".published-value-per-mwh, R$/MWh) ausente, nula ou zerada para "
                    + properties.getDistributor() + " / " + properties.getTariffClass()
                    + " / " + properties.getModality()
                    + ". Nenhuma tarifa alternativa será usada — configure a tarifa publicada.");
        }

        // Conversão de unidade: R$/MWh ÷ 1000 = R$/kWh (unidade do motor de custos).
        BigDecimal tariffPerKwh = published.divide(
            TariffProperties.MWH_TO_KWH_DIVISOR, CONVERSION_CONTEXT);

        Status status = resolveStatus(date, properties.getValidFrom(), properties.getValidUntil());

        return new TariffQuote(
            tariffPerKwh,
            properties.getDistributor(),
            properties.getTariffClass(),
            properties.getModality(),
            properties.getValidFrom(),
            properties.getValidUntil(),
            properties.getSourceUrl(),
            TariffQuote.ORIGIN_UNIT,
            status);
    }

    /**
     * Vigência com limites INCLUSIVOS: {@code validFrom <= date <= validUntil}
     * → VALID; caso contrário → OUTDATED.
     *
     * <p>Vigência ausente/incoerente também resulta em OUTDATED — sem janela
     * conhecida não se pode afirmar que a referência é válida.
     */
    private static Status resolveStatus(LocalDate date, LocalDate validFrom, LocalDate validUntil) {
        if (validFrom == null || validUntil == null || validUntil.isBefore(validFrom)) {
            return Status.OUTDATED;
        }
        boolean withinWindow = !date.isBefore(validFrom) && !date.isAfter(validUntil);
        return withinWindow ? Status.VALID : Status.OUTDATED;
    }
}
