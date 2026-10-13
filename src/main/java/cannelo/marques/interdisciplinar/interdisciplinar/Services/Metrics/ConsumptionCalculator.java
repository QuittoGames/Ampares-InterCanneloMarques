package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.util.Optional;

import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.InputValidationException;

/**
 * Função pura de cálculo de consumo energético — camada de primitivas
 * do Formula Bank.
 *
 * <p><b>Formula Bank (camada primitiva).</b> A partir do refactor do
 * hub unificado de métricas (decision_001), esta classe sobrevive como
 * <i>camada de primitivas</i> em {@link BigDecimal}: fórmulas atômicas,
 * puras e determinísticas, consumidas pelo hub
 * {@code Services.MetricsService}. Os métodos do Formula Bank validam
 * inputs explicitamente — null ou valor fora de domínio lança
 * {@link InputValidationException}; nenhum null vira ZERO silencioso.
 * Valores não calculáveis (ex.: standby sem potência, horas derivadas
 * fora de [0,24]) são representados por {@link Optional#empty()}.
 *
 * <p><b>Convenções numéricas:</b>
 * <ul>
 *   <li>Escala interna alta ({@link MathContext#DECIMAL128}) nas cadeias
 *       de multiplicação/divisão, para não perder precisão;</li>
 *   <li>Arredondamento monetário {@code HALF_UP} com 2 casas somente no
 *       desenho da saída (métodos {@code cost*});</li>
 *   <li>{@code DAYS_PER_YEAR = 365} (ano de 365 dias — sem bissexto);
 *       {@code MONTHS_PER_YEAR = 12} (convenção de mês médio: ano / 12,
 *       não ponderado por dias reais do período).</li>
 * </ul>
 */
public final class ConsumptionCalculator {

    // ---- constantes do Formula Bank ----

    /** Dias em um ano — convenção de ano de 365 dias (base kWh/ano ↔ kWh/dia). */
    private static final BigDecimal DAYS_PER_YEAR = new BigDecimal("365");

    /** Meses em um ano — convenção de "mês médio" (ano / 12). */
    private static final BigDecimal MONTHS_PER_YEAR = new BigDecimal("12");

    /** Fator de conversão W → kW (dividir por 1000). */
    private static final BigDecimal WATTS_PER_KILOWATT = new BigDecimal("1000");

    /** Contexto matemático interno de alta precisão (34 dígitos significativos). */
    private static final MathContext MATH_CONTEXT = MathContext.DECIMAL128;

    /** Escala das saídas monetárias (R$) — arredondamento HALF_UP. */
    private static final int MONETARY_SCALE = 2;

    /** Escala das saídas de horas/dia derivadas (inversa). */
    private static final int HOUR_SCALE = 4;

    /** Limite superior de horas por dia (inclusivo). */
    private static final BigDecimal MAX_HOURS_PER_DAY = new BigDecimal("24");

    /** Unidade mínima de quantidade de unidades de um produto. */
    private static final BigDecimal MIN_QUANTITY = BigDecimal.ONE;

    private ConsumptionCalculator() {
    }

    // =====================================================================
    // Formula Bank — consumo do PERFIL (potência × horas × quantidade)
    // =====================================================================

    /**
     * Consumo diário de um item do perfil.
     *
     * <pre>
     * dailyKwh = P (W) × h_dia × q / 1000
     * </pre>
     *
     * @param powerW     potência ativa nominal (W); deve ser &gt; 0
     * @param hoursPerDay horas ativas por dia; deve estar em [0, 24]
     * @param quantity   quantidade de unidades; deve ser &gt;= 1
     * @return consumo em <b>kWh/dia</b>
     * @throws InputValidationException se algum input for null, potência
     *         não positiva, horas fora de [0,24] ou quantidade &lt; 1
     */
    public static BigDecimal dailyKwh(BigDecimal powerW, BigDecimal hoursPerDay,
            BigDecimal quantity) {
        requirePositivePower(powerW, "powerW");
        requireHoursInRange(hoursPerDay, "hoursPerDay");
        requireQuantity(quantity, "quantity");
        return powerW.multiply(hoursPerDay).multiply(quantity)
                .divide(WATTS_PER_KILOWATT, MATH_CONTEXT);
    }

