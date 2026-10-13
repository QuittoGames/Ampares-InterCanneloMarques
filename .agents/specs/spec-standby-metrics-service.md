# SPEC — StandbyService + MetricsService (consumo em standby)

| Campo | Valor |
|---|---|
| **Título** | Serviço de consumo em standby + integração ao MetricsService (hub) |
| **Status** | `DRAFT` — aguarda decisões do DEV (ver §6 e §12) |
| **Data da spec (conteúdo DEV)** | 2026-10-13 |
| **Autor do conteúdo** | DEV (Quitto) — texto original preservado e marcado como **[DEV]** |
| **Persistência** | 2026-10-13, por `specification-engineer` (subagente) — somente organização, marcação de evidência e rastreabilidade; **nenhum requisito adicionado, removido ou decidido** |
| **Rastreabilidade** | `.agents/decisions/decision_001.json` (hub unificado), `decision_004.json` (contrato null/empty/throw; standby não calculável), `decision_005` (HourService — citada no javadoc), `.agents/specs/spec-registry-refactor-unified-consumption-engine.md` (§7 Standby), citações "SPEC §7/§8" nos javadocs do hub |
| **Complexidade** | STANDARD (serviço novo + integração no hub; sem decisão de persistência resolvida — ver §6) |

**Legenda de evidência usada em todo o documento:**

- **[DEV]** — requisito prescritivo vindo do texto original do DEV (autoridade do pedido).
- **FACT** — comportamento/contrato confirmado por leitura de código/arquivo (caminho:linha na §11).
- **INFERENCE** — conclusão derivada de evidências, não confirmada por declaração explícita.
- **PROPOSAL** — alternativa proposta, ainda não aprovada pelo DEV.
- **UNKNOWN** — informação sem confirmação / decisão pendente do DEV (nunca tratar como aceite).

---

## 1. Objetivo

**[DEV]** Implementar o serviço de consumo em standby e integrá-lo ao `MetricsService`, preservando o cálculo ativo, adicionando standby e garantindo que resultados diários/anuais/financeiros usem o consumo total correto.

**Contexto atual (FACT):** o hub `ConsumeMetricsService` já coordena o cálculo **ativo** sobre o motor `ConsumptionCalculator` ("zero fórmula duplicada no hub" — `ConsumeMetricsService.java:24-30`) e os dois métodos de standby da interface (`calculateStandbyConsumeAvg`, `calculateStandbyConsumesForProduct`) retornam `Optional.empty()` com javadoc "NÃO CALCULÁVEL enquanto não houver potência de standby confiável (SPEC §7 / decision_004)" (`ConsumeMetricsService.java:340-381`). O `StandbyMetricsService` existe como skeleton `@Service` **não totalmente vazio** (ver §11, F15). O motor de fórmulas **já possui** as fórmulas de standby (`standbyDailyKwh`, `standbyAnnualKwh`, `standbyAnnualCost` — `ConsumptionCalculator.java:294-347`).

---

## 2. Escopo / Não-escopo

### 2.1 No escopo

- **[DEV]** Serviço exclusivo do standby (novo `StandbyMetricsService`): receber dados, validar, calcular consumo diário agregado com quantidade, retornar com o tipo numérico do projeto (`BigDecimal`).
- **[DEV]** Integração no hub `MetricsService`/`ConsumeMetricsService` via pontes (§5): ativo existente → standby via serviço → somar por produto → agregar → derivar indicadores diários/anuais/financeiros.
- **[DEV]** Validações de entrada e domínio (§7).
- **[DEV]** Testes unitários do serviço + integração hub↔standby (§9).
- **[DEV, condicionado]** Se o modelo não tiver campo de potência de standby, identificar a **menor alteração necessária** (modelo/DTOs/persistência) — §5. **A escolha da fonte é OPEN QUESTION (§6/§12): nada é implementado de persistência sem decisão do DEV.**

### 2.2 Fora do escopo (não fazer)

- **[DEV]** Refatorar serviços não relacionados; executar apenas a alteração mínima necessária (§10/§13).
- **[DEV]** Alterar a fonte/contrato de tarifa (fonte única `TariffService` permanece; sem tarifa fixa — §2 do DEV, §3 abaixo).
- **[DEV]** Duplicar lógica ativa ou calcular tarifas no serviço de standby (§3).
- **FACT-derived:** novos endpoints/controllers não são pedidos; preservar assinaturas públicas da `MetricsService` e o contrato de resposta `ResultDTO` (**[DEV]** §3). Corrigir artefatos fora do escopo (ex.: `*DELETE FROM registry_user_product` em javadoc — F16, §11) não faz parte desta spec.

