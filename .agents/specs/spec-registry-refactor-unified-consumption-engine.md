# SPEC — Refatoração do registro de produtos e motor unificado de consumo energético

**Projeto:** Ampares-InterCanneloMarques (Spring Boot 4.1.1, Java 21, Maven `./mvnw`, JPA/Hibernate, PostgreSQL, `ddl-auto=update`, sem Flyway — schema canônico em `migrations/create.sql`)
**Pacote raiz:** `cannelo.marques.interdisciplinar.interdisciplinar`
**Status:** ACTIVE — implementação em andamento com múltiplas instâncias de code-implementer
**Baseline de testes:** `Tests run: 86, Failures: 0, Errors: 0, Skipped: 0 — BUILD SUCCESS` (executado 13/10/2026, ANTES dos moves do DEV)
**Diagrama de referência:** `docs/arquiteture.drawio` (páginas Database e Page-2)
**Decisões persistidas:** `.agents/decisions/decision_001.json`, `decision_002.json`, `decision_003.json`

---

## 0. Fonte de verdade e autoridade

| Fonte | Papel |
|---|---|
| Código real do repositório | FACT — verdade suprema |
| Este artefato | Contrato de implementação derivado do rascunho do DEV + codebase-explorer + decision records |
| `.agents/protocol/docs/codebase-explorer.json` | Cache de conhecimento da codebase (VALID no início da tarefa) |
| `docs/arquiteture.drawio` | Design do DEV (schema alvo e fluxo do hub) |
| Decision records 001–003 | DECISIONs aceitas pelo DEV |

**Delimitação de escopo (DECISION 002):** o DEV é dono do ecossistema Metrics — `interfaces/MetricsService.java`, `Services/MetricsService.java`, `Services/Metrics/ConsumeMetricsService.java`, `Services/Metrics/ConsumptionCalculator.java` (motor, mas em pasta do DEV — ver §4), `Controllers/MetricsController.java`, `DTO/ResultDTO.java`, `ConsumeMetricsServiceTest.java`, `UserService.java`, `pom.xml`, `application.properties`. Agentes não tocam esses arquivos sem delegação explícita.

---

## 1. Estado atual (FACT, com evidência)

### 1.1 Modelo de dados (migrations/create.sql:21-65 + entidades JPA)

- `users(id SERIAL PK, name VARCHAR(50))` — `User.java`, IDENTITY.
- `product(id UUID PK, name VARCHAR(150), brand, model, category, subcategory, avg_power_w NUMERIC, annual_energy_kwh NUMERIC)` — UUID `GenerationType.UUID`. **Sem** coluna de potência de standby.
- `registry_user_product(id UUID PK, user_id FK NOT NULL, product_id FK NOT NULL, quantity INT NOT NULL, avg_active_hours NUMERIC, hours_standby NUMERIC, UNIQUE(user_id, product_id))` — a UNIQUE existe no SQL mas **não** na entidade; é checada em código (`RegistryUserService`).
- **Design alvo (drawio, página Database):** `Product` deve ganhar `avg_idle_energy_for_hour NUMERIC` — potência de standby (W) proveniente de `data_raw_product` (coletor `energy_collector`, normalize). Anotação do DEV no diagrama: *"Avg Active Hours represent only estimative been got for user"*.

### 1.2 Fórmulas atuais (detalhe completo no cache codebase-explorer)

| Onde | Fórmula | Problema |
|---|---|---|
| ConsumptionCalculator | `kWh = P × horas × qtd / 1000` | null → ZERO silencioso; sem arredondamento explícito |
| ConsumptionCalculator / RegistryCalculator | `H/dia = (E×1000/P)/365` (scale 4) | fórmula DUPLICADA em 2 classes (≡ `computeEquivalentHoursYear/Day`) |
| RegistryCalculator ~147-162 | `standby = 24 − ativo` | derivação proibida: horas sem ativo ≠ standby |
| RegistryUserService ~63-93 | horas = input ?? RegistryCalculator ?? ConsumptionCalculator | cadeia redundante e confusa |
| ConsumeMetricsService | total/média/max por consumo ativo; standby médio e por produto | rótulos dizem "anual", fórmula retorna **diário** (nenhum ×365 no Java) |

