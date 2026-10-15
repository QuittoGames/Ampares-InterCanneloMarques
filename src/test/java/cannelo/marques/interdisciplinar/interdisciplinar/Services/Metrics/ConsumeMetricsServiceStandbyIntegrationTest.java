package cannelo.marques.interdisciplinar.interdisciplinar.Services.Metrics;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.ResultDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.Product;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;
import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Repository.RegistryUserProductRepository;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffQuote;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Tariff.TariffService;

/**
 * Testes de INTEGRAÇÃO hub ↔ standby: {@link ConsumeMetricsService} com
 * {@link StandbyMetricsService} e {@link HourService} REAIS (sem Spring
 * context) e {@link TariffService}/{@link RegistryUserProductRepository}
 * mockados.
 *
 * <p>Cobrem a política de consumo TOTAL ({@code E_active + E_standby} por
 * registro; standby não calculável contribui 0 no total; standby inválido
 * exclui o registro), os endpoints dedicados de standby (vazio ≠ zero) e
 * a consistência diário × 365 = anual + custos com tarifa.
 */
@ExtendWith(MockitoExtension.class)
class ConsumeMetricsServiceStandbyIntegrationTest {

    /** Tarifa de teste em R$/kWh — mesma do ConsumeMetricsServiceTest. */
    private static final String TEST_TARIFF_PER_KWH = "1.06110";

    @Mock
    private RegistryUserProductRepository registryRepository;

    @Mock
    private TariffService tariffService;

    private ConsumeMetricsService service;
    private User user;

    @BeforeEach
    void setUp() {
        // StandbyMetricsService e HourService REAIS: a integração é o alvo
        // do teste (fórmula e consistência de períodos verificáveis).
        service = new ConsumeMetricsService(registryRepository, tariffService,
                new StandbyMetricsService(new HourService()));
        user = new User(7);
    }

    // =====================================================================
    // Ativo sem standby — comportamento IDÊNTICO ao anterior
    // =====================================================================

    @Nested
    @DisplayName("Ativo sem standby: total = ativo (idêntico ao comportamento anterior)")
    class AtivoSemStandby {

        @Test
        @DisplayName("horasStandby null: total diário = ativo puro; endpoints de standby vazios")
        void horasStandbyNullTotalEhAtivo() {
            // 100W × 5h × 2 / 1000 = 1 kWh/dia → 365 kWh/ano
            when(registryRepository.findByUser(user))
                    .thenReturn(List.of(registry(product("A", "100", null), "5", 2, null)));
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("1").compareTo(result.totalDailyKwh()),
                    "sem standby conhecido, o total é apenas o ativo (1 kWh/dia)");
            assertEquals(0, new BigDecimal("365").compareTo(result.totalAnnualKwh()));
            assertEquals(0, new BigDecimal("1.06").compareTo(result.dailyCost()),
                    "1 × 1.06110 → HALF_UP 2 casas = 1.06");
            assertEquals(0, new BigDecimal("387.30").compareTo(result.annualCost()),
                    "365 × 1.06110 = 387.3015 → 387.30");
            assertTrue(service.calculateStandbyConsumeAvg(user).isEmpty(),
                    "endpoint dedicado de standby continua VAZIO, nunca zero");
        }