---

## 3. Regras de domínio e fórmulas

### 3.1 Fórmulas **[DEV]**

| # | Fórmula | Nota do DEV |
|---|---|---|
| F-A | `E_active = (P_active × H_active × q) / 1000` | **preservar** (cálculo ativo existente) |
| F-B | `E_standby = (P_standby × H_standby × q) / 1000` | nova |
| F-C | `E_total = E_active + E_standby` | componentes calculados **de forma independente e somados UMA vez** |
| F-D | `Consumo anual = E_total_diário × 365` | |
| F-E | `Custo diário = E_total_diário × tarifa` | |
| F-F | `Custo anual = E_total_anual × tarifa` | |

**[DEV]** Manter a tarifa existente (fonte única), não introduzir tarifa fixa, **não arredondar intermediários**.

**FACT — o motor já implementa exatamente estas fórmulas:**
`ConsumptionCalculator.dailyKwh` (`:117-124`), `annualKwh = dailyKwh × 365` (`:176-179`), `cost = kwh × T` com 2 casas HALF_UP (`:264-269`), `standbyDailyKwh` (`:294-304`), `standbyAnnualKwh` (`:320-324`), `standbyAnnualCost` (`:341-347`), `DAYS_PER_YEAR = 365` (`:65`), `MathContext.DECIMAL128` interno (`:74`). O hub já soma os componentes válidos **uma única vez** por registro e deriva anual/custos por registro (`ConsumeMetricsService.java:208-234`). **INFERENCE:** a integração de standby deve reutilizar o Formula Bank (regra vigente "zero fórmula duplicada no hub" + **[DEV]** Ponte A "não replica fórmula") — ou seja, `StandbyMetricsService` orquestra/valida e delega as fórmulas ao motor; o hub não ganha fórmula nova inline. **Verificação do exemplo do DEV (§8 desta spec):** `2 W × 8 h × 3 un / 1000 = 0,048 kWh/dia` ✔.

### 3.2 Regras de domínio já vigentes (FACT — a integração não pode violá-las)

- Nunca `null` → zero silencioso; não calculável → `Optional.empty()` (`ConsumptionCalculator.java:20-28, 296-298`; `HourService.java:27-35`).
- Potência ativa **nunca** é usada como standby (`ConsumeMetricsService.java:344-347, 366-368`; `ConsumptionCalculator.java:274-276`).
- Horas: `Hday = Hactive + Hstandby ≤ 24 h/dia`; componente `null` → não calculável; fora de [0,24] e soma > 24 → `InputValidationException`, sem clamp (`HourService.java:20-36, 60-75`).
- Registro ativo não computável é **excluído dos agregados** (nunca vira ZERO, nunca derruba os demais) (`ConsumeMetricsService.java:90-114`).
- Entrada `user` nula → `NullPointerException` com mensagem; listas nunca `null` (`decision_004`; `ConsumeMetricsService.java:32-40, 394-398`).
- `TariffUnavailableException` **propaga** (nunca inventar tarifa) (`ConsumeMetricsService.java:49-53, 228-230`).
- Contrato de resposta vigente: `ResultDTO` (médias escala 6 HALF_UP; totais precisão natural do motor; custos 2 casas) (`ResultDTO.java:13-29`; `ConsumeMetricsService.java:58-59, 208-234`). Métodos standby da interface retornam **valor ANUAL** (`MetricsService.java:22, 24`; `decision_004.consequences[2]`).

---

## 4. Responsabilidades dos serviços

### 4.1 StandbyMetricsService (serviço de standby) **[DEV]**

- Serviço **exclusivo do standby**: receber dados, validar, calcular o consumo diário agregado com quantidade, e retornar com o tipo numérico do projeto (`BigDecimal`).
- **Não** acessar web/banco/MetricsService sem necessidade arquitetural comprovada.
- **Não** duplicar lógica ativa nem calcular tarifas.
- Contrato conceitual **[DEV]**: `calculateDailyStandbyEnergy(powerW, standbyHoursPerDay, quantity)` — a assinatura definitiva respeita os tipos/domínio existentes do projeto.
  - **INFERENCE (não decisão):** o motor já expõe a primitiva correspondente `standbyDailyKwh(BigDecimal standbyPowerW, BigDecimal hoursStandby, BigDecimal quantity) → Optional<BigDecimal>` com `null` de potência → `Optional.empty()` (`ConsumptionCalculator.java:294-304`), que satisfaz o contrato conceitual; delegar a ela é o caminho consistente com a regra "zero fórmula duplicada" (F2/F4). A assinatura final do serviço é do implementador dentro dos tipos do projeto (`BigDecimal`, `Optional`), sem alterar contratos públicos vigentes.