- **Nenhuma tarifa existe em Java** (custo só no coletor Python, `config.py DEFAULT_TARIFF_PER_KWH=None`).
- Magic numbers: `1000`, `365`, `24`, scales 2/4.
- `RegistryUserProductDTO` tem comentário proibido: *"se null, o backend calcula via RegistryCalculator"*.
- Sem `@ControllerAdvice` — exceções viram 500.

### 1.3 Movimentação em andamento (git status, 13/10/2026 — mudanças do DEV)

- `Services/Consumption/ConsumptionCalculator.java` → movido para `Services/Metrics/ConsumptionCalculator.java`
- `Services/User/ConsumeMetricsService.java` → movido para `Services/Metrics/ConsumeMetricsService.java`
- `Models/interfaces/MetricsService.java` → movido para `interfaces/MetricsService.java` (**package declarado ainda é `Models.interfaces` — inconsistência transicional que quebra compilação até resolvida**)
- `Models/interfaces/HoursProvider.java` → removido
- Novos: `Services/MetricsService.java` (@Service hub esqueleto, injeta `ConsumptionCalculator`), `DTO/ResultDTO.java`
- Modificados pelo DEV: `MetricsController`, `RegistryUserService`, `UserService`, `OpenApiConfig`, `application.properties`, `pom.xml`, `docs/arquiteture.drawio`, `ConsumeMetricsServiceTest`

### 1.4 Contrato de API atual

- `POST /registryUserProducts` → DTO (`userId`, `productId`, `quantity @Min(1)`, `avgActiveHours @NotNull @Min(0)`, `hoursStandby?`) → 200 entity
- `GET /registryUserProducts/user/{id}` → List
- `POST /api/metrics/users/{total-energy|average-energy|most-consumer-product|standby-consumption-avg|standby-consumption-by-product}`
- `GET /api/metrics/search/{id}?search=`

---

## 2. Decisões arquiteturais aceitas (DECISION)

### D1 — Hub unificado de cálculos (decision_001)

A classe implementadora da interface `MetricsService` (`ConsumeMetricsService`, com o hub em construção em `Services/MetricsService.java`) é o **hub único de cálculo**: todas as fórmulas do §4 vivem lá via funções intermediárias (padrão DEV: `MetricsService.calculate → call → calculateAvgHour() → cálculo`), absorvendo as fórmulas de `ConsumptionCalculator` e `RegistryCalculator`. Acoplamento aceito conscientemente pelo DEV.

`ConsumptionCalculator` **sobrevive como camada primitiva de BigDecimal** que o hub injeta (esqueleto já criado pelo DEV). Trabalho dos agentes no motor é **aditivo-conservador**: nenhum método público existente é renomeado/removido (o hub pode já referenciá-los); métodos com semântica errada viram `@Deprecated` com javadoc.

### D2 — User sem coleção (decision_003)

`Models/User.java` **não recebe nenhum atributo novo** (sem `@OneToMany`). A lista de produtos registrados do usuário é entregue pelo hub: `MetricsService.getProductRegistry(Client user) → List<RegistryUserProduct>` (já existe na interface).

### D3 — Tarifa com defaults em código

`@ConfigurationProperties` com defaults em código + override opcional via properties — evita editar `application.properties` (arquivo sujo nas mãos do DEV).

### D4 — `hoursStandby` sem derivação automática

Proibido `hoursStandby = 24 − avgActiveHours`. `hoursStandby` null permanece null. Horas sem uso ativo não são presumidas como standby.

---

## 3. Invariantes do banco (SPEC §1 do rascunho)

