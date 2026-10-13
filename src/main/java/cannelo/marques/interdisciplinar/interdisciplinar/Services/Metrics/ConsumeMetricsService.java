package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ResultDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffQuote;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;
import cannelo.marques.interdisciplinar.interdisciplinar.interfaces.MetricsService;

/**
 * Hub unificado de métricas de consumo (SPEC §8, decision_001/004).
 *
 * <p>Implementa o contrato da interface {@link MetricsService} sobre o
 * motor primitivo {@link ConsumptionCalculator} — <b>zero fórmula
 * duplicada no hub</b>: os helpers {@code calculateDailyKwh} e
 * {@code calculateAnnualKwh} apenas adaptam um {@link RegistryUserProduct}
 * para as fórmulas static do motor.
 *
 * <p><b>Convenções de contrato (decision_004):</b>
 * <ul>
 *   <li>Nunca null: consultas retornam lista possivelmente vazia;
 *       cálculos retornam {@link Optional#empty()} quando não calculável;</li>
 *   <li>Entrada nula ({@code user}) → {@link NullPointerException} com
 *       mensagem explícita;</li>
 *   <li>{@code java.stream()} em todas as agregações/filtros/ranking;</li>
 *   <li>Sempre {@link BigDecimal} — {@code double}/{@code float} proibidos.</li>
 * </ul>
 *
 * <p><b>Unidades:</b> helpers diários em kWh/dia, helpers anuais em
 * kWh/ano, médias em kWh/ano (escala 6, HALF_UP), custos em R$/dia e
 * R$/ano (2 casas, HALF_UP — aplicado pelo motor
 * {@link ConsumptionCalculator#cost}). Standby é sempre valor
 * ANUAL — porém não calculável enquanto não houver potência de standby
 * confiável (SPEC §7).
 *
 * <p><b>Tarifa (FONTE ÚNICA):</b> os custos do {@link ResultDTO} usam a
 * tarifa de {@link TariffService#getReferenceTariff(LocalDate)} convertida
 * em R$/kWh — nunca uma tarifa escrita no hub. Se a tarifa estiver
 * indisponível, {@code TariffUnavailableException} <b>propaga</b>
 * (nunca se inventa tarifa nem se substitui por outra fonte).
 */
@Service
public class ConsumeMetricsService implements MetricsService<User, BigDecimal> {

    /** Escala das divisões decimais (médias e taxas) — SPEC §8.3 exige scale ≥ 6 com HALF_UP. */
    private static final int DIVISION_SCALE = 6;

    private final RegistryUserProductRepository registryRepository;
    private final TariffService tariffService;

    public ConsumeMetricsService(RegistryUserProductRepository registryRepository,
            TariffService tariffService) {
        this.registryRepository = registryRepository;
        this.tariffService = tariffService;
    }

    // =====================================================================
    // Helpers puros (static) — delegação ao motor ConsumptionCalculator
    // =====================================================================

    /**
     * Verifica se o registro tem todas as entradas ativas obrigatórias
     * (SPEC §8.3): registro, produto, {@code avgPowerW} e
     * {@code avgActiveHours} não nulos. Registro sem entradas não conta
     * como consumo válido — é excluído dos cálculos, nunca vira ZERO.
     *
     * @param r registro de produto do usuário (pode ser null)
     * @return {@code true} se todas as entradas ativas estiverem presentes
     */
    private static boolean hasValidActiveInputs(RegistryUserProduct r) {
        return r != null
                && r.getProduct() != null
                && r.getProduct().getAvgPowerW() != null
                && r.getAvgActiveHours() != null;
    }

    /**
     * Verifica se o registro é <b>computável</b> pelo motor
     * (SPEC §6 / decisão do DEV de 13/10/2026).
     *
     * <p>Além da presença das entradas ({@link #hasValidActiveInputs}),
     * exige que o motor as aceite: horas derivadas ou legadas fora de
     * [0,24] h/dia, potência ≤ 0 ou quantidade &lt; 1 fazem o motor lançar
     * {@link InputValidationException} — esse registro é <b>excluído dos
     * agregados</b>, nunca vira ZERO e nunca derruba o cálculo dos demais
     * (mesma convenção de {@code hasValidActiveInputs}).
     *
     * @param r registro de produto do usuário (pode ser null)
     * @return {@code true} se o motor calcula este registro sem rejeitar
     */
    private static boolean hasComputableActiveInputs(RegistryUserProduct r) {
        if (!hasValidActiveInputs(r)) {
            return false;
        }
        try {
            calculateDailyKwh(r);
            return true;
        } catch (InputValidationException e) {
            return false;
        }
    }