### 4.2 ConsumeMetricsService (hub `MetricsService`) **[DEV]**

- Continua coordenando: cálculo ativo existente → obter standby via serviço → **somar por produto** → agregar → derivar indicadores diários/anuais/financeiros.
- **Preservar assinaturas públicas e contratos de resposta** (`MetricsService.java:12-29`; `ResultDTO.java:46-67`).
- **FACT:** a interface exige que os métodos públicos de standby (`calculateStandbyConsumeAvg`, `calculateStandbyConsumesForProduct`) retornem valor **ANUAL** (`MetricsService.java:22, 24`) — a derivação anual é `diário × 365` via motor (F-D).

### 4.3 Dependência **[DEV]**

- Dependência **unidirecional** `MetricsService → StandbyService`; **sem dependência circular**.
- **FACT (direção existente):** `ConsumeMetricsService` já depende só de `RegistryUserProductRepository`, `TariffService` e do motor static (`ConsumeMetricsService.java:61-68`); `ConsumptionCalculator` é classe final pura, sem estado/Spring (`ConsumptionCalculator.java:41-48, 60, 96-97`). `HourService` é `@Service` independente (`HourService.java:38-39`).

---

## 5. Pontes de integração (no hub)

**[DEV]** Nomes abaixo são adaptáveis aos padrões existentes do projeto — **tratar como PROPOSAL de nomenclatura** (o contrato conceitual é prescritivo; o nome final segue o padrão do hub):

- **Ponte A — `calculateStandbyEnergy(productUsage)`:** extrai potência/horas/quantidade do registro e encaminha ao serviço de standby (**não replica a fórmula**).
  - FACT de apoio: o padrão vigente de ponte é o helper que adapta `RegistryUserProduct` → fórmula static do motor (`calculateDailyKwh`, `ConsumeMetricsService.java:128-133`).
- **Ponte B — `calculateProductTotalEnergy(productUsage)`:** `E_total = ativo + standby` por registro.
  - FACT de apoio: o motor lança/retorna `Optional` conforme o caso; somar componentes calculados de forma independente **uma única vez** (**[DEV]** F-C). Sem potência de standby → componente standby não calculável → seguir a política de dados ausentes (§5.2/§7), nunca zero silencioso.
- **Ponte C — `calculateTotalConsumption(usages)`:** agrega os totais por registro **sem multiplicar a quantidade de novo** (a quantidade já entra dentro de cada `E` pela fórmula, `ConsumptionCalculator.java:122-123`).
- **[DEV]** Indicadores derivados (anual/financeiros) saem do **total** (F-D/E/F), com tarifa da fonte única.

---

## 6. Fonte da potência de standby — OPEN QUESTIONS (**não resolver nesta spec**)

**[DEV §5]** Verificar se o modelo tem campo; se não, identificar a menor alteração necessária (modelo/DTOs/persistência). Nunca usar potência nominal/ativa como standby. Nunca inventar valores.

### 6.1 O que o código mostra (FACT — conflito de fontes documentais)

