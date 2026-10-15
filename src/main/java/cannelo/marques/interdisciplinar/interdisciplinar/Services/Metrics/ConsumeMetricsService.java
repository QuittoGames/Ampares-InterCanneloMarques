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
 * para as fórmulas static do motor. O standby é calculado
 * exclusivamente por {@link StandbyMetricsService} (dependência
 * unidirecional hub → serviço de standby).
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
 * <p><b>Política de consumo TOTAL (decisão do DEV):</b> médias, totais,
 * custos e rankings do {@link ResultDTO} somam
 * {@code E_active + E_standby} por registro. Quando o standby não é
 * calculável (potência de standby ausente no produto ou
 * {@code hoursStandby} ausente), o standby contribui <b>zero no TOTAL</b>
 * e o total é apenas o ativo — comportamento idêntico ao anterior nesse
 * caso. Os endpoints DEDICADOS de standby
 * ({@code calculateStandbyConsumeAvg}/{@code calculateStandbyConsumesForProduct})
 * mantêm a semântica de {@link Optional#empty()} — nunca zero.
 * Registro com {@code hoursStandby} presente porém inválido (negativo,
 * &gt; 24 ou soma {@code Hactive + Hstandby} &gt; 24 h/dia) é
 * <b>excluído dos agregados</b>, como já acontece com entradas ativas
 * inválidas — nunca vira zero e nunca derruba os demais.
 *
 * <p><b>Unidades:</b> helpers diários em kWh/dia, helpers anuais em
 * kWh/ano, médias em kWh/ano (escala 6, HALF_UP), custos em R$/dia e
 * R$/ano (2 casas, HALF_UP — aplicado pelo motor
 * {@link ConsumptionCalculator#cost}). Standby é sempre valor
 * ANUAL quando exposto pelos endpoints dedicados (SPEC §8 /
 * "Return in Year value").
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
    private final StandbyMetricsService standbyMetricsService;

    public ConsumeMetricsService(RegistryUserProductRepository registryRepository,
            TariffService tariffService, StandbyMetricsService standbyMetricsService) {
        this.registryRepository = registryRepository;
        this.tariffService = tariffService;
        this.standbyMetricsService = standbyMetricsService;
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
     * Verifica se o registro é <b>computável no consumo TOTAL</b>
     * (ativo + standby): ativo computável E standby sem inconsistência.
     *
     * <p>Um registro com {@code hoursStandby} presente porém inválido
     * (negativo, &gt; 24 h/dia, ou soma {@code Hactive + Hstandby} &gt;
     * 24 h/dia) é <b>excluído dos agregados</b> — mesma convenção das
     * entradas ativas inválidas: nunca vira ZERO e nunca derruba o
     * cálculo dos demais. Potência de standby ausente NÃO exclui
     * (standby não calculável contribui 0 no total, mas o registro
     * continua válido pelo consumo ativo). Potência de standby presente
     * porém ≤ 0 também exclui (entrada inválida, coerente com o ativo).
     *
     * @param r registro de produto do usuário (pode ser null)
     * @return {@code true} se o registro participa dos agregados totais
     */
    private boolean hasComputableTotalInputs(RegistryUserProduct r) {
        if (!hasComputableActiveInputs(r)) {
            return false;
        }
        try {
            // Valida consistência do standby (horas e soma ≤ 24h/dia);
            // potência ausente → empty (ok), presente inválida → exceção.
            standbyMetricsService.calculateDailyStandbyKwh(r);
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

    // =====================================================================
    // Pontes hub → StandbyMetricsService (dependência unidirecional)
    // =====================================================================

    /**
     * <b>Ponte A</b> — consumo diário de standby de um registro
     * (<b>kWh/dia</b>).
     *
     * <p>Só extrai e encaminha para
     * {@link StandbyMetricsService#calculateDailyStandbyKwh(RegistryUserProduct)}
     * — nenhuma fórmula é replicada aqui.
     *
     * @param registro registro de produto do usuário (pode ser null)
     * @return consumo diário de standby em <b>kWh/dia</b>, ou
     *         {@link Optional#empty()} se não calculável (potência ou
     *         horas de standby ausentes — nunca zero)
     * @throws InputValidationException se os inputs de standby forem
     *         inválidos (propaga do serviço de standby)
     */
    public Optional<BigDecimal> calculateStandbyEnergy(RegistryUserProduct registro) {
        return standbyMetricsService.calculateDailyStandbyKwh(registro);
    }

    /**
     * <b>Ponte B</b> — consumo <b>diário TOTAL</b> do registro:
     * {@code E_active + E_standby}.
     *
     * <p>Quando o standby não é calculável (potência ou horas ausentes),
     * contribui {@link BigDecimal#ZERO} no TOTAL — o total é apenas o
     * ativo, comportamento idêntico ao anterior. Quando o standby está
     * presente porém inválido, o {@link InputValidationException}
     * propaga (esses registros são excluídos dos agregados pelo guarda
     * {@link #hasComputableTotalInputs}).
     *
     * @param r registro com entradas ativas computáveis
     * @return consumo total diário em <b>kWh/dia</b>
     * @throws InputValidationException se os inputs forem inválidos (via motor)
     */
    private BigDecimal calculateTotalDailyKwh(RegistryUserProduct r) {
        BigDecimal standbyDaily = standbyMetricsService.calculateDailyStandbyKwh(r)
                .orElse(BigDecimal.ZERO);
        return calculateDailyKwh(r).add(standbyDaily);
    }

    /**
     * Consumo <b>anual TOTAL</b> do registro — <b>kWh/ano</b>.
     *
     * <p>{@code annualKwh = calculateTotalDailyKwh(r) × 365}, delegando a
     * {@link ConsumptionCalculator#annualKwh(BigDecimal)} — anual sempre
     * derivado do diário pelo motor, nunca multiplicação inline.
     *
     * @param r registro com entradas ativas computáveis
     * @return consumo total anual em <b>kWh/ano</b>
     * @throws InputValidationException se os inputs forem inválidos (via motor)
     */
    private BigDecimal calculateTotalAnnualKwh(RegistryUserProduct r) {
        return ConsumptionCalculator.annualKwh(calculateTotalDailyKwh(r));
    }

    // =====================================================================
    // Contrato MetricsService
    // =====================================================================

    /**
     * Monta o resultado geral do usuário — consumo <b>TOTAL</b>
     * ({@code E_active + E_standby} por registro; decisão do DEV).
     *
     * <p>Calcula, via stream sobre os registros com entradas computáveis
     * no total (ativo válido e standby sem inconsistência):
     * <ul>
     *   <li>{@code avgDailyKwh} — <b>média de consumo diário total</b> por
     *       associação válida em <b>kWh/dia</b> (Σ calculateTotalDailyKwh ÷
     *       nº de válidos, escala 6, HALF_UP);</li>
     *   <li>{@code avgUseInYear} — <b>média de consumo anual total</b> por
     *       associação válida em <b>kWh/ano</b> (Σ calculateTotalAnnualKwh ÷
     *       nº de válidos, escala 6, HALF_UP);</li>
     *   <li>{@code totalDailyKwh} — <b>total diário</b> do usuário em
     *       <b>kWh/dia</b> (Σ calculateTotalDailyKwh sobre os mesmos
     *       válidos, sem arredondamento forçado — soma com a precisão do
     *       motor);</li>
     *   <li>{@code totalAnnualKwh} — <b>total anual</b> do usuário em
     *       <b>kWh/ano</b> (Σ calculateTotalAnnualKwh sobre os mesmos
     *       válidos, anual = diário × 365 pelo motor — não é
     *       multiplicação inline);</li>
     *   <li>{@code dailyCost} / {@code annualCost} — <b>gasto</b> em
     *       <b>R$/dia</b> e <b>R$/ano</b>, obtidos com
     *       {@link ConsumptionCalculator#cost(BigDecimal, BigDecimal)}
     *       sobre a tarifa de {@link TariffService} (2 casas, HALF_UP já
     *       aplicado pelo motor — não duplicado aqui);</li>
     *   <li>{@code productsList} — todos os registros do usuário
     *       (incluindo os sem entradas válidas, para exibição).</li>
     * </ul>
     *
     * <p>Quando o standby de um registro não é calculável (potência de
     * standby ausente no produto ou {@code hoursStandby} ausente), o
     * standby contribui <b>zero no TOTAL</b> e o total daquele registro é
     * apenas o ativo — comportamento idêntico ao anterior. Standby
     * presente porém inválido (negativo, &gt; 24 h/dia ou soma
     * {@code Hactive + Hstandby} &gt; 24) exclui o registro dos agregados.
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
                .filter(this::hasComputableTotalInputs)
                .toList();

        if (valid.isEmpty()) {
            return Optional.empty();
        }

        int count = valid.size();

        // Polítca de consumo TOTAL: E_active + E_standby por registro
        // (standby não calculável contribui 0 no total — só o ativo).
        BigDecimal avgDailyKwh = valid.stream()
                .map(this::calculateTotalDailyKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .divide(BigDecimal.valueOf(count), DIVISION_SCALE, RoundingMode.HALF_UP);

        BigDecimal avgUseInYear = valid.stream()
                .map(this::calculateTotalAnnualKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .divide(BigDecimal.valueOf(count), DIVISION_SCALE, RoundingMode.HALF_UP);

        // Totais do usuário sobre os MESMOS válidos das médias — só soma,
        // sem arredondamento forçado (precisão natural do motor).
        BigDecimal totalDailyKwh = valid.stream()
                .map(this::calculateTotalDailyKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        BigDecimal totalAnnualKwh = valid.stream()
                .map(this::calculateTotalAnnualKwh)
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
     * Média <b>ANUAL</b> de consumo total (ativo + standby) por
     * associação (registro) válida do usuário — <b>kWh/ano por
     * associação</b>.
     *
     * <p>SPEC §8.3: {@code Σ calculateTotalAnnualKwh(registro) ÷ nº de
     * registros válidos}, escala 6, HALF_UP. Registros sem potência ou
     * sem horas ativas são excluídos ({@link #hasValidActiveInputs}),
     * não contam como ZERO; registros com standby inconsistente também
     * são excluídos ({@link #hasComputableTotalInputs}). Standby não
     * calculável contribui 0 no total do registro.
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
                .filter(this::hasComputableTotalInputs)
                .toList();

        if (valid.isEmpty()) {
            return Optional.empty();
        }

        BigDecimal totalAnnualKwh = valid.stream()
                .map(this::calculateTotalAnnualKwh)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        return Optional.of(totalAnnualKwh
                .divide(BigDecimal.valueOf(valid.size()), DIVISION_SCALE, RoundingMode.HALF_UP));
    }

    /**
     * Produto de maior consumo do usuário, comparado pelo consumo
     * <b>diário TOTAL</b> ({@code E_active + E_standby}, incluindo a
     * quantidade — {@code kWh/dia}).
     *
     * <p>Como todos os registros usam o mesmo período (365 dias), o
     * ranking anual é idêntico ao diário (SPEC §8.3). Registros sem
     * entradas válidas ou com standby inconsistente são ignorados;
     * standby não calculável contribui 0 (ranking = ativo).
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
                .filter(this::hasComputableTotalInputs)
                .max(Comparator.comparing(this::calculateTotalDailyKwh))
                .map(RegistryUserProduct::getProduct);
    }

    /**
     * Produtos da categoria pedida, ordenados por consumo <b>diário
     * TOTAL</b> ({@code E_active + E_standby}, {@code kWh/dia}, incluindo
     * quantidade) em ordem <b>DESC</b>.
     *
     * <p>Categoria comparada com {@code equalsIgnoreCase}; registros sem
     * entradas válidas ou com standby inconsistente são ignorados.
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
                .filter(this::hasComputableTotalInputs)
                .filter(r -> r.getProduct().getCategory() != null
                        && r.getProduct().getCategory().equalsIgnoreCase(category))
                .sorted(Comparator.comparing(this::calculateTotalDailyKwh).reversed())
                .map(RegistryUserProduct::getProduct)
                .toList();

        return ranked.isEmpty() ? Optional.empty() : Optional.of(ranked);
    }

    /**
     * Média do consumo em <b>standby</b> — valor ANUAL (<b>kWh/ano</b>).
     *
     * <p>{@code Σ standbyAnnualKwh(registro) ÷ nº de registros em que o
     * standby é calculável}, escala 6, HALF_UP. Fonte da potência de
     * standby: {@code Product.avgIdleEnergyForHour} — <b>NUNCA</b>
     * {@code Product.avgPowerW} (potência ATIVA) nem standby zero por
     * ausência de dado.
     *
     * <p>Semântica de dados ausentes (decision_004 / SPEC §7): potência
     * de standby ausente ou {@code hoursStandby} ausente → registro
     * <b>não calculável</b>, excluído da média (não contam como ZERO).
     * Se nenhum registro for calculável → {@link Optional#empty()}.
     * Registro com standby presente porém inválido (negativo, &gt; 24
     * h/dia ou soma {@code Hactive + Hstandby} &gt; 24 h/dia) é
     * <b>excluído</b> — nunca derruba o cálculo dos demais.
     *
     * @param user usuário dono dos registros (não pode ser null)
     * @return média anual de standby em <b>kWh/ano</b>, ou vazio se
     *         nenhum registro tiver standby calculável
     * @throws NullPointerException se {@code user} for null
     */
    @Override
    public Optional<BigDecimal> calculateStandbyConsumeAvg(User user) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");

        List<BigDecimal> standbyAnnuals = getProductsRegistrys(user).stream()
                .map(this::standbyAnnualIfCalculable)
                .flatMap(Optional::stream)
                .toList();

        if (standbyAnnuals.isEmpty()) {
            return Optional.empty();
        }

        BigDecimal totalAnnualStandby = standbyAnnuals.stream()
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        return Optional.of(totalAnnualStandby
                .divide(BigDecimal.valueOf(standbyAnnuals.size()), DIVISION_SCALE, RoundingMode.HALF_UP));
    }

    /**
     * Consumo em <b>standby</b> de um produto específico — valor ANUAL
     * (<b>kWh/ano</b>).
     *
     * <p>Delega a
     * {@link StandbyMetricsService#calculateAnnualStandbyKwh(RegistryUserProduct)}
     * sobre o registro daquele produto. Fonte da potência de standby:
     * {@code Product.avgIdleEnergyForHour} — <b>NUNCA</b>
     * {@code Product.avgPowerW}.
     *
     * <p>Semântica de dados ausentes: produto sem registro no usuário,
     * potência de standby ausente ou {@code hoursStandby} ausente →
     * {@link Optional#empty()} (não calculável — nunca zero). Standby
     * presente porém inválido também resulta em vazio (registro
     * excluído), nunca exceção para os demais produtos.
     *
     * @param user    usuário dono do registro (não pode ser null)
     * @param product produto alvo (não pode ser null)
     * @return consumo anual de standby do produto em <b>kWh/ano</b>, ou
     *         vazio se não encontrado ou não calculável
     * @throws NullPointerException se {@code user} ou {@code product} forem null
     */
    @Override
    public Optional<BigDecimal> calculateStandbyConsumesForProduct(User user, Product product) {
        Objects.requireNonNull(user, "O usuário não pode ser nulo.");
        Objects.requireNonNull(product, "O produto não pode ser nulo.");

        return getProductsRegistrys(user).stream()
                .filter(r -> r.getProduct() != null && sameProduct(product, r.getProduct()))
                .findFirst()
                .flatMap(this::standbyAnnualIfCalculable);
    }

    /**
     * Compara se duas referências de {@link Product} são o mesmo produto:
     * por {@code id} quando ambos têm id (o controller carrega o produto
     * via repositório — instância pode diferir da do registro), com
     * fallback para {@code equals}.
     *
     * @param a produto alvo (pode ser null)
     * @param b produto do registro (pode ser null)
     * @return {@code true} se representam o mesmo produto
     */
    private static boolean sameProduct(Product a, Product b) {
        if (a == b) {
            return true;
        }
        if (a == null || b == null) {
            return false;
        }
        if (a.getId() != null && b.getId() != null) {
            return a.getId().equals(b.getId());
        }
        return a.equals(b);
    }

    /**
     * Consumo anual de standby do registro, tolerando dados ausentes:
     * standby não calculável (potência ou horas ausentes) ou inválido
     * (exceção do motor/serviço) → {@link Optional#empty()} — o registro
     * é excluído da agregação de standby, nunca vira ZERO e nunca
     * derruba os demais.
     *
     * @param r registro de produto do usuário (pode ser null)
     * @return consumo anual de standby em <b>kWh/ano</b>, ou vazio
     */
    private Optional<BigDecimal> standbyAnnualIfCalculable(RegistryUserProduct r) {
        try {
            return standbyMetricsService.calculateAnnualStandbyKwh(r);
        } catch (InputValidationException e) {
            return Optional.empty();
        }
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