    /**
     * Consumo <b>diário</b> do registro — <b>kWh/dia</b>.
     *
     * <p>Delega ao motor: {@code dailyKwh = P (W) × h_dia × q / 1000}
     * ({@link ConsumptionCalculator#dailyKwh(BigDecimal, BigDecimal, BigDecimal)}).
     *
     * @param r registro com entradas válidas (ver {@link #hasValidActiveInputs})
     * @return consumo em <b>kWh/dia</b>
     * @throws cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException
     *         se o motor rejeitar os inputs (potência ≤ 0, horas fora de
     *         [0,24] ou quantidade &lt; 1) — exceção de domínio, nunca null
     */
    private static BigDecimal calculateDailyKwh(RegistryUserProduct r) {
        return ConsumptionCalculator.dailyKwh(
                r.getProduct().getAvgPowerW(),
                r.getAvgActiveHours(),
                BigDecimal.valueOf(r.getQuantity()));
    }

    /**
     * Consumo <b>anual</b> do registro — <b>kWh/ano</b>.
     *
     * <p>{@code annualKwh = calculateDailyKwh(r) × 365}, delegando a
     * {@link ConsumptionCalculator#annualKwh(BigDecimal)} (ano de 365 dias).
     *
     * @param r registro com entradas válidas (ver {@link #hasValidActiveInputs})
     * @return consumo em <b>kWh/ano</b>
     * @throws cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException
     *         se os inputs forem inválidos (via motor)
     */
    private static BigDecimal calculateAnnualKwh(RegistryUserProduct r) {
        return ConsumptionCalculator.annualKwh(calculateDailyKwh(r));
    }

    // =====================================================================
    // Contrato MetricsService
    // =====================================================================

    /**
     * Monta o resultado geral do usuário.
     *
     * <p>Calcula, via stream sobre os registros com entradas válidas:
     * <ul>
     *   <li>{@code avgDailyKwh} — <b>média de consumo diário</b> por
     *       associação válida em <b>kWh/dia</b> (Σ calculateDailyKwh ÷
     *       nº de válidos, escala 6, HALF_UP);</li>
     *   <li>{@code avgUseInYear} — <b>média de consumo anual</b> por
     *       associação válida em <b>kWh/ano</b> (Σ calculateAnnualKwh ÷
     *       nº de válidos, escala 6, HALF_UP);</li>
     *   <li>{@code totalDailyKwh} — <b>total diário</b> do usuário em
     *       <b>kWh/dia</b> (Σ calculateDailyKwh sobre os mesmos válidos,
     *       sem arredondamento forçado — soma com a precisão do motor);</li>
     *   <li>{@code totalAnnualKwh} — <b>total anual</b> do usuário em
     *       <b>kWh/ano</b> (Σ calculateAnnualKwh sobre os mesmos válidos,
     *       calculado pelo motor — não é multiplicação inline);</li>
     *   <li>{@code dailyCost} / {@code annualCost} — <b>gasto</b> em
     *       <b>R$/dia</b> e <b>R$/ano</b>, obtidos com
     *       {@link ConsumptionCalculator#cost(BigDecimal, BigDecimal)}
     *       sobre a tarifa de {@link TariffService} (2 casas, HALF_UP já
     *       aplicado pelo motor — não duplicado aqui);</li>
     *   <li>{@code productsList} — todos os registros do usuário
     *       (incluindo os sem entradas válidas, para exibição).</li>
     * </ul>
     *
     * <p>Sem registros ou sem nenhuma entrada válida → não há resultado
     * calculável → {@link Optional#empty()} (a tarifa nem é consultada).
     * Havendo resultado a montar, a tarifa vem da FONTE ÚNICA
     * ({@link TariffService#getReferenceTariff(LocalDate)} de hoje) e
     * {@code TariffUnavailableException} <b>propaga</b> — o hub nunca
     * inventa, arredonda nem substitui tarifa.
     *
     * @param user usuário dono dos registros (não pode ser null)
     * @return o {@link ResultDTO} geral ou vazio se não calculável
     * @throws NullPointerException se {@code user} for null
     * @throws cannelo.marques.interdisciplinar.interdisciplinar.exceptions.TariffUnavailableException
     *         se a tarifa de referência estiver indisponível (propaga)
     */
    @Override
    public Optional<ResultDTO> calculate(User user) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");

        List<RegistryUserProduct> registries = getProductsRegistrys(user);
        List<RegistryUserProduct> valid = registries.stream()
                .filter(ConsumeMetricsService::hasComputableActiveInputs)
                .toList();

        if (valid.isEmpty()) {
            return Optional.empty();
        }

        int count = valid.size();