| Fonte | Diz |
|---|---|
| `migrations/add_avg_idle_energy_for_hour.sql:4-22` | cria coluna **aditiva** `product.avg_idle_energy_for_hour NUMERIC` (potência de standby em W); alega que o Hibernate a aplica "a partir da entidade Models/Product.java" com `ddl-auto=update` |
| `Models/Product.java:12-29` | entidade tem **8 campos** e **NÃO possui** campo de standby (nem `avg_idle_energy_for_hour`, nem `standby_power_w`) |
| `application.properties:12` | `spring.jpa.hibernate.ddl-auto=update` (de fato) — **INFERENCE (F13):** sem campo mapeado na entidade, o Hibernate não cria/mapeia a coluna; um script SQL aditivo sozinho deixa o dado invisível ao backend Java |
| `migrations/005_canonical_product_contract.sql:13-16` | contrato canônico de `product` = **8 colunas**; `product.standby_power_w` e `is_generic` **DEPRECADOS**; "`standby_power_w` e `is_generic` vivem em `product_source_observation` — NÃO em product" |
| `migrations/create.sql:32-49` | espelha Product.java em 8 colunas; declara explicitamente que o diagrama **não tem mais** `avg_cosume`/`avg_idle_energy_for_hour` em `Product` (linha 38) |
| `migrations/create.sql:61-82` | `product_source_observation` carrega `standby_power_w` (`:71`) |
| `energy_collector/collector/database.py:67-88, 293` | coletor grava `standby_power_w` **APENAS em `product_source_observation`** (`_INSERT_PRODUCT_SQL` tem exatamente 8 colunas, sem standby) |
| `energy_collector/collector/sources/inmetro.py:315`, `wattsimple.py:295` | fontes retornam `standby_power_w=None` ("fonte nao declara standby") — **INFERENCE (F14):** mesmo com a fonte canônica escolhida, muitos produtos não terão potência de standby → estado não calculável será o caso comum |
| Backend Java (glob `src/main/java/**/*Observation*.java`) | **NÃO existe** entidade JPA para `product_source_observation` |
| Javadoc do hub + `decision_004` (`ConsumeMetricsService.java:342-344, 364-366`; `decision_004.decision[5]`) | citam `Product.avg_idle_energy_for_hour` como fonte futura da potência de standby |
| `.agents/specs/spec-registry-refactor-unified-consumption-engine.md:33, 170` | design alvo antigo: `Product` ganharia `avg_idle_energy_for_hour` proveniente do coletor |

**Ordem dos arquivos (timestamps informados pelo orquestrador; conteúdo verificado por leitura):** `add_avg_idle_energy_for_hour.sql` (13/10 11:19) → `005_canonical_product_contract.sql` (11:21) → `create.sql` (12:52) → `decision_004` (14:20). **A contradição entre elas é genuína e não é resolvida aqui.**

### 6.2 Questão central (UNKNOWN — decisão do DEV)

> **Onde vive `P_standby` canônico para o backend Java?**

Alternativas identificadas (nenhuma aprovada):

- **PROPOSAL A:** mapear `avg_idle_energy_for_hour` em `Product` (menor alteração no backend; alinhada ao javadoc do hub/`decision_004`; porém contradiz o contrato canônico de 8 colunas de `005`/`create.sql` e o coletor não popula essa coluna — dado ficaria vazio até existir ingestão).
- **PROPOSAL B:** consumir `product_source_observation.standby_power_w` (canônico para o coletor; porém exige nova entidade/repositório/consulta no backend — alteração maior — e a regra de qual observação prevalece por produto canônico não está definida no backend).
- **PROPOSAL C:** outra fonte/DTO específico — a definir pelo DEV.

### 6.3 Regras **[DEV]** independente da fonte escolhida

- **Nunca** usar potência nominal/ativa (`Product.avgPowerW`) como standby — FACT: já é regra vigente (`ConsumeMetricsService.java:344-347`; `ConsumptionCalculator.java:274-276`; `decision_004.decision[5]`).
- **Nunca** inventar valores.
- **H_standby > 0 com potência ausente → sinalizar cálculo não confiável**, usando o mecanismo já adotado pelo projeto (**[DEV]**): FACT — `Optional.empty()` para não calculável (`ConsumptionCalculator.java:296-298`); **nunca converter ausência em zero**.

---

## 7. Validações

**[DEV]** Regras mínimas pedidas (aplicadas no limite adequado — entrada + domínio do cálculo):

1. Quantidade > 0.
2. Potências e horas não negativas.
3. Horas ativas em [0, 24].
4. Horas standby em [0, 24].
5. Se períodos mutuamente exclusivos: `H_active + H_standby ≤ 24`.
6. `null`s conforme contrato dos DTOs — sem NPE/NaN/resultado silenciosamente errado.
7. **Nunca corrigir automaticamente registros inválidos — sinalizar.**

**FACT — mecanismo vigente que já atende/supera o piso acima** (a implementação deve reutilizá-lo, não recriá-lo):