`User (1:N) → RegistryUserProduct ← (N:1) Product` (N:N lógico).

- **User**: dono dos registros; PK existente; entidade enxuta (D2).
- **Product**: catálogo compartilhado; dados técnicos NUNCA alterados por cadastro individual de usuário; nunca copiar produto nem criar `Product` por usuário.
- **RegistryUserProduct**: estado de uso individual. `id` PK UUID própria (JPA), `user_id` FK, `product_id` FK, `quantity`, `avg_active_hours`, `hours_standby`.
- Preservar constraints, relacionamentos JPA e regra anti-duplicidade do par (user, product).
- Migrações somente aditivas; nada destrutivo sem backup, auditoria e plano de recuperação (critério de aceitação 10).

---

## 4. Motor de fórmulas — Formula Bank (autoridade)

Constantes nomeadas: `DAYS_PER_YEAR = 365`, `WATTS_PER_KILOWATT = 1000`. BigDecimal sempre; `double/float` proibidos. Precisão interna alta (`MathContext.DECIMAL128` ou scale ≥ 6); arredondamento monetário **`RoundingMode.HALF_UP`, 2 casas**, aplicado na saída monetária.

| # | Método | Fórmula | Unidade |
|---|---|---|---|
| 1 | `dailyKwh(P_w, h_d, q)` | `P_w × h_d × q / 1000` | kWh/dia |
| 2 | `monthlyKwh(daily, daysInPeriod)` | `daily × daysInPeriod` | kWh/mês |
| 3 | `averageMonthKwh(annual)` | `annual / 12` | kWh/mês (média — convenção documentada) |
| 4 | `annualKwh(daily)` | `daily × 365` | kWh/ano |
| 5 | `sourceAnnualKwh(productAnnual, q)` | `productAnnual × q`; `daily = /365`; `mês médio = /12` | consumo da FONTE (Product) — nunca misturar com o perfil |
| 6 | `cost(kwh, T)` | `kwh × T` | R$ |
| 7 | `standbyDailyKwh(P_standby, h_s, q)` | `P_standby × h_s × q / 1000`; anual `× 365`; custo `× T` | kWh/dia, kWh/ano, R$/ano. **P_standby null → estado NÃO CALCULÁVEL** (nunca null→0, nunca usar P ativo) |
| 8 | `inverseDailyHours(annual, P_w, q)` | `annual × 1000 / (P_w × q × 365)` | CONDICIONAL: exige `P_w > 0`, `q ≥ 1`; resultado fora de [0,24] → não calculável (**nunca clamar em 24**) |

**Validações obrigatórias** (métodos novos): `quantity ≥ 1`; horas ∈ [0,24] inclusivo; potência > 0 na inversa; nulls explícitos (exceção com mensagem clara). Null → ZERO silencioso é proibido nos métodos novos.

**Separação conceitual:** `Product.annualEnergyKwh` é referência da fonte; consumo personalizado deriva do perfil (`avg_active_hours`, `quantity`). Períodos diário/mensal/anual sempre explícitos; nunca somar kWh de períodos diferentes na mesma variável; nunca anualizar valor já anual.

**Convenção mensal:** quando o resultado for "mês médio", usar `annual/12` e rotular a convenção; quando for mês real, usar `daysInPeriod` do período. Não misturar dentro do mesmo resultado.

---

## 5. Tarifa — fonte única (SPEC §3)

| Campo | Valor |
|---|---|
| Distribuidora | `ENEL_SP` |
| Classe | `B1_RESIDENCIAL` |
| Modalidade | `CONVENCIONAL` |
| Valor publicado | `789.38` R$/MWh (TUSD 472,42 + TE 316,96) |
| Conversão | `÷ 1000` → `0.78938` R$/kWh |
| Vigência | `2026-07-04` a `2027-07-03` (limites inclusivos na validade) |
| Fonte oficial | https://www.enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html |