        BigDecimal avgDailyKwh = valid.stream()
                .map(ConsumeMetricsService::calculateDailyKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .divide(BigDecimal.valueOf(count), DIVISION_SCALE, RoundingMode.HALF_UP);

        BigDecimal avgUseInYear = valid.stream()
                .map(ConsumeMetricsService::calculateAnnualKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .divide(BigDecimal.valueOf(count), DIVISION_SCALE, RoundingMode.HALF_UP);

        // Totais do usuário sobre os MESMOS válidos das médias — só soma,
        // sem arredondamento forçado (precisão natural do motor).
        BigDecimal totalDailyKwh = valid.stream()
                .map(ConsumeMetricsService::calculateDailyKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal totalAnnualKwh = valid.stream()
                .map(ConsumeMetricsService::calculateAnnualKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        // Tarifa da FONTE ÚNICA (R$/kWh). Ausente → exceção propaga.
        TariffQuote quote = tariffService.getReferenceTariff(LocalDate.now());
        BigDecimal tariffPerKwh = quote.tariffPerKwh();

        // Custo = motor estático (já devolve 2 casas, HALF_UP).
        BigDecimal dailyCost = ConsumptionCalculator.cost(totalDailyKwh, tariffPerKwh);
        BigDecimal annualCost = ConsumptionCalculator.cost(totalAnnualKwh, tariffPerKwh);

        return Optional.of(new ResultDTO(
                user.getId(),
                user.getName(),
                avgDailyKwh,
                avgUseInYear,
                totalDailyKwh,
                totalAnnualKwh,
                dailyCost,
                annualCost,
                registries));
    }

    /**
     * Média <b>ANUAL</b> de consumo por associação (registro) válida do
     * usuário — <b>kWh/ano por associação</b>.
     *
     * <p>SPEC §8.3: {@code Σ calculateAnnualKwh(registro) ÷ nº de registros
     * válidos}, escala 6, HALF_UP. Registros sem potência ou sem horas
     * ativas são excluídos ({@link #hasValidActiveInputs}), não contam
     * como ZERO.
     *
     * <p><b>Não confundir</b> com a média por unidade física
     * ({@code Σ E ÷ Σ q}) — métrica distinta (SPEC §8.3).
     *
     * @param user usuário dono dos registros (não pode ser null)
     * @return média anual em <b>kWh/ano</b>, ou vazio se não houver
     *         registros válidos
     * @throws NullPointerException se {@code user} for null
     */
    @Override
    public Optional<BigDecimal> calculateAverageEnergyByUser(User user) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");

        List<RegistryUserProduct> valid = getProductsRegistrys(user).stream()
                .filter(ConsumeMetricsService::hasComputableActiveInputs)
                .toList();

        if (valid.isEmpty()) {
            return Optional.empty();
        }

        BigDecimal totalAnnualKwh = valid.stream()
                .map(ConsumeMetricsService::calculateAnnualKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        return Optional.of(totalAnnualKwh
                .divide(BigDecimal.valueOf(valid.size()), DIVISION_SCALE, RoundingMode.HALF_UP));
    }

    /**
     * Produto de maior consumo do usuário, comparado pelo consumo
     * <b>diário</b> incluindo a quantidade ({@code kWh/dia}).
     *
     * <p>Como todos os registros usam o mesmo período (365 dias), o
     * ranking anual é idêntico ao diário (SPEC §8.3). Registros sem
     * entradas válidas são ignorados.
     *
     * @param user usuário dono dos registros (não pode ser null)
     * @return o {@link Product} vencedor, ou vazio se não houver registros
     *         válidos
     * @throws NullPointerException se {@code user} for null
     */
    @Override
    public Optional<Product> calculateMostConsumerProduct(User user) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");

        return getProductsRegistrys(user).stream()
                .filter(ConsumeMetricsService::hasComputableActiveInputs)
                .max(Comparator.comparing(ConsumeMetricsService::calculateDailyKwh))
                .map(RegistryUserProduct::getProduct);
    }

    /**
     * Produtos da categoria pedida, ordenados por consumo <b>diário</b>
     * ({@code kWh/dia}, incluindo quantidade) em ordem <b>DESC</b>.
     *
     * <p>Categoria comparada com {@code equalsIgnoreCase}; registros sem
     * entradas válidas são ignorados.
     *
     * @param user     usuário dono dos registros (não pode ser null)
     * @param category categoria a filtrar (null/blank → não calculável)
     * @return lista ordenada DESC, ou vazio se a categoria for
     *         null/blank ou não tiver match
     * @throws NullPointerException se {@code user} for null
     */
    @Override
    public Optional<List<Product>> calculateMostConsumerProductByCategory(User user, String category) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");
        if (category == null || category.isBlank()) {
            return Optional.empty();
        }

        List<Product> ranked = getProductsRegistrys(user).stream()
                .filter(ConsumeMetricsService::hasComputableActiveInputs)
                .filter(r -> r.getProduct().getCategory() != null
                        && r.getProduct().getCategory().equalsIgnoreCase(category))
                .sorted(Comparator.comparing(ConsumeMetricsService::calculateDailyKwh).reversed())
                .map(RegistryUserProduct::getProduct)
                .toList();

        return ranked.isEmpty() ? Optional.empty() : Optional.of(ranked);
    }

    /**
     * Média do consumo em <b>standby</b> — valor ANUAL (kWh/ano).
     *
     * <p><b>NÃO CALCULÁVEL:</b> a potência de standby
     * ({@code Product.avg_idle_energy_for_hour}) ainda não tem dado
     * confiável (SPEC §7 / decision_004). <b>NUNCA</b> usar
     * {@code Product.avgPowerW} (potência ATIVA) como standby nem tratar
     * ausência de medição como potência zero. Retorna
     * {@link Optional#empty()} até que a potência de standby tenha fonte
     * confiável.
     *
     * @param user usuário dono dos registros (não pode ser null)
     * @return sempre {@link Optional#empty()} (standby não calculável)
     * @throws NullPointerException se {@code user} for null
     */
    @Override
    public Optional<BigDecimal> calculateStandbyConsumeAvg(User user) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");
        return Optional.empty();
    }

