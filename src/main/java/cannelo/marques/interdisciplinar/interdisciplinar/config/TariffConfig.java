package cannelo.marques.interdisciplinar.interdisciplinar.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

/**
 * Registra {@link TariffProperties} (prefixo {@code ampares.energy.tariff})
 * no contexto Spring sem tocar na classe de aplicação
 * ({@code InterdisciplinarApplication}) — que está sob escopo humano.
 *
 * <p>Chaves ausentes em {@code application.properties} caem nos defaults
 * embutidos em {@link TariffProperties}.
 */
@Configuration
@EnableConfigurationProperties(TariffProperties.class)
public class TariffConfig {
}