> **Revisão 13/10/2026 (decisão do DEV):** referência migrada de Enel Rio
> (`ENEL_RIO`, `1061.10` R$/MWh, vigência `2026-03-15` a `2027-03-14`) para
> Enel São Paulo (`ENEL_SP`, `789.38` R$/MWh — B1 residencial convencional da
> Resolução Homologatória ANEEL nº 3.596/2026, válida a partir de 04/07/2026).

Implementação: `config/TariffProperties` (@ConfigurationProperties prefix `ampares.energy.tariff`, defaults em código) + `config/TariffConfig` (@EnableConfigurationProperties) + `Services/Tariff/TariffService` + record `TariffQuote` (tariffPerKwh, distributor, class, modality, validFrom, validUntil, sourceUrl, originUnit, status `VALID|OUTDATED`).

Regras:
- Fora da vigência → status `OUTDATED` (sinaliza desatualização; nunca afirma ser a tarifa atual; nunca substitui por outra tarifa).
- Tarifa ausente/zerada → `TariffUnavailableException` (nunca null, nunca valor arbitrário).
- Segunda fonte, média nacional ou tarifa fictícia: PROIBIDAS.
- Resultado rotulado como **estimativa de energia pela tarifa de referência** — nunca como conta final da residência (tributos, bandeiras, disponibilidade exigem dados adicionais).

---

## 6. Conversor — `ProductForRegistryConverter` (SPEC §2 e §7)

**Entrada:** record `ProductForRegistry` — `Integer userId @NotNull`, `UUID productId @NotNull`, `int quantity @Min(1)`, `BigDecimal avgActiveHours @NotNull @Min(0) @Max(24)`, `BigDecimal hoursStandby @Min(0) @Max(24)` opcional.

**Migração de DTO:** `RegistryUserProductDTO` é @Deprecated (sem DTOs concorrentes); comentário "backend calcula via RegistryCalculator" removido.

**Processo (conversor = APENAS mapeamento; resolução/persistência = serviço):**
1. Serviço resolve `User` por `userId` (→ `UserNotFoundException`) e `Product` por `productId` (→ `ProductNotFoundException`).
2. Serviço valida referências e dados (`InvalidRegistryException` com mensagem explícita).
3. Conversor: `toEntity(ProductForRegistry, User, Product)` → `RegistryUserProduct` (quantity, avgActiveHours, hoursStandby null→null, associa instâncias).
4. PK sob responsabilidade do JPA; persistência na transação do serviço; retorna associação persistida.

**Critérios de conversão de teste:** quantity 0/negativa, avgActiveHours <0/>24, hoursStandby >24, usuário inexistente, produto inexistente, duplicado, **hoursStandby null NÃO vira 24−ativo**.

---

## 7. Standby (SPEC §5)

- Potência de standby real vem de `Product.avg_idle_energy_for_hour` (novo campo aditivo nullable, fonte: coletor `data_raw_product`).
- Sem potência de standby disponível → **estado não calculável**; nunca apresentar custo de standby como confiável; ausência de medição ≠ potência zero.
- Métricas de standby separadas do consumo ativo; agregadas somente com entradas disponíveis.

---

## 8. Métricas (hub — implementação delegada aos agentes sob demanda do DEV)

### 8.1 Contrato atual da interface (FACT — interfaces/MetricsService.java)

```java
Optional<ResultDTO> calculate(Client user);
Optional<BigDecimal> calculateAverageEnergyByUser(Client user);          // média anual por produto
Optional<Product> calculateMostConsumerProduct(Client user);
Optional<List<Product>> calculateMostConsumerProductByCategory(Client user, String category);
Optional<BigDecimal> calculateStandbyConsumeAvg(Client user);            // valor ANUAL
Optional<BigDecimal> calculateStandbyConsumesForProduct(Client user, Product product); // valor ANUAL
List<RegistryUserProduct> getProductsRegistrys(Client user);
Optional<BigDecimal> avg(OperationValue value, List<?> arry);
```