        @Test
        @DisplayName("produto com horasStandby preenchidas mas SEM potência de standby: total = ativo; standby vazio")
        void produtoSemPotenciaDeStandbyConhecida() {
            // 1000W × 2h × 1 / 1000 = 2 kWh/dia; horas de standby presentes
            // mas o produto não tem avgIdleEnergyForHour → standby não calculável
            Product semStandby = product("B", "1000", null);
            when(registryRepository.findByUser(user))
                    .thenReturn(List.of(registry(semStandby, "2", 1, "8")));
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("2").compareTo(result.totalDailyKwh()),
                    "potência de standby ausente → total é só o ativo");
            assertEquals(0, new BigDecimal("730").compareTo(result.totalAnnualKwh()));
            assertTrue(service.calculateStandbyConsumeAvg(user).isEmpty());
            assertTrue(service.calculateStandbyConsumesForProduct(user, semStandby).isEmpty(),
                    "potência de standby ausente = vazio, nunca zero nem potência ativa");
        }
    }

    // =====================================================================
    // Ativo + standby — consumo TOTAL por registro
    // =====================================================================

    @Nested
    @DisplayName("Ativo + standby: total = E_active + E_standby por registro")
    class AtivoComStandby {

        @Test
        @DisplayName("100W×5h×2 (ativo) + 2W×8h×2 (standby): total 1.032 kWh/dia → 376.68 kWh/ano")
        void totalSomaAtivoMaisStandby() {
            // ativo: 100×5×2/1000 = 1.0; standby: 2×8×2/1000 = 0.032 → 1.032
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("TV", "100", "2"), "5", 2, "8")));
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("1.032").compareTo(result.totalDailyKwh()),
                    "total diário = ativo + standby, cada um UMA vez");
            // diário × 365 = anual (consistência): 1.032 × 365 = 376.68
            assertEquals(0, new BigDecimal("376.68").compareTo(result.totalAnnualKwh()));
            assertEquals(0, result.totalDailyKwh()
                    .multiply(new BigDecimal("365")).compareTo(result.totalAnnualKwh()),
                    "consistência: total anual = total diário × 365");
            // custos com tarifa 1.06110:
            // 1.032 × 1.06110 = 1.0950552 → HALF_UP = 1.10
            assertEquals(0, new BigDecimal("1.10").compareTo(result.dailyCost()));
            // 376.68 × 1.06110 = 399.695148 → HALF_UP = 399.70
            assertEquals(0, new BigDecimal("399.70").compareTo(result.annualCost()));
            // médias por associação (1 registro): iguais aos totais
            assertEquals(0, new BigDecimal("1.032000").compareTo(result.avgDailyKwh()));
            assertEquals(0, new BigDecimal("376.680000").compareTo(result.avgUseInYear()));
        }

        @Test
        @DisplayName("standby dedicado: média anual = 0.032 × 365 = 11.68 kWh/ano")
        void endpointsDedicadosDeStandby() {
            Product tv = product("TV", "100", "2");
            when(registryRepository.findByUser(user))
                    .thenReturn(List.of(registry(tv, "5", 2, "8")));

            assertEquals(0, new BigDecimal("11.68").compareTo(
                    service.calculateStandbyConsumeAvg(user).orElseThrow()),
                    "standby ANUAL: 2W × 8h × 2 / 1000 × 365 = 11.68 kWh/ano");
            assertEquals(0, new BigDecimal("11.68").compareTo(
                    service.calculateStandbyConsumesForProduct(user, tv).orElseThrow()));
        }

        @Test
        @DisplayName("q > 1 no standby aplicada EXATAMENTE uma vez: 2W×8h×3 = 0.048 (total 1.548)")
        void quantidadeDoStandbyAplicadaUmaVez() {
            // ativo: 100×5×3/1000 = 1.5; standby: 2×8×3/1000 = 0.048 → 1.548
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("TV", "100", "2"), "5", 3, "8")));
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("1.548").compareTo(result.totalDailyKwh()),
                    "q participa UMA vez do standby (0.048, não 0.144) e UMA do ativo");
            assertEquals(0, new BigDecimal("565.02").compareTo(result.totalAnnualKwh()),
                    "1.548 × 365 = 565.02");
        }
    }

    // =====================================================================
    // Agregação de diversos produtos
    // =====================================================================

    @Nested
    @DisplayName("Agregação de diversos produtos (streams sobre os registros)")
    class Agregacao {

        @Test
        @DisplayName("3 produtos: 1.032 + 2.0 + 0.25 = 3.282 kWh/dia; médias e standby só sobre calculáveis")
        void agregaProdutosMistos() {
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    // A: ativo 1.0 + standby 0.032 (calculável)
                    registry(product("A", "100", "2"), "5", 2, "8"),
                    // B: ativo 2.0, standby não calculável (sem potência) → contribui 0
                    registry(product("B", "1000", null), "2", 1, "8"),
                    // C: ativo 0.2 + standby 0.05 (calculável)
                    registry(product("C", "50", "5"), "4", 1, "10")));
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("3.282").compareTo(result.totalDailyKwh()),
                    "1.032 + 2.0 + 0.25 = 3.282 kWh/dia");
            assertEquals(0, new BigDecimal("1197.93").compareTo(result.totalAnnualKwh()),
                    "(1.032 + 2 + 0.25) × 365 = 1197.93 kWh/ano");
            // médias sobre os 3 válidos:
            assertEquals(0, new BigDecimal("1.094000").compareTo(result.avgDailyKwh()),
                    "3.282 / 3 = 1.094 kWh/dia");
            assertEquals(0, new BigDecimal("399.310000").compareTo(result.avgUseInYear()),
                    "1197.93 / 3 = 399.31 kWh/ano");
            // standby dedicado: só A e C são calculáveis (B excluído, NÃO conta 0):
            // (11.68 + 18.25) / 2 = 14.965
            assertEquals(0, new BigDecimal("14.965000").compareTo(
                    service.calculateStandbyConsumeAvg(user).orElseThrow()),
                    "média de standby ignora registros não calculáveis (não vira zero)");
        }
    }

    // =====================================================================
    // Standby inválido → registro excluído (não derruba os demais)
    // =====================================================================

    @Nested
    @DisplayName("Standby inválido: registro excluído dos agregados, nunca zero, nunca derruba os demais")
    class StandbyInvalido {

        @Test
        @DisplayName("hoursStandby = 25h (fora de [0,24]) → registro excluído; demais permanecem")
        void horasDeStandbyForaDoDomínio() {
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("OK", "100", "2"), "5", 1, "8"),       // 0.516 kWh/dia
                    registry(product("Ruim", "500", "5"), "3", 1, "25")));  // excluído
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("0.516").compareTo(result.totalDailyKwh()),
                    "só o registro válido entra no total (0.5 + 0.016)");
            assertEquals(0, new BigDecimal("188.34").compareTo(result.totalAnnualKwh()),
                    "0.516 × 365 = 188.34");
            assertEquals(2, result.productsList().size(),
                    "productsList traz todos os registros, inclusive o excluído dos agregados");
        }

        @Test
        @DisplayName("soma Hactive + Hstandby > 24 h/dia → registro excluído dos agregados")
        void somaDeHorasExcede24h() {
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("OK", "100", "2"), "5", 1, "8"),   // válido
                    registry(product("Inconsistente", "100", "2"),
                            "20", 1, "5")));                            // 20 + 5 = 25 h/dia → excluído
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("0.516").compareTo(result.totalDailyKwh()),
                    "registro com soma > 24h/dia fica fora; o válido permanece");
        }

        @Test
        @DisplayName("horasStandby negativas → registro excluído do agregado e dos rankings")
        void horasDeStandbyNegativas() {
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("OK", "100", "2"), "5", 1, "8"),
                    registry(product("Negativo", "900", "5"), "3", 1, "-4")));

            Optional<BigDecimal> avg = service.calculateAverageEnergyByUser(user);
            assertEquals(0, new BigDecimal("188.340000").compareTo(avg.orElseThrow()),
                    "só o registro válido na média anual (0.516 × 365 = 188.34)");
            assertEquals("OK", service.calculateMostConsumerProduct(user)
                    .orElseThrow().getName(),
                    "ranking também exclui o registro de standby inválido");
        }

        @Test
        @DisplayName("standby dedicado: registro inválido → vazio (não derruba o endpoint)")
        void standbyDedicadoIgnoraInvalidos() {
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("OK", "100", "2"), "5", 1, "8"),
                    registry(product("Ruim", "500", "5"), "3", 1, "25")));

            assertEquals(0, new BigDecimal("5.840000").compareTo(
                    service.calculateStandbyConsumeAvg(user).orElseThrow()),
                    "média anual só sobre os calculáveis (0.016 × 365 = 5.84)");
        }
    }

    // =====================================================================
    // Rankings — standby participa da comparação
    // =====================================================================

    @Nested
    @DisplayName("Rankings comemparam pelo consumo diário TOTAL (ativo + standby)")
    class RankingsComStandby {

        @Test
        @DisplayName("standby decide o vencedor: Y (0.9 + 0.2) vence X (1.0 + 0)")
        void standbyDecideRanking() {
            Product x = product("X", "1000", null);  // ativo 1.0, sem standby
            Product y = product("Y", "900", "200");  // ativo 0.9 + standby 0.2
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(x, "1", 1, null),    // total 1.0
                    registry(y, "1", 1, "1")));   // total 1.1 (0.9 + 0.2)

            assertEquals(y, service.calculateMostConsumerProduct(user).orElseThrow(),
                    "Y só vence se o standby entrar na comparação (1.1 > 1.0)");

            List<Product> ranked = service.calculateMostConsumerProductByCategory(
                    user, "electronics").orElseThrow();
            assertEquals(List.of(y, x), ranked, "ordem DESC pelo total diário");
        }
    }

    // =====================================================================
    // Standby por produto — busca e semântica de vazio
    // =====================================================================

    @Nested
    @DisplayName("calculateStandbyConsumesForProduct — vazio se não encontrado ou não calculável")
    class StandbyPorProduto {

        @Test
        @DisplayName("produto registrado com standby: retorna o anual; instância diferente com mesmo id também encontra")
        void encontraPorIdIndependenteDaInstancia() {
            Product tv = product("TV", "100", "2");
            when(registryRepository.findByUser(user))
                    .thenReturn(List.of(registry(tv, "5", 2, "8")));

            // instância DIFERENTE (como o controller carrega via repositório), mesmo id
            Product mesmaInstanciaOutroObjeto = new Product(tv.getId(), "TV", "Brand", "Model",
                    "electronics", "sub", new BigDecimal("100"), new BigDecimal("100"));
            // avgIdleEnergyForHour ausente nesta instância — a comparação é por id

            assertEquals(0, new BigDecimal("11.68").compareTo(service
                    .calculateStandbyConsumesForProduct(user, mesmaInstanciaOutroObjeto)
                    .orElseThrow()));
        }

        @Test
        @DisplayName("produto não registrado no usuário → vazio")
        void produtoNaoEncontrado() {
            when(registryRepository.findByUser(user))
                    .thenReturn(List.of(registry(product("TV", "100", "2"), "5", 2, "8")));

            assertTrue(service.calculateStandbyConsumesForProduct(user,
                    product("Desconhecido", "100", "2")).isEmpty());
        }
    }

    // =====================================================================
    // Sem duplicação — nem de q, nem do consumo ativo
    // =====================================================================

    @Nested
    @DisplayName("Sem duplicação: q e consumo ativo entram exatamente uma vez")
    class SemDuplicacao {

        @Test
        @DisplayName("totais não duplicam ativo nem q: 100W×5h×2 + 2W×8h×2 = 1.032 (não 2.064, não 1.5+)")
        void totaisSemDuplicacao() {
            when(registryRepository.findByUser(user)).thenReturn(List.of(
                    registry(product("TV", "100", "2"), "5", 2, "8")));
            stubReferenceTariff(TEST_TARIFF_PER_KWH);

            ResultDTO result = service.calculate(user).orElseThrow();

            assertEquals(0, new BigDecimal("1.032").compareTo(result.totalDailyKwh()),
                    "ativo 1.0 + standby 0.032, cada um aplicado UMA vez com q=2");
            // se o standby fosse somado duas vezes: 2.064; se q fosse re-aplicada
            // no standby: 0.144 → nenhuma dessas é o valor correto.
            assertTrue(result.totalDailyKwh().compareTo(new BigDecimal("2.064")) != 0,
                    "standby não é somado duas vezes");
            assertTrue(result.totalDailyKwh().compareTo(new BigDecimal("1.5")) != 0,
                    "q não é re-aplicada no standby");
        }
    }

    // =====================================================================
    // Helpers de construção
    // =====================================================================

    /** Simula a FONTE ÚNICA de tarifa com a tarifa informada em R$/kWh. */
    private void stubReferenceTariff(String tariffPerKwh) {
        when(tariffService.getReferenceTariff(any(LocalDate.class))).thenReturn(
                new TariffQuote(
                        new BigDecimal(tariffPerKwh),
                        "ENEL_SP",
                        "B1_RESIDENCIAL",
                        "CONVENCIONAL",
                        LocalDate.of(2026, 3, 15),
                        LocalDate.of(2027, 3, 14),
                        "https://www.enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html",
                        TariffQuote.ORIGIN_UNIT,
                        TariffQuote.Status.VALID));
    }

    /**
     * Monta um registro: potência ativa fixa no produto, potência de
     * standby informada (null = ausente) e horas de standby informadas
     * (null = ausente).
     */
    private static RegistryUserProduct registry(Product product, String activeHours,
            int quantity, String standbyHours) {
        BigDecimal hours = activeHours == null ? null : new BigDecimal(activeHours);
        BigDecimal standby = standbyHours == null ? null : new BigDecimal(standbyHours);
        return new RegistryUserProduct(new User(7), quantity, hours, standby, product);
    }

    private static Product product(String name, String activePower, String standbyPower) {
        Product product = new Product(UUID.randomUUID(), name, "Brand", "Model",
                "electronics", "sub", new BigDecimal(activePower), new BigDecimal("100"));
        product.setAvgIdleEnergyForHour(
                standbyPower == null ? null : new BigDecimal(standbyPower));
        return product;
    }
}