- Motor: `requirePositivePower` (P **> 0**; P ≤ 0 → exceção), `requireHoursInRange` ([0,24]), `requireQuantity` (q ≥ 1), todos lançando `InputValidationException` com mensagem (`ConsumptionCalculator.java:486-522`); `standbyDailyKwh` com potência `null` → `Optional.empty()` e horas/quantidade validadas (`:294-304`).
- Horas: `HourService.totalDailyHours` valida componentes em [0,24] e soma ≤ 24, sem clamp (`HourService.java:60-75, 109-120`).
- Hub: registro que o motor rejeita é **excluído dos agregados** (sinalização por exclusão, nunca ZERO, nunca derruba os demais) (`ConsumeMetricsService.java:104-114`); entrada `user`/`product` nula → NPE explícita (`:195, 267, 300, 323, 356, 378-379`).
- Exceções de domínio existentes: `exceptions/InputValidationException.java`, `exceptions/InvalidRegistryException.java` (git status untracked; usadas por `HourService`/motor).

**NOTA (não é decisão):** para **potência standby = 0**, o motor vigente rejeita (exige P > 0 — `ConsumptionCalculator.java:490-492`), enquanto o piso **[DEV]** ("não negativas") aceitaria 0. Manter o comportamento vigente do motor (mais restritivo) é o padrão até o DEV decidir o contrário. **UNKNOWN (baixo impacto):** semântica de `hoursStandby = null` — ver §12, OQ-4.

---

## 8. Precisão numérica

**[DEV]** Usar o tipo decimal da convenção do projeto (**`BigDecimal`** em Java); a fórmula não deve ser alterada por arredondamentos prematuros. Exemplo **[DEV]**: `2 W × 8 h × 3 un → 0,048 kWh/dia`.

**FACT — convenções vigentes:** precisão interna `MathContext.DECIMAL128` (`ConsumptionCalculator.java:32-34, 74`); arredondamento monetário 2 casas HALF_UP **somente na saída** de custo (`:34-37, 264-269`); médias com escala 6 HALF_UP no hub (`ConsumeMetricsService.java:58-59`); totais sem arredondamento forçado (`:218-226`); `double`/`float` proibidos (`:39`). **INFERENCE:** standby entra nas mesmas cadeias de soma do total sem arredondamento intermediário próprio.

---

## 9. Estratégia de testes

**[DEV]** Testes **unitários do serviço de standby**:

- valores válidos;
- quantidade `q > 1` aplicada **exatamente uma vez**;
- `0 h` → `0`;
- potência fracionária;
- potência/horas negativas (rejeição);
- `q ≤ 0` (rejeição);
- obrigatórios ausentes (potência ausente → não calculável — mecanismo do projeto, nunca zero);
- precisão decimal.

**[DEV]** Testes de **integração MetricsService ↔ standby**:

- ativo sem standby;
- ativo + standby;
- agregação de diversos produtos;
- `q > 1`;
- produto sem potência de standby conhecida;
- rejeição de períodos incompatíveis (`H_active + H_standby > 24`);
- consistência diário/anual/custos (anuais e financeiros derivam do **total**);
- ausência de duplicação de ativo ou de quantidade.

**[DEV]** Usar os mocks/fixtures do projeto.

**FACT — convenção vigente de testes:** JUnit 5 com classes `@Nested` aninhadas e nomes/`@DisplayName` em português (`HourServiceTest.java:45-55`; seções em `ConsumptionCalculatorTest.java:34, 69, 110`); Mockito com `@ExtendWith(MockitoExtension.class)` e mocks de repositório/tarifa (`ConsumeMetricsServiceTest.java:39-49`); serviços concretos instanciados diretamente sem Spring (`HourServiceTest.java:22-24, 36-39`); fixture de tarifa `"1.06110"` (`ConsumeMetricsServiceTest.java:43`). **INFERENCE:** os testes novos seguem este padrão; os testes existentes do hub/motor são a régua de regressão (§10).

---

## 10. Critérios de aceitação

**[DEV]** — verificáveis na entrega:

1. O serviço calcula o standby (contrato conceitual `calculateDailyStandbyEnergy`).
2. O hub integra **sem duplicar fórmulas** (delegação ao motor; regra vigente).
3. Quantidade aplicada corretamente (exatamente uma vez por componente).
4. Cálculo **ativo continua funcionando** (regressão verde).
5. Total inclui standby quando dados disponíveis.
6. Anuais/financeiros derivam do **total** (ativo + standby).
7. Dados insuficientes/inválidos **não geram resultado enganoso** (não calculável sinalizado; nunca zero silencioso; nunca potência ativa como standby).
8. Testes novos + regressão passam.
9. Contratos de API compatíveis, salvo justificativa explícita (preservar assinaturas `MetricsService`/`ResultDTO`).

---

## 11. Evidências de código (FACT — caminho:linha)