    /**
     * Consumo de um período a partir do consumo diário.
     *
     * <pre>
     * monthlyKwh = dailyKwh × daysInPeriod
     * </pre>
     *
     * @param dailyKwh     consumo diário (kWh/dia)
     * @param daysInPeriod número de dias do período; deve ser &gt;= 1
     * @return consumo do período em <b>kWh</b>
     * @throws InputValidationException se input null ou dias &lt; 1
     */
    public static BigDecimal monthlyKwh(BigDecimal dailyKwh, BigDecimal daysInPeriod) {
        if (dailyKwh == null) {
            throw new InputValidationException("dailyKwh não pode ser nulo");
        }
        requireQuantity(daysInPeriod, "daysInPeriod");
        return dailyKwh.multiply(daysInPeriod, MATH_CONTEXT);
    }

    /**
     * Consumo médio mensal a partir do consumo anual.
     *
     * <pre>
     * averageMonthKwh = annualKwh / 12
     * </pre>
     *
     * <p><b>Convenção de mês médio:</b> divide-se por 12 meses fixos, sem
     * ponderar por dias reais de cada mês. Um "mês médio" tem 365/12 dias.
     *
     * @param annualKwh consumo anual (kWh/ano); deve ser &gt;= 0
     * @return consumo médio mensal em <b>kWh/mês</b>
     * @throws InputValidationException se input null ou negativo
     */
    public static BigDecimal averageMonthKwh(BigDecimal annualKwh) {
        requireNonNegative(annualKwh, "annualKwh");
        return annualKwh.divide(MONTHS_PER_YEAR, MATH_CONTEXT);
    }

    /**
     * Consumo anual a partir do consumo diário.
     *
     * <pre>
     * annualKwh = dailyKwh × 365
     * </pre>
     *
     * @param dailyKwh consumo diário (kWh/dia); deve ser &gt;= 0
     * @return consumo anual em <b>kWh/ano</b>
     * @throws InputValidationException se input null ou negativo
     */
    public static BigDecimal annualKwh(BigDecimal dailyKwh) {
        requireNonNegative(dailyKwh, "dailyKwh");
        return dailyKwh.multiply(DAYS_PER_YEAR, MATH_CONTEXT);
    }

    // =====================================================================
    // Formula Bank — consumo da FONTE (dados do catálogo Product)
    // =====================================================================
    // IMPORTANTE: o consumo da fonte Product (annualEnergyKwh do catálogo)
    // é um dado declarado pelo fabricante e NUNCA deve ser misturado com o
    // consumo do perfil do usuário (registry). Camadas separadas.

    /**
     * Consumo anual da fonte (catálogo) escalado pela quantidade.
     *
     * <pre>
     * sourceAnnualKwh = productAnnualKwh × q
     * </pre>
     *
     * @param productAnnualKwh energia anual declarada no catálogo (kWh/ano); &gt;= 0
     * @param quantity         quantidade de unidades; deve ser &gt;= 1
     * @return consumo anual da fonte em <b>kWh/ano</b>
     * @throws InputValidationException se input null, negativo ou q &lt; 1
     */
    public static BigDecimal sourceAnnualKwh(BigDecimal productAnnualKwh, BigDecimal quantity) {
        requireNonNegative(productAnnualKwh, "productAnnualKwh");
        requireQuantity(quantity, "quantity");
        return productAnnualKwh.multiply(quantity, MATH_CONTEXT);
    }

    /**
     * Consumo diário da fonte (catálogo) escalado pela quantidade.
     *
     * <pre>
     * sourceDailyKwh = productAnnualKwh × q / 365
     * </pre>
     *
     * @param productAnnualKwh energia anual declarada no catálogo (kWh/ano); &gt;= 0
     * @param quantity         quantidade de unidades; deve ser &gt;= 1
     * @return consumo diário da fonte em <b>kWh/dia</b>
     * @throws InputValidationException se input null, negativo ou q &lt; 1
     */
    public static BigDecimal sourceDailyKwh(BigDecimal productAnnualKwh, BigDecimal quantity) {
        return sourceAnnualKwh(productAnnualKwh, quantity)
                .divide(DAYS_PER_YEAR, MATH_CONTEXT);
    }