    /**
     * Consumo em <b>standby</b> de um produto específico — valor ANUAL
     * (kWh/ano).
     *
     * <p><b>NÃO CALCULÁVEL:</b> a potência de standby
     * ({@code Product.avg_idle_energy_for_hour}) ainda não tem dado
     * confiável (SPEC §7 / decision_004). <b>NUNCA</b> usar
     * {@code Product.avgPowerW} (potência ATIVA) como standby. Retorna
     * {@link Optional#empty()} até que a potência de standby tenha fonte
     * confiável.
     *
     * @param user    usuário dono do registro (não pode ser null)
     * @param product produto alvo (não pode ser null)
     * @return sempre {@link Optional#empty()} (standby não calculável)
     * @throws NullPointerException se {@code user} ou {@code product} forem null
     */
    @Override
    public Optional<BigDecimal> calculateStandbyConsumesForProduct(User user, Product product) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");
        Objects.requireNonNull(product, "O produto não pode ser nulo.");
        return Optional.empty();
    }

    /**
     * Registros de produtos do usuário.
     *
     * <p>decision_004: <b>nunca null e nunca exception por lista vazia</b> —
     * ausência de registros é resultado válido. Somente entrada nula é
     * rejeitada.
     *
     * @param user usuário dono dos registros (não pode ser null)
     * @return a lista retornada pelo repositório (possivelmente vazia)
     * @throws NullPointerException se {@code user} for null
     */
    @Override
    public List<RegistryUserProduct> getProductsRegistrys(User user) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");
        return registryRepository.findByUser(user);
    }

    /**
     * Média dos elementos numéricos de uma lista heterogênea.
     *
     * <p><b>Limitação do curinga {@code List<?>} (decision_004, OQ
     * aberta):</b> a assinatura não define quais valores somar — aqui
     * somente elementos {@code instanceof Number} entram na soma (nulos e
     * objetos não numéricos são ignorados), convertidos via
     * {@code BigDecimal} (sem passar por double/float). A contagem é o
     * número de elementos numéricos efetivamente somados.
     *
     * <p>{@code value} atua como <b>guarda de validade</b>: se for null o
     * resultado é não calculável ({@link Optional#empty()}); não é
     * incorporado à soma. Se o DEV autorizar mudança de assinatura, este
     * método deve virar um tipo tipado (decision_004 OQ).
     *
     * @param value valor de referência (guarda: null → vazio)
     * @param arry  lista mista com os elementos a somar (pode ser null)
     * @return média em escala 6 (HALF_UP), ou vazio se não houver
     *         elementos numéricos
     */
    @Override
    public Optional<BigDecimal> avg(BigDecimal value, List<?> arry) {
        if (value == null) {
            return Optional.empty();
        }
        if (arry == null) {
            return Optional.empty();
        }

        List<BigDecimal> numbers = arry.stream()
                .filter(Objects::nonNull)
                .filter(Number.class::isInstance)
                .map(Number.class::cast)
                .map(n -> new BigDecimal(n.toString()))
                .toList();

        if (numbers.isEmpty()) {
            return Optional.empty();
        }

        BigDecimal sum = numbers.stream()
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        return Optional.of(sum.divide(
                BigDecimal.valueOf(numbers.size()), DIVISION_SCALE, RoundingMode.HALF_UP));
    }
}