> Caminhos relativos à raiz do projeto. Prefixo Java `src/main/java/cannelo/marques/interdisciplinar/interdisciplinar/` abreviado como `…`.

**Serviço/Hub/Motor/Horas**

- **F1** `…/Services/Metrics/ConsumeMetricsService.java:24-30` — hub implementa `MetricsService<User, BigDecimal>` sobre o motor; "zero fórmula duplicada no hub"; helpers adaptam `RegistryUserProduct` → fórmulas static.
- **F2** `…/Services/Metrics/ConsumeMetricsService.java:32-40` — convenções `decision_004`: nunca null; NPE em entrada nula; streams; sempre `BigDecimal` (double/float proibidos).
- **F3** `…/Services/Metrics/ConsumeMetricsService.java:42-53, 58-59` — unidades (diário kWh/dia, anual kWh/ano, custos R$/dia e R$/ano); "Standby é sempre valor ANUAL — não calculável enquanto não houver potência de standby confiável (SPEC §7)"; tarifa FONTE ÚNICA `TariffService`, `TariffUnavailableException` propaga; `DIVISION_SCALE = 6`.
- **F4** `…/Services/Metrics/ConsumeMetricsService.java:83-133` — `hasValidActiveInputs` / `hasComputableActiveInputs` (registro rejeitado é excluído, nunca ZERO) / `calculateDailyKwh` e `calculateAnnualKwh` delegam ao motor.
- **F5** `…/Services/Metrics/ConsumeMetricsService.java:193-246` — `calculate(User)`: filtra válidos; vazio → `Optional.empty()`; médias escala 6 HALF_UP; totais sem arredondamento; custos via `ConsumptionCalculator.cost`; monta `ResultDTO`.
- **F6** `…/Services/Metrics/ConsumeMetricsService.java:340-381` — `calculateStandbyConsumeAvg` e `calculateStandbyConsumesForProduct` retornam `Optional.empty()`; javadoc cita `Product.avg_idle_energy_for_hour`, "SPEC §7 / decision_004", proíbe usar `avgPowerW` como standby e proíbe ausência→zero.
- **F7** `…/Services/Metrics/ConsumptionCalculator.java:60-97, 117-124, 176-179, 264-269` — classe final pura; `dailyKwh = P×h×q/1000` validado; `annualKwh = daily×365`; `cost` 2 casas HALF_UP.
- **F8** `…/Services/Metrics/ConsumptionCalculator.java:294-347` — `standbyDailyKwh` (null → `Optional.empty()`; validações; fórmula), `standbyAnnualKwh` (×365), `standbyAnnualCost`.
- **F9** `…/Services/Metrics/ConsumptionCalculator.java:486-522` — `requirePositivePower` (P > 0) / `requireNonNegative` / `requireHoursInRange` ([0,24]) / `requireQuantity` (q ≥ 1) → `InputValidationException`.
- **F10** `…/Services/Metrics/HourService.java:20-36, 60-75, 96-120` — `Hday = Hactive + Hstandby ≤ 24` (DECISION 005); null → `Optional.empty()` (nunca zero); fora de domínio/soma > 24 → `InputValidationException`, sem clamp.
- **F11** `…/interfaces/MetricsService.java:12-29` — contrato público: `calculate`, `calculateAverageEnergyByUser`, `calculateMostConsumerProduct`, `calculateMostConsumerProductByCategory`, `calculateStandbyConsumeAvg` (:22, "Return in Year value"), `calculateStandbyConsumesForProduct` (:24, idem), `getProductsRegistrys`, `avg`.
- **F12** `…/DTO/ResultDTO.java:13-29, 46-67` — contrato de resposta: médias (escala 6), totais, custos 2 casas; 9 componentes.

**Modelos**

- **F13** `…/Models/Product.java:12-29` — entidade JPA com **8 campos** (`avg_power_w` :25-26, `annual_energy_kwh` :28-29); **sem campo de standby**.
- **F14** `…/Models/RegistryUserProduct.java:16-17, 30-36` — `quantity` int primitivo (:30); `avgActiveHours` BigDecimal nullable (:32-33); `hoursStandby` BigDecimal nullable (:35-36).
- **F15** `…/Services/Metrics/StandbyMetricsService.java:8-17` — skeleton `@Service` **não totalmente vazio**: construtor vazio + método **privado** `getStandyByHours(BigDecimal acitveHours)` (:14-17) que faz `acitveHours.subtract(new BigDecimal("24"))` — ou seja `H_active − 24`, **sinal invertido** em relação a "horas restantes do dia = 24 − H_active"; nomes com typos (`getStandyByHours`, `acitveHours`). Código parcial no escopo ativo do DEV — **destino a confirmar com o DEV** (ver §12, OQ-7).