    /**
     * Consumo médio mensal da fonte (catálogo) escalado pela quantidade.
     *
     * <pre>
     * sourceAverageMonthKwh = productAnnualKwh × q / 12
     * </pre>
     *
     * <p>Convenção de mês médio: 12 meses fixos (ver
     * {@link #averageMonthKwh(BigDecimal)}).
     *
     * @param productAnnualKwh energia anual declarada no catálogo (kWh/ano); &gt;= 0
     * @param quantity         quantidade de unidades; deve ser &gt;= 1
     * @return consumo médio mensal da fonte em <b>kWh/mês</b>
     * @throws InputValidationException se input null, negativo ou q &lt; 1
     */
    public static BigDecimal sourceAverageMonthKwh(BigDecimal productAnnualKwh,
            BigDecimal quantity) {
        return sourceAnnualKwh(productAnnualKwh, quantity)
                .divide(MONTHS_PER_YEAR, MATH_CONTEXT);
    }

    // =====================================================================
    // Formula Bank — custo
    // =====================================================================

    /**
     * Custo monetário de um consumo de energia.
     *
     * <pre>
     * cost = kwh × T (R$/kWh)
     * </pre>
     *
     * <p>Precisão interna em {@link MathContext#DECIMAL128}; o
     * arredondamento monetário {@code HALF_UP} com 2 casas é aplicado
     * somente no desenho desta saída.
     *
     * @param kwh          consumo em kWh; deve ser &gt;= 0
     * @param tariffPerKwh tarifa em R$/kWh; deve ser &gt;= 0
     * @return custo em <b>R$</b> com 2 casas decimais (HALF_UP)
     * @throws InputValidationException se algum input for null ou negativo
     */
    public static BigDecimal cost(BigDecimal kwh, BigDecimal tariffPerKwh) {
        requireNonNegative(kwh, "kwh");
        requireNonNegative(tariffPerKwh, "tariffPerKwh");
        return kwh.multiply(tariffPerKwh, MATH_CONTEXT)
                .setScale(MONETARY_SCALE, RoundingMode.HALF_UP);
    }

    // =====================================================================
    // Formula Bank — standby (modo espera)
    // =====================================================================
    // A potência de standby é um atributo DISTINTO da potência ativa.
    // Se for null, o estado é NÃO CALCULÁVEL (Optional.empty()): jamais se
    // usa a potência ativa como standby e jamais se trate null como zero.

    /**
     * Consumo diário em modo standby.
     *
     * <pre>
     * standbyDailyKwh = P_standby (W) × h_standby × q / 1000
     * </pre>
     *
     * @param standbyPowerW potência em standby (W); {@code null} → não
     *                      calculável; valores &lt;= 0 → exceção
     * @param hoursStandby  horas em standby por dia; deve estar em [0, 24]
     * @param quantity      quantidade de unidades; deve ser &gt;= 1
     * @return consumo diário de standby em <b>kWh/dia</b>, ou vazio se a
     *         potência de standby for ausente (não calculável)
     * @throws InputValidationException se horas/quantidade inválidas ou
     *         potência de standby não nula porém não positiva
     */
    public static Optional<BigDecimal> standbyDailyKwh(
            BigDecimal standbyPowerW, BigDecimal hoursStandby, BigDecimal quantity) {
        if (standbyPowerW == null) {
            return Optional.empty();
        }
        requirePositivePower(standbyPowerW, "standbyPowerW");
        requireHoursInRange(hoursStandby, "hoursStandby");
        requireQuantity(quantity, "quantity");
        return Optional.of(standbyPowerW.multiply(hoursStandby).multiply(quantity)
                .divide(WATTS_PER_KILOWATT, MATH_CONTEXT));
    }

    /**
     * Consumo anual em modo standby.
     *
     * <pre>
     * standbyAnnualKwh = standbyDailyKwh × 365
     * </pre>
     *
     * @param standbyPowerW potência em standby (W); {@code null} → não calculável
     * @param hoursStandby  horas em standby por dia; deve estar em [0, 24]
     * @param quantity      quantidade de unidades; deve ser &gt;= 1
     * @return consumo anual de standby em <b>kWh/ano</b>, ou vazio se não
     *         calculável
     * @throws InputValidationException se inputs presentes forem inválidos
     */
    public static Optional<BigDecimal> standbyAnnualKwh(
            BigDecimal standbyPowerW, BigDecimal hoursStandby, BigDecimal quantity) {
        return standbyDailyKwh(standbyPowerW, hoursStandby, quantity)
                .map(daily -> daily.multiply(DAYS_PER_YEAR, MATH_CONTEXT));
    }