Repositório: `RegistryUserProductRepository.findByUser(User)`.

### 8.2 Regras de contrato (DECISION 004)

- **Nunca null.** Consulta (`getProductsRegistrys`) retorna `List` possivelmente vazia — ausência de registros é resultado válido, não erro.
- Cada cálculo decide o que lista vazia significa: `Optional.empty()` (sem registros ou sem entradas válidas) ou exceção de domínio quando a regra exigir ≥1 produto (`NoRegisteredProductsException`, mais clara que `IllegalStateException`).
- `Objects.requireNonNull(user, ...)` para entrada nula.

### 8.3 Diretrizes de implementação

- **`java.stream()`** preferido em agregações/filtros/ranking.
- **Funções `static`**: métodos de cálculo puro no `ConsumptionCalculator` são `static` (não dependem de estado); helpers privados do hub que só chamam o motor também podem ser `static`.
- Helpers do hub: `calculateDailyKwh(registration)` e `calculateAnnualKwh(registration)` delegando ao motor — **zero fórmula duplicada no hub**; `calculateDailyKwh` retorna kWh/dia, `calculateAnnualKwh` retorna kWh/ano (unidades explícitas nos nomes/javadocs).
- Filtro `hasValidActiveInputs(registration)`: registration, product, `avgPowerW` e `avgActiveHours` não nulos — registros sem entradas não contam como consumo válido.
- Média (`calculateAverageEnergyByUser`): média **por associação** (Σ consumo ÷ nº de registros válidos, scale ≥6, HALF_UP); média por unidade física é métrica DISTINTA (Σ E ÷ Σ q) — nunca tratar como equivalentes.
- Ranking (`calculateMostConsumerProduct`, `...ByCategory`): comparar pelo consumo diário incluindo quantidade; como todos os registros usam o mesmo período (365 dias), o ranking anual é idêntico ao diário. Categoria: `equalsIgnoreCase`, ordenado DESC, `Optional.empty()` quando sem match.
- **Standby**: métodos de standby NÃO usam a potência ativa; enquanto `Product.avg_idle_energy_for_hour` não tiver dado confiável, retornar `Optional.empty()` com javadoc de "não calculável" — nunca simular com `avgPowerW`.
- `avg(BigDecimal, List<?>)`: curinga `List<?>` não define quais valores somar — implementar filtrando elementos `Number`, ou substituir por método tipado se o DEV autorizar mudança de assinatura.
- Consumo anual do fabricante (`Product.annualEnergyKwh`) é referência da fonte: usar diretamente, **nunca** multiplicar por 365.
- Derivação física (referência didática): `P = ΔE/Δt ⟹ ΔE = P·Δt`; multiplicação por `q` soma unidades idênticas; `÷1000` converte Wh→kWh; `×365` acumula dias. Conversão universal: **1 MWh = 1000 kWh** (a tarifa Enel é publicada em R$/MWh e convertida ÷1000 para R$/kWh).

### 8.4 HoursService (DECISION 005)

`@HoursProvider` (anotação em getters) foi REMOVIDO — `interfaces/HoursProvider.java` deletado, anotações removidas de `RegistryUserProduct`. Substituído por:

- `interfaces/HoursService.java` — interface com funcs de cálculo de horas.
- Implementação `@Service` normal (`Services/Metrics/HoursServiceImpl.java`).
- **Fórmula:** `Hday = Hactive + Hstandby` (horas totais diárias).
- `hoursStandby` null → **não calculável** (`Optional.empty()`); null nunca vira zero (regra §7).
- Soma > 24h → inconsistência sinalizada explicitamente (nunca clamp silencioso).

---

## 9. Cenários de teste obrigatórios

### Cenário A — `P=100W, h_d=5, q=2`
- daily: `100×5×2/1000 = 1 kWh/dia` ✓ (CONFERE com rascunho)
- annual: `1 × 365 = 365 kWh/ano` ✓
- custo anual: `365 × 0,78938 = 288,12370 → R$ 288,12` (HALF_UP) ✓