**Migrations / banco / coletor**

- **F16** `migrations/add_avg_idle_energy_for_hour.sql:4-22` — coluna aditiva `product.avg_idle_energy_for_hour NUMERIC`; alega aplicação automática via Hibernate a partir de `Models/Product.java`.
- **F17** `migrations/005_canonical_product_contract.sql:13-16` — contrato canônico de `product` = 8 colunas; `product.standby_power_w`/`is_generic` **DEPRECADOS**; `standby_power_w` vive em `product_source_observation`.
- **F18** `migrations/create.sql:32-49, 61-82, 100-108` — `product` com 8 colunas (comentário :38 diz que o diagrama **não tem mais** `avg_idle_energy_for_hour` em `Product`); `product_source_observation` com `standby_power_w` (:71); `registry_user_product` com `hours_standby` NUMERIC anulável (:106).
- **F19** `energy_collector/collector/database.py:67-88, 293` — `_INSERT_PRODUCT_SQL` com exatamente 8 colunas (sem standby); `standby_power_w` gravado **apenas** em `product_source_observation`.
- **F20** `energy_collector/collector/sources/inmetro.py:315` e `…/sources/wattsimple.py:295` — fontes retornam `standby_power_w=None` ("fonte nao declara standby").
- **F21** `src/main/resources/application.properties:12` — `spring.jpa.hibernate.ddl-auto=update`. **INFERENCE (I1):** sem campo mapeado em `Product`, o Hibernate não cria/mapeia `avg_idle_energy_for_hour`; a migration sozinha não torna o dado visível ao backend.
- **F22** Glob `src/main/java/**/*Observation*.java` → vazio — backend **não possui** entidade JPA para `product_source_observation`.

**Decisões / specs persistidas / testes**

- **F23** `.agents/decisions/decision_001.json:7-17` — hub unificado no `ConsumeMetricsService`; `ConsumptionCalculator` sobrevive como camada primitiva delegada.
- **F24** `.agents/decisions/decision_004.json:7-16` — contrato null/empty/throw; item 5: standby não calculável (`Optional.empty`) enquanto `Product.avg_idle_energy_for_hour` não tiver dado confiável; nunca usar potência ativa; unidades: standby methods retornam valor ANUAL.
- **F25** `.agents/specs/spec-registry-refactor-unified-consumption-engine.md:84-86, 114, 168-172, 207, 218-219` — `hoursStandby` null permanece null (sem derivação `24 − ativo`); fórmula de standby com `P_standby null → NÃO CALCULÁVEL`; standby nunca usa potência ativa.
- **F26** `src/test/java/…/Services/Metrics/HourServiceTest.java:22-24, 36-47` e `…/Services/User/ConsumeMetricsServiceTest.java:39-49` — JUnit 5, `@Nested` + `@DisplayName` em português, Mockito, sem Spring context, fixture de tarifa `"1.06110"` (:43).
- **F27** `git status` (13/10/2026) — trabalho em andamento não commitado: `Services/Metrics/` (serviços, incluindo `StandbyMetricsService`), `ResultDTO.java`, migrations `005`/`006`/`add_avg_idle`, testes de Metrics — tudo untracked/modified. `.agents/` é untracked.

**Findings fora do escopo desta spec (registro, não correção):**

- **F28** `…/Services/Metrics/ConsumptionCalculator.java:312` — trecho `*DELETE FROM registry_user_product` solto **dentro do javadoc** de `standbyAnnualKwh` (colagem acidental aparente; inofensivo ao compilador, ruído perigoso). Não corrigir nesta spec (§2.2); reportar à entrega.
- **F29** Divergência interna de fase nos testes do coletor (`energy_collector/tests/test_normalization.py:197-198` menciona `rec.product.standby_power_w` enquanto `test_database.py:132` afirma `"standby_power_w" not in _INSERT_PRODUCT_SQL`) — indica fases históricas diferentes; sem efeito no backend Java. Registro apenas.

---

## 12. Questões abertas / UNKNOWN (decisão do DEV — nenhuma é resolvida nesta spec)