    /**
     * Custo anual do modo standby.
     *
     * <pre>
     * standbyAnnualCost = standbyAnnualKwh × T (R$/kWh)
     * </pre>
     *
     * @param standbyPowerW potência em standby (W); {@code null} → não calculável
     * @param hoursStandby  horas em standby por dia; deve estar em [0, 24]
     * @param quantity      quantidade de unidades; deve ser &gt;= 1
     * @param tariffPerKwh  tarifa em R$/kWh; deve ser &gt;= 0
     * @return custo anual de standby em <b>R$/ano</b> (2 casas, HALF_UP),
     *         ou vazio se não calculável
     * @throws InputValidationException se inputs presentes forem inválidos
     */
    public static Optional<BigDecimal> standbyAnnualCost(
            BigDecimal standbyPowerW, BigDecimal hoursStandby, BigDecimal quantity,
            BigDecimal tariffPerKwh) {
        requireNonNegative(tariffPerKwh, "tariffPerKwh");
        return standbyAnnualKwh(standbyPowerW, hoursStandby, quantity)
                .map(annual -> cost(annual, tariffPerKwh));
    }

    // =====================================================================
    // Formula Bank — inversa (horas/dia derivadas de energia anual)
    // =====================================================================

    /**
     * Horas ativas por dia derivadas da energia anual — a inversa de
     * {@link #dailyKwh(BigDecimal, BigDecimal, BigDecimal)}:
     *
     * <pre>
     *          E_ano (kWh) × 1000
     * H/dia = ─────────────────────
     *          P (W) × q × 365
     * </pre>
     *
     * <p>CONDICIONAL: exige {@code powerW > 0} e {@code quantity >= 1}
     * (divisão por zero é erro de entrada). Se o resultado cair fora de
     * [0, 24] o estado é <b>não calculável</b> ({@link Optional#empty()})
     * — o valor NUNCA é cortado artificialmente em 24.
     *
     * @param annualKwh consumo anual (kWh/ano); deve ser &gt;= 0
     * @param powerW    potência ativa (W); deve ser &gt; 0
     * @param quantity  quantidade de unidades; deve ser &gt;= 1
     * @return horas ativas por dia (escala 4) em <b>h/dia</b>, ou vazio se
     *         não calculável (fora de [0,24])
     * @throws InputValidationException se algum input for null, energia
     *         negativa, potência não positiva ou quantidade &lt; 1
     */
    public static Optional<BigDecimal> inverseDailyHours(
            BigDecimal annualKwh, BigDecimal powerW, BigDecimal quantity) {
        requireNonNegative(annualKwh, "annualKwh");
        requirePositivePower(powerW, "powerW");
        requireQuantity(quantity, "quantity");

        BigDecimal hours = annualKwh.multiply(WATTS_PER_KILOWATT)
                .divide(powerW.multiply(quantity).multiply(DAYS_PER_YEAR), MATH_CONTEXT);

        if (hours.signum() < 0 || hours.compareTo(MAX_HOURS_PER_DAY) > 0) {
            return Optional.empty();
        }
        return Optional.of(hours.setScale(HOUR_SCALE, RoundingMode.HALF_UP));
    }

    // =====================================================================
    // Validações (somente para métodos do Formula Bank)
    // =====================================================================

    private static void requirePositivePower(BigDecimal value, String name) {
        if (value == null) {
            throw new InputValidationException(name + " não pode ser nulo");
        }
        if (value.signum() <= 0) {
            throw new InputValidationException(name + " deve ser maior que zero (W), recebido: " + value);
        }
    }

    private static void requireNonNegative(BigDecimal value, String name) {
        if (value == null) {
            throw new InputValidationException(name + " não pode ser nulo");
        }
        if (value.signum() < 0) {
            throw new InputValidationException(name + " não pode ser negativo, recebido: " + value);
        }
    }

    private static void requireHoursInRange(BigDecimal value, String name) {
        if (value == null) {
            throw new InputValidationException(name + " não pode ser nulo");
        }
        if (value.signum() < 0 || value.compareTo(MAX_HOURS_PER_DAY) > 0) {
            throw new InputValidationException(
                    name + " deve estar em [0, 24] horas/dia, recebido: " + value);
        }
    }

    private static void requireQuantity(BigDecimal value, String name) {
        if (value == null) {
            throw new InputValidationException(name + " não pode ser nulo");
        }
        if (value.compareTo(MIN_QUANTITY) < 0) {
            throw new InputValidationException(
                    name + " deve ser maior ou igual a 1, recebido: " + value);
        }
    }
}