### Cenário B — `P=1000W, h_d=2, q=2`
- daily: `1000×2×2/1000 = 4 kWh/dia` ✓
- annual: `4 × 365 = 1460 kWh/ano` ✓
- custo anual: `1460 × 0,78938 = 1152,49480 → **R$ 1152,49**`
- **OPEN QUESTION (OQ1, histórica):** o DEV escreveu `R$ 1550,41` no rascunho, contra a referência anterior (Enel Rio `1061,10` → calculado `1549,21`; o rascunho implicaria tarifa ≈ 1,06193 R$/kWh). Com a referência atual (Enel SP `0,78938` R$/kWh) a aritmética dá `1152,49`. Implementar conforme a fórmula a partir da fonte única; **não forçar o valor do rascunho**; confirmação do DEV permanece em aberto (OQ1).

### Cenário C — validações
Quantidade inválida; horas negativas ou >24; produto inexistente; usuário inexistente; potência ausente; potência negativa; tarifa desatualizada ou ausente; registro duplicado; divisão por zero; consumo anual de fonte sem anualização duplicada; ausência de potência de standby (não calculável); arredondamento financeiro HALF_UP. Testes verificam **unidades** dos retornos, não só igualdade numérica.

**Procedimento:** suíte existente executada antes (86 verdes) e depois; testes quebrados pela mudança de semântica são corrigidos/explicados, não contornados.

---

## 10. Critérios de aceitação

1. Request convertido consistentemente em `RegistryUserProduct`.
2. PK UUID e FKs preservadas.
3. `Product` global não alterado por registro individual.
4. Motor compartilhado: hub + `ConsumptionCalculator` primitivo, sem fórmulas duplicadas.
5. Períodos diário/mensal/anual explícitos.
6. Todos os custos vêm da configuração única da tarifa Enel.
7. Standby nunca usa potência ativa.
8. API com contrato documentado e testado.
9. Testes existentes + novos executados (resultado real reportado).
10. Nenhuma mudança destrutiva no banco sem backup/auditoria/plano de recuperação.

---

## 11. Entrega final (checklist)

Causas encontradas · arquivos criados/alterados · contrato do conversor (entrada/saída) · fórmulas e unidades · configuração da tarifa + fonte oficial · migrações · comandos executados e resultados reais dos testes · problemas remanescentes e limitações das fontes · instruções de execução/validação. Sem declaração de "corrigido" sem verificações executadas; sem commits/push sem autorização.

---

## 12. Open questions

| # | Questão | Status |
|---|---|---|
| OQ1 | Cenário B: rascunho 1550,41 (escrito contra Enel Rio 1061,10 — que daria 1549,21) vs fórmula. Com ENEL_SP vigente (789,38 R$/MWh → 0,78938 R$/kWh) a fórmula dá 1152,49; testes de regressão determinísticos fixam 288,12 (365 kWh) e 1152,49 (1460 kWh) | ✅ RESOLVIDA (fórmula mantida; rascunho não forçado) |
| OQ2 | `interface MetricsService` movida para `interfaces/` com package correto — compilação verde (186 testes) | ✅ RESOLVIDA |
| OQ3 | `RegistryCalculator` fica como deprecado ou é eliminado após absorção pelo hub | DEV (após hub pronto) |
| OQ4 | `ProductForRegistry` vs `RegistryUserProductDTO`: DTO antigo DELETADO; migração completa | ✅ RESOLVIDA |
| OQ5 | `User.java` sem coleção `@OneToMany` (decisão 003) — guard test incluso; `UserTest` cobre contrato enxuto | ✅ RESOLVIDA |
| OQ6 | `AVG_SCALE` renomeado para `DIVISION_SCALE` (escala de divisão, não só média) — valor 6 e HALF_UP preservados | ✅ RESOLVIDA |