| # | Questão | Alternativas / estado atual | Impacto |
|---|---|---|---|
| **OQ-1** | **Fonte canônica de `P_standby`** para o backend: `product.avg_idle_energy_for_hour` (migration aditiva + javadoc do hub + `decision_004`) **ou** `product_source_observation.standby_power_w` (`005`/`create.sql`/coletor) **ou** outra? | PROPOSAL A / B / C na §6.2 | Define toda a §5 (menor alteração: modelo/DTO/persistência) |
| **OQ-2** | `Product.java` **não tem** o campo que javadoc/`decision_004`/migration citam (F13 vs F16/F24) — mapeamento JPA ausente. | Se OQ-1 = coluna aditiva → `Product` precisa ganhar o campo (decisão de modelo do DEV); caso contrário, não | Mudança de entidade/contrato |
| **OQ-3** | Backend **não tem** entidade JPA para `product_source_observation` (F22). | Se OQ-1 = observation → criar entidade/consulta (alteração maior + regra de seleção entre múltiplas observações por produto canônico não definida no backend) | Escopo/alcançabilidade do dado |
| **OQ-4** | **Semântica de `hoursStandby = null`**: ausência = zero hora **ou** desconhecido? **[DEV]**: "se ausência significar zero hora, tratar como zero; se significar desconhecido, preservar a distinção" — a definição é do DEV. | Estado vigente: null → **não calculável** (nunca zero) em `HourService` (F10) e o motor exige horas não nulas (F8/F9); a coluna é anulável (F14/F18) | Determina resultado quando `P_standby` existe e `H_standby` é null |
| **OQ-5** | Tratamento do registro standby **inviável/inconsistente** no agregado do hub (ex.: soma de horas > 24): excluir como o ativo faz hoje (F4) **ou** propagar `InputValidationException`? **[DEV §6]** diz apenas "sinalizar / nunca corrigir". | Mecanismo vigente do hub = exclusão sinalizada por exclusão (F4); `HourService` lança exceção no cálculo de horas (F10) | Comportamento dos endpoints agregados |
| **OQ-6** | Potência standby `= 0`: motor rejeita (P > 0, F9); piso **[DEV §7]** ("não negativas") aceitaria 0. | Manter motor (recomendável — padrão vigente) ou relaxar por decisão do DEV | Pequeno; afeta validação |
| **OQ-7** | Destino do método privado `getStandyByHours` no skeleton (F15): remove/substitui? (sinal aparentemente invertido; código parcial do DEV) | Confirmar com o DEV antes de tocar | Higiene do skeleton |
| **OQ-8** | Aceitação de produto: com inmetro/wattsimple sem standby (F20), muitos produtos ficarão **não calculáveis** mesmo com a fonte escolhida — `Optional.empty()` é o resultado esperado para esses casos? | Confirmar expectativa do DEV | UX/contrato dos endpoints standby |

> **Regra:** nenhum item acima pode ser fechado silenciosamente na implementação. Questões de fonte/persistência (OQ-1/2/3) são **DEV DECISION GATE** — se bloquearem o avanço, a entrega parcial documenta o bloqueio.

---

## 13. Relatório de entrega esperado do agente implementador

**[DEV]** A entrega deve conter, exatamente:

1. **Diagnóstico** da implementação anterior e dos pontos de integração (o que existia: hub `Optional.empty()` nos métodos standby — F6; skeleton F15; motor F8).
2. **Arquivos criados/modificados** (lista com caminhos).
3. **Assinaturas finais** dos métodos novos/alterados (respeitando tipos/domínio do projeto — **[DEV]** §3).
4. **Fórmulas e política de dados ausentes** implementadas (F-A…F-F; mecanismo `Optional.empty()`/exceção — §5.3/§7; semântica de null conforme resposta do DEV às OQ-4/5, se resolvidas).
5. **Testes executados e resultados** (comando, contagem de testes, exit status — evidência de execução real).
6. **Mudanças de modelo/API** (somente se OQ-1/2/3 foram decididas pelo DEV; nada de contrato público alterado sem justificativa — §10.9).
7. **Riscos/pendências** (incluindo OQs remanescentes e os findings F15/F28 se não tratados).

**[DEV]** Restrições de entrega: **não refatorar serviços não relacionados**; **alteração mínima necessária**; regressão do cálculo ativo verde; testes novos seguindo a convenção do projeto (§9/F26).

---

*Fim da spec. Status: DRAFT — OQ-1…OQ-8 pendentes de decisão do DEV antes de/durante a implementação.*
