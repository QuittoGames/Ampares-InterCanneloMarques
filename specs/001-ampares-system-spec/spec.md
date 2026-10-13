# Feature Specification: Sistema Ampares — Catálogo Energético, Motor de Cálculo e Ingestão Multi-Fonte

**Feature Branch**: `001-ampares-system-spec` (diretório da spec; branch Git **não** criada nesta execução — há alterações locais não commitadas que precisam ser preservadas)

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "Especificação completa do sistema Ampares: objetivo e limites; arquitetura Java/Spring 4 + coletor Python; fluxo de dados fonte→produto canônico→registro do usuário→cálculo→tarifa→API; modelo relacional e contratos; catálogo de produtos e procedência das fontes; fórmulas com derivação e unidades; tarifa elétrica e vigência; qualidade, migrações e segurança; testes e plano de evolução. Não implementar código nesta etapa."

---

## Legendas de evidência (usadas em toda a spec)

Cada afirmação relevante usa um destes estados — nunca se apresenta inferência como fato:

| Estado | Significado |
|---|---|
| **[CÓDIGO]** | VERIFICADO NO CÓDIGO — confirmado por arquivo/símbolo (linha quando útil) nesta execução (13/10/2026, árvore de trabalho com alterações locais não commitadas sobre o commit `c70d48e` de 12/10/2026). |
| **[FONTE]** | VERIFICADO NA FONTE EXTERNA — URL, organização e data de consulta registradas (detalhes no [Apêndice C — Fontes](appendix-sources.md)). |
| **[DECISÃO]** | DECISÃO JÁ TOMADA — registrada em `.agents/decisions/decision_001..006.json` ou no briefing do DEV. |
| **[ALVO]** | ALVO PLANEJADO — comportamento desejado ainda não implementado/confirmado. |
| **[HIPÓTESE]** | Interpretação plausível que exige confirmação. |
| **[PENDÊNCIA]** | PENDÊNCIA DE DECISÃO — pode alterar arquitetura, valor calculado ou comportamento do usuário. |

**Contexto de execução importante**: o repositório contém **muitas alterações não commitadas** (`git status` de 13/10/2026), incluindo arquivos movidos/deletados e refatorações do coletor. A auditoria desta spec descreve o **estado da árvore de trabalho**, que é mais novo que o último commit e mais novo que partes do briefing original. Divergências entre o briefing e o código atual estão registradas no [Apêndice D](appendix-current-state-and-evolution.md). Durante a própria execução (15:57 de 13/10/2026), `User.java` foi editado — remoção de `@OneToMany`/campo, aplicando a DECISÃO 003 na entidade; as afirmações desta spec refletem o estado **pós-15:57** desse arquivo, com a divergência remanescente (métodos órfãos que quebram a compilação) registrada como D1.

## Resumo executivo

O **Ampares** é uma aplicação Java/Spring Boot (Web MVC + JPA + PostgreSQL) com coletor de dados Python que alimenta um catálogo canônico de produtos eletroeletrônicos. O usuário seleciona produtos do catálogo, registra quantidade e perfil de uso (horas ativas/standby por dia), e o sistema calcula consumo (kWh/dia, kWh/ano) e custo estimado (R$) usando uma tarifa de referência configurada, com procedência e rastreabilidade das fontes.

- **Linguagens/stack** [CÓDIGO]: Java 21, Spring Boot **4.1.1** (`pom.xml:8,30`), JPA/Hibernate, PostgreSQL + H2 (runtime), springdoc-openapi 3.1.1, Lombok; coletor Python 3.14+, psycopg 3 + pool, pytest (290 testes); frontend estático (`app.js`) sem framework.
- **Banco** [CÓDIGO]: PostgreSQL local `jdbc:postgresql://localhost:5432/neondb` (log de teste Maven, 13/10/2026); `application.properties` usa `ddl-auto=update` e importa `.env`. **Não existe `docker-compose.yml` no repositório** (busca exaustiva — [PENDÊNCIA] sobre o requisito "banco Docker" do briefing).
- **Testes na data da spec** [CÓDIGO]: Java **176 testes, 0 falhas — BUILD SUCCESS** (`./mvnw test`, 13/10/2026 ~15:51); Python **290 passed** (`pytest`, 13/10/2026). ⚠ O baseline Java **antecede** a edição de `User.java` às 15:57 (D1): a árvore atual **não compila** até a remoção dos métodos órfãos — re-executar a suíte após a correção (ver Apêndice D §D.1/D.4).
- **Tarifa** [FONTE]: Enel São Paulo, B1 residencial convencional — TUSD 472,42 + TE 316,96 = **789,38 R$/MWh**, Resolução Homologatória ANEEL nº 3.596/2026, válidas a partir de 04/07/2026 (página oficial Enel SP consultada em 13/10/2026; confere com `TariffProperties.java:53-77`).

### Objetivos

1. Definir o contrato canônico do `Product` e reconciliar Java ↔ Python ↔ migrações ↔ diagrama.
2. Especificar o motor de cálculo (Formula Bank em Java, `BigDecimal`) com unidades, derivação e casos-limite.
3. Especificar a tarifa de referência com fonte, vigência, componentes e limitações (OQ1).
4. Especificar a ingestão multi-fonte INSERT-only com procedência, precedência e idempotência.
5. Registrar estado atual vs. desejado, decisões, divergências e plano de fases A–G.

### Não objetivos (desta especificação)

- Não implementa código, migrações, configuração Docker nem importação de dados.
- Não redesenha autenticação (hoje login por ID com cookie — [CÓDIGO] `AuthService.java:39-61`; limitação conhecida, redesign é decisão futura do DEV).
- Não cobre o redesign do frontend (documentado em `docs/TODO.md`, fora de escopo).
- Não define estratégia de atualização dinâmica de tarifa (Fase D decide; hoje é validação temporal de valor configurado — [CÓDIGO] `TariffService`).

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Consultar catálogo canônico com procedência (Priority: P1)

Uma pessoa desenvolvedora/usuária abre o catálogo e encontra produtos com nome, marca, modelo, categoria, subcategoria, potência média (W) e energia anual (kWh/ano) consistentes entre a API, o banco e o diagrama. Cada valor tem origem conhecida (fonte, identificador externo, unidade e período), e valores de fontes genéricas/estrangeiras não aparecem como especificação brasileira verificada.

**Why this priority**: o catálogo é o insumo de todos os cálculos; contratos divergentes entre Java/Python/SQL corrompem tudo a jusante.

**Independent Test**: pode ser testado comparando `Product.java`, DDL Python, `migrations/create.sql` e `docs/arquiteture.drawio` campo a campo, e consultando `GET /products` com paginação/busca.

**Acceptance Scenarios**:

1. **Given** o schema aplicado (migrations 004/005/006 + `create.sql`), **When** o coletor grava um produto INMETRO, **Then** a tabela `product` recebe exatamente as 8 colunas canônicas e a proveniência (tensão, `standby_power_w`, `is_generic`, energia bruta) vai para `product_source_observation` — nunca para `product`.
2. **Given** um produto de fonte estrangeira (ENERGY STAR) e outro brasileiro (INMETRO) da mesma categoria, **When** a projeção canônica é gerada (`merge_products`), **Then** apenas membros de fonte primária brasileira não-genérica contribuem com métricas; a estrangeira permanece só como observação de origem.
3. **Given** busca por termo em `GET /products?search=`, **When** o termo casa nome/marca/modelo/categoria/subcategoria (case-insensitive), **Then** a lista correspondente é retornada sem expor entidades JPA com ciclos de serialização [ALVO — hoje retorna entidade, ver FR-026].

---

### User Story 2 - Registrar produto com perfil de uso e calcular consumo personalizado (Priority: P2)

O usuário faz login (ID), seleciona um produto do catálogo e registra: quantidade, horas ativas por dia e (opcionalmente) horas em standby por dia. O sistema persiste `RegistryUserProduct` e calcula consumo diário e anual personalizado (kWh) a partir da potência média do produto × horas × quantidade.

**Why this priority**: é o coração do produto — consumo personalizado distingue o Ampares de uma tabela estática.

**Independent Test**: `POST /registryUserProducts` + `POST /api/metrics/users/calculate` com os cenários A/B do Formula Bank (100W×5h×2 → 1 kWh/dia e 365 kWh/ano; 1000W×2h×2 → 4 kWh/dia e 1460 kWh/ano).

**Acceptance Scenarios**:

1. **Given** usuário e produto existentes, **When** um registro válido é enviado (quantity ≥ 1; avgActiveHours ∈ [0,24]; hoursStandby ∈ [0,24] opcional), **Then** o registro é persistido com FKs válidas e retornada a entidade criada.
2. **Given** o mesmo par (user, product), **When** um segundo registro é tentado, **Then** o fluxo falha com erro de duplicidade (`IllegalStateException` hoje [CÓDIGO] `RegistryUserService.java:85-92`; `UNIQUE(user_id, product_id)` no SQL [CÓDIGO] `create.sql:107`) [ALVO: resposta HTTP mapeada, ver FR-027].
3. **Given** um registro com horas impossíveis (ex.: 316,12 h/dia legadas), **When** qualquer agregado é calculado, **Then** o registro inconsistente é **excluído** dos agregados, nunca vira ZERO e nunca derruba os demais [DECISÃO 006]; `productsList` continua exibindo todos.
4. **Given** usuário sem registros válidos, **When** `calculate` é chamado, **Then** a resposta é 404 (Optional.empty → notFound) e nunca um resultado fabricado com zeros.

---

### User Story 3 - Custo estimado com tarifa de referência rastreável (Priority: P3)

O sistema converte a tarifa publicada (R$/MWh → R$/kWh), valida a vigência pela data de referência e aplica o custo sobre o consumo do mesmo período, retornando R$ com rastreabilidade (distribuidora, classe, modalidade, vigência, status, fonte).

**Why this priority**: dá significado financeiro ao consumo; erros de unidade/escala aqui afetam diretamente o valor apresentado (OQ1).

**Independent Test**: `TariffServiceTest` reproduz 1460 kWh × 0,78938 R$/kWh = 1152,49480 → R$ 1152,49 (HALF_UP); datas no início/fim/fora da vigência; tarifa nula/zerada → exceção.

**Acceptance Scenarios**:

1. **Given** tarifa configurada 789,38 R$/MWh com vigência 2026-07-04…2027-07-03, **When** consultada em 13/10/2026, **Then** retorna `VALID` com `tariffPerKwh = 0.78938` e metadados de origem.
2. **Given** data fora da janela (ou vigência ausente/incoerente), **When** consultada, **Then** status `OUTDATED` — nunca substituída por outra tarifa nem apresentada como atual.
3. **Given** tarifa nula/zero/negativa na configuração, **When** consultada, **Then** `TariffUnavailableException` é lançada — nunca tarifa alternativa inventada.

---

### User Story 4 - Agregações e ranking com denominadores claros (Priority: P4)

O usuário consulta total, média, produto mais consumidor e ranking por categoria. Totais/médias/máximos usam o mesmo período e denominadores explícitos (média por **registro** ≠ média por **unidade física**); empate e lista vazia têm comportamento definido.

**Why this priority**: métricas são a superfície principal da API; ambiguidade de denominador produce números enganosos.

**Independent Test**: `ConsumeMetricsServiceTest` (20 testes verdes) + cenários do [Apêndice B](appendix-formulas.md) §9.9.

**Acceptance Scenarios**:

1. **Given** 2 registros válidos (1 e 3 kWh/dia), **When** `calculateAverageEnergyByUser`, **Then** média **por associação** = 2 kWh/ano-escala (Σ anual ÷ nº de registros válidos, escala 6, HALF_UP) — não média por unidade física.
2. **Given** empate no máximo, **When** `calculateMostConsumerProduct`, **Then** comportamento de empate definido pelo `max` (primeiro na ordem de encontro — [CÓDIGO] `Comparator.comparing(...).max()`); teste documenta a escolha.
3. **Given** categoria sem match (ou nula/blank), **When** `calculateMostConsumerProductByCategory`, **Then** `Optional.empty()` → 404.

---

### User Story 5 - Standby correto ou explicitamente indisponível (Priority: P5)

Métricas de standby usam potência de standby **verificada**. Enquanto não houver fonte confiável, o estado é **indisponível** (`Optional.empty()`), nunca estimado com a potência ativa e nunca zero silencioso.

**Why this priority**: risco de erro conceitual alto (usar `avgPowerW` como standby superestima consumo ocioso); hoje o dado canônico não existe em `Product`.

**Independent Test**: `ConsumeMetricsServiceTest` valida `calculateStandbyConsumeAvg`/`ForProduct` → `Optional.empty()`; [Apêndice B](appendix-formulas.md) §9.6.

**Acceptance Scenarios**:

1. **Given** `Product` sem potência de standby canônica, **When** qualquer métrica de standby é consultada, **Then** resultado `Optional.empty()` (API hoje devolve `ZERO` — divergência registrada em FR-024 [PENDÊNCIA]).
2. **Given** uma fonte que declara potência de standby (ex.: dataset ENERGY STAR de TVs expõe `measured_standby_mode_power_w` [FONTE 13/10/2026]), **When** a observação é ingerida, **Then** o valor fica em `product_source_observation.standby_power_w` — disponível para decisão futura, sem vazar para o contrato canônico de 8 colunas sem decisão do DEV [PENDÊNCIA OQ2].

---

### User Story 6 - Ingestão segura INSERT-only (Priority: P6)

O coletor conecta ao PostgreSQL de produção por configuração de ambiente, verifica o schema (sem executar DDL) e grava apenas com `INSERT ... ON CONFLICT DO NOTHING` nas tabelas autorizadas, nunca tocando `users`/`registry_user_product`.

**Why this priority**: protege o dado do usuário e a integridade do catálogo; a política é a base da idempotência.

**Independent Test**: `tests/test_database.py` (coletor) — repetição não cria duplicatas; conflito não atualiza; `verify_schema` falha rápido sem as migrations.

**Acceptance Scenarios**:

1. **Given** banco com schema completo (004/005/006), **When** a mesma coleta é reexecutada, **Then** contagens `inserted`/`duplicates` são reportadas e nenhum registro existente é alterado ou apagado.
2. **Given** banco sem migrations, **When** o coletor inicia, **Then** `verify_schema` falha com mensagem clara apontando para `migrations/` — e nenhum DDL é executado.

### Edge Cases

- Horas ativas negativas ou > 24 → `InputValidationException` (motor) / `InvalidRegistryException` (registro); sem clamp silencioso [CÓDIGO] `ConsumptionCalculator.java:504-512`, `HourService.java:109-120`.
- `Hday = Hactive + Hstandby > 24` → inconsistência explícita [CÓDIGO] `HourService.java:70-73`.
- Potência ≤ 0 ou ausente → erro explícito no Formula Bank; registro excluído dos agregados [DECISÃO 006].
- Energia anual da fonte **nunca** é anualizada novamente (×365 proibido sobre dado já anual) [CÓDIGO] `ConsumptionCalculator` camada fonte; [DECISÃO 004].
- kWh/mês → kWh/ano só com ×12 quando a fonte declara período mensal (INMETRO/PBE) [CÓDIGO] `inmetro.py` (`_MONTHS_PER_YEAR`); unidades incompatíveis (VA, W) nunca viram kWh [CÓDIGO] `inmetro_xlsx.py` (coluna VA ignorada).
- Tensão: 110 V ≠ 127 V ≠ 220 V; bivolt e faixa preservados; ausente → `unknown`; nunca convertida nem inferida por país [CÓDIGO] `voltage.py:9-23`.
- Horas derivadas da inversa fora de [0,24] → não calculável, sem truncar em 24 [CÓDIGO] `ConsumptionCalculator.inverseDailyHours`.
- Tarifa: vigência com limites inclusivos; ausente/incoerente → `OUTDATED` [CÓDIGO] `TariffService.resolveStatus`.
- Duplicidade usuário-produto → bloqueada em SQL (UNIQUE) e em serviço [CÓDIGO].
- Divisões: denominador zero/ausente → não calculável (Python `safeDivide`→None; Java exceção/Optional), nunca NaN/∞.
- Fonte indisponível (ex.: WattSimple retornou HTTP 429 na verificação de 13/10/2026 [FONTE]) → erro isolado da fonte; dados já válidos não são apagados; testes seguem offline com fixtures.

## Requirements *(mandatory)*

### Requisitos funcionais

**Catálogo canônico e contratos**

- **FR-001**: O contrato canônico de `Product` DEVE ser exatamente: `id UUID` (determinístico uuid5 no coletor / `GenerationType.UUID` no JPA), `name VARCHAR(150)`, `brand`, `model`, `category`, `subcategory` (VARCHAR 255), `avg_power_w NUMERIC` (W) e `annual_energy_kwh NUMERIC` (kWh/ano). Java, DDL Python, `migrations/create.sql` e `docs/arquiteture.drawio` DEVAM concordar em nomes, unidades e semântica. [CÓDIGO: `Product.java:12-29`; `create.sql:40-49`; `database.py:70-75`; `models.py:65-113`] Divergência remanescente registrada no [Apêndice D](appendix-current-state-and-evolution.md) (migeração `add_avg_idle_energy_for_hour.sql` obsoleta).
- **FR-002**: Campos de proveniência de fonte (`standby_power_w`, `is_generic`, `voltage_raw/kind/min/max`, `raw_energy_value/unit`, `source`, `external_id`, `dataset_id`) DEVEM viver em `product_source_observation` e NUNCA no INSERT de `product`. [CÓDIGO: `create.sql:61-82`; `database.py:80-88`; `models.py:96-113`]
- **FR-003**: Cada valor canônico DEVE ter procedência conhecida: fonte, identificador externo, unidade e período. Dados genéricos (`is_generic`) e estrangeiros NÃO DEVEM ser apresentados como especificação brasileira verificada. [CÓDIGO: `precedence.py`; `data-sources.md`]
- **FR-004**: A projeção canônica por `category|subcategory` DEVE ser média aritmética **apenas** de membros de fonte primária brasileira não-genérica; sem membros elegíveis → métrica `NULL` (indisponível), nunca fabricada. [CÓDIGO: `models.py:306-371`; `precedence.py:78-88`]
- **FR-005**: A pesquisa de catálogo (`GET /products?search=`) DEVE cobrir nome, marca, modelo, categoria e subcategoria, case-insensitive. [CÓDIGO: `ProductRepository.searchByTerm`]

**Normalização e ingestão**

- **FR-006**: Normalização DEVE converter somente com unidade/período conhecidos: kWh/mês→kWh/ano ×12 exatamente uma vez (INMETRO); nunca anualizar dado já anual; ausência permanece `NULL` (nunca zero); negativo/NaN/∞ → `NULL`. [CÓDIGO: `inmetro.py`; `normalization.py:158-194`]
- **FR-007**: Tensão DEVE ser preservada como proveniência verbatim + classificação `unknown|monovolt|bivolt|range` + min/max em V; NUNCA convertida (220→127 proibido) nem inferida por país/estado/categoria. [CÓDIGO: `voltage.py`; `normalization.py:319-336`]
- **FR-008**: O coletor DEVE conectar-se ao PostgreSQL configurado por ambiente (`.env` do projeto pai; precedência `DB_URL` → `DATABASE_URL` → chaves discretas) e NÃO DEVE manter banco próprio. [CÓDIGO: `config.py:189-265`] [PENDÊNCIA: nomes de chaves do `.env` atual (`DB_USER`, `DB_PASSWORD`) não atendem o contrato do coletor (`DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `DATABASE`) — ver Apêndice D]
- **FR-009**: O coletor NÃO DEVE executar DDL em runtime: `verify_schema` apenas lê `information_schema` e falha rápido se faltar tabela obrigatória (`product`, `product_source_observation`, `energy_label_class`, `aggregate_reference`). [CÓDIGO: `database.py:139-169` — divergência histórica do briefing já resolvida na árvore de trabalho]
- **FR-010**: Toda escrita do coletor DEVE ser `INSERT ... ON CONFLICT DO NOTHING` (produto por `id`; observação por `(source, external_id)`; rótulo/agregado por `id`), idempotente, sem UPDATE/DELETE, sem tocar `users` e `registry_user_product`. [CÓDIGO: `database.py:48-103`; docstrings] [PENDÊNCIA OQ3 sobre atualização de catálogo]
- **FR-011**: IDs determinísticos (uuid5 com canonicalização NFKC+casefold+whitespace) DEVEM ser preservados — mesma chave → mesmo UUID entre execuções; ENERGY STAR mantém UUIDs bit a bit. [CÓDIGO: `models.py:43-140`]
- **FR-012**: Falha de uma fonte NÃO DEVE apagar dados já válidos; lotes ordenados por UUID (anti-deadlock) com transação curta por lote. [CÓDIGO: `database.py:187-231`]

**Motor de cálculo**

- **FR-013**: O hub `ConsumeMetricsService` (implementação de `MetricsService`) DEVE ser o único agregador de fórmulas; `ConsumptionCalculator` é a camada primitiva estática; `RegistryCalculator` está `@Deprecated` para absorção. [CÓDIGO: `ConsumeMetricsService.java`; DECISÃO 001]
- **FR-014**: Fórmulas (unidades obrigatórias — catálogo completo com derivação no [Apêndice B](appendix-formulas.md)):
  - `dailyKwh = P(W) × h(dia) × q / 1000` → kWh/dia;
  - `annualKwh = dailyKwh × 365` → kWh/ano (ano de 365 dias, convenção explícita);
  - `averageMonthKwh = annualKwh / 12` (mês médio rotulado);
  - fonte: `sourceAnnualKwh = productAnnualKwh × q` (NUNCA ×365 sobre valor já anual);
  - `cost = kwh × T(R$/kWh)` → R$;
  - standby: `P_standby × h_standby × q / 1000` (P_standby `null` → não calculável);
  - inversa: `H/dia = E_ano × 1000 / (P × q × 365)`, fora de [0,24] → não calculável.
  [CÓDIGO: `ConsumptionCalculator.java:62-389`]
- **FR-015**: Validações do motor: potência > 0; horas ∈ [0,24] inclusivo; quantidade ≥ 1; `null` → exceção de domínio (nunca ZERO silencioso nos métodos novos). Métodos legados com `null`→ZERO permanecem marcados como LEGADO até absorção. [CÓDIGO: `ConsumptionCalculator.java:486-522`; DECISÃO 004]
- **FR-016**: Horas: `Hday = Hactive + Hstandby` via `HourService`; componente `null` → `Optional.empty()`; soma > 24 → `InputValidationException`. [CÓDIGO: `HourService.java:60-101`; DECISÃO 005]
- **FR-017**: Agregados excluem registros não-computáveis (`hasComputableActiveInputs`), nunca os contam como ZERO; sem válidos → `Optional.empty()`. `productsList` mantém todos os registros para exibição. [CÓDIGO: `ConsumeMetricsService.java:83-114,194-246`; DECISÃO 006]
- **FR-018**: Média por associação (Σ E ÷ nº de registros válidos, escala 6, HALF_UP) é métrica DISTINTA de média por unidade física (Σ E ÷ Σ q); nomes de métrica DEVEM explicitar o denominador. [CÓDIGO: `ConsumeMetricsService.java:59,208-216`; Apêndice B §9.9]
- **FR-019**: Ranking usa máximo linear (`max(Comparator.comparing(...))`); por categoria: filtro `equalsIgnoreCase` + ordenação DESC; `Optional.empty()` sem match. [CÓDIGO: `ConsumeMetricsService.java:299-337`]
- **FR-020**: Toda aritmética de domínio DEVE usar `BigDecimal` (Java) / `Decimal` (Python); `double/float` proibidos em cálculo de tarifa/dinheiro; precisão interna DECIMAL128; arredondamento monetário HALF_UP 2 casas somente na saída. [CÓDIGO: `ConsumptionCalculator.java:73-77`; `TariffService.java:37`] [Observação registrada: coerção Python `_to_decimal` passa por `float` intermediário — limitação conhecida de precisão para valores extremos, aceitável para dado de fonte, ver Apêndice D]

**Tarifa**

- **FR-021**: Fonte única de tarifa (`TariffProperties` prefixo `ampares.energy.tariff`, defaults em código): `ENEL_SP`, `B1_RESIDENCIAL`, `CONVENCIONAL`, `publishedValuePerMwh = 789.38` (TUSD 472,42 + TE 316,96 — Resolução Homologatória ANEEL nº 3.596/2026, vigentes a partir de 04/07/2026 [FONTE 13/10/2026]), conversão ÷1000 → R$/kWh. Segunda fonte, média nacional ou valor alternativo: PROIBIDOS. [CÓDIGO: `TariffProperties.java:53-77`; DECISÃO D3]
- **FR-022**: Vigência inclusiva `validFrom ≤ date ≤ validUntil` → `VALID`; fora da janela ou limites ausentes/incoerentes → `OUTDATED` (nunca afirma ser a tarifa atual, nunca substitui). `validUntil = 2027-07-03` é **hipótese de código** (projeção do ciclo anual de reajuste ~jun/jul — a página publicada não declara fim de vigência). [CÓDIGO: `TariffService.java:86-99`; HIPÓTESE em `TariffProperties.java:69-74`]
- **FR-023**: Tarifa ausente/nula/zerada/negativa → `TariffUnavailableException` (nunca `null`, nunca tarifa inventada). `TariffUnavailableException` PROPAGA pelo hub (cálculo sem tarifa não é produzido). [CÓDIGO: `TariffService.java:55-66`; `ConsumeMetricsService.java:228-234`]
- **FR-024** [PENDÊNCIA OQ1]: O resultado do cenário B é **R$ 1152,49** (1460 kWh × 0,78938 = 1152,49480 → HALF_UP), reproduzido em `TariffServiceTest:116-132` e `ConsumptionCalculatorTest:101-111`. O rascunho histórico (R$ 1550,41) foi escrito contra a tarifa antiga da Enel Rio (1061,10 R$/MWh ⇒ ≈1549,21). A matemática não deve ser alterada para igualar o rascunho; a confirmação formal do DEV sobre 1152,49 como resultado canônico permanece em aberto. [CÓDIGO + `.agents/specs/spec-registry-refactor-unified-consumption-engine.md:234-235`]

**API, DTOs e erros**

- **FR-025**: Endpoints reais (contrato atual [CÓDIGO]): `POST /auth/login` · `POST /auth/logout` · `GET /products` · `POST /registryUserProducts` · `GET /registryUserProducts/user/{userId}` · `POST /api/metrics/users/calculate` · `POST /api/metrics/users/average-energy` · `POST /api/metrics/users/most-consumer-product` · `POST /api/metrics/users/standby-consumption-avg` · `POST /api/metrics/users/standby-consumption-by-product` · `GET /api/metrics/search/{userId}?search=`.
- **FR-026** [ALVO]: Contratos HTTP NÃO DEVEM expor entidades JPA diretamente nem serializar ciclos. Hoje `MetricsController` retorna `Product` (l.81-89), `RegistryUserProductController` retorna `RegistryUserProduct`/lista (l.75-92) e `ResultDTO` contém `List<RegistryUserProduct>` (l.66). O `@OneToMany` de `User` foi **removido em 13/10/2026 15:57** (DECISÃO 003 aplicada na entidade), o que elimina o ciclo User→registros na navegação JPA — porém os métodos auxiliares órfãos (`set/add/removeRegistryUserProduct`, l.45-92) referenciam o campo e o import removidos e **quebram a compilação** (D1); e entidades continuam expostas dentro de DTOs (`RegistryUserProduct.user` via `@ManyToOne` ainda serializa `User` aninhado), portanto o DTO de resposta explícito permanece o estado alvo. [CÓDIGO: `MetricsController.java`; `RegistryUserProductController.java`; `ResultDTO.java:66`; `User.java` pós-15:57; git diff]
- **FR-027** [ALVO]: Erros de domínio DEVAM ter mapeamento HTTP explícito via `@ControllerAdvice` (hoje inexistente — exceções viram 500 genérico [CÓDIGO: grep sem match; TODO.md TASK-019/026]). Status propostos: 400 validação (`InvalidRegistryException`, `InputValidationException`), 404 não encontrado (`UserNotFoundException`, `ProductNotFoundException`), 409 duplicidade (`IllegalStateException` do par user-product), 503/502 tarifa indisponível (`TariffUnavailableException`) [PROPOSAL — decisão final do DEV].
- **FR-028** [PENDÊNCIA]: Semântica de vazio nos endpoints de standby e média: o serviço retorna `Optional.empty()` (não calculável) [DECISÃO 004], mas os controllers convertem para `BigDecimal.ZERO` (`result.orElse(BigDecimal.ZERO)`) [CÓDIGO: `MetricsController.java:73,101,116`] — o cliente não distingue "zero real" de "indisponível". Estado alvo a decidir pelo DEV: manter ZERO no contrato HTTP, retornar 404/204, ou campo com flag de disponibilidade. [CÓDIGO: divergência registrada no Apêndice D §D.3]
- **FR-029**: `ProductForRegistry` (contrato de entrada de registro): `Integer userId @NotNull`, `UUID productId @NotNull`, `int quantity @Min(1)`, `BigDecimal avgActiveHours @NotNull @Min(0) @Max(24)`, `BigDecimal hoursStandby @Min(0) @Max(24)` opcional. O backend NUNCA deriva horas (nem `24 − ativo`); `hoursStandby` ausente permanece `null` persistido. [CÓDIGO: `ProductForRegistry.java:24-46`; `RegistryUserService.java:105-127`; `ProductForRegistryConverter.java:42-56`]
- **FR-030**: Fluxo de registro DEVE resolver `User` e `Product` por id (404 se ausentes), validar faixas, bloquear duplicidade do par e persistir via conversor puro. [CÓDIGO: `RegistryUserService.java:64-97`]

**Fluxo de usuário/autenticação (estado atual documentado)**

- **FR-031**: Login por ID numérico: usuário inexistente é criado com o MESMO id (SQL nativo `INSERT ... ON CONFLICT (id) DO NOTHING` — necessário porque `GenerationType.IDENTITY` omite o id no INSERT); cookie `user_id` HttpOnly com TTL de 7 dias. [CÓDIGO: `UserService.java:132-140`; `AuthService.java:39-61`; `AuthController.java:40-46`] Limitação de segurança conhecida (sem senha/verificação de posse) — redesign é decisão do DEV, fora do escopo desta spec.

**Qualidade, segurança e operação**

- **FR-032**: Credenciais NUNCA aparecem em logs/`repr`/documentação (senha com `field(repr=False)` [CÓDIGO: `config.py:140`]); esta spec registra apenas **nomes** de variáveis de ambiente, nunca valores.
- **FR-033**: Testes de adapters DEVEM ser determinísticos e offline (fixtures injetadas); nenhum teste depende de rede. [CÓDIGO: `energy_collector/tests/*` — 290 testes passam em 1,35 s sem rede]
- **FR-034**: Cálculo de domínio NÃO deve migrar para SQL (o banco persiste dado normalizado e perfil de uso; Java calcula métricas) [DECISÃO + briefing]; paralelismo só após benchmark, sem carregar entidades JPA gerenciadas entre threads [CÓDIGO: docstring `ConsumeMetricsService`; briefing §12].
- **FR-035**: Migrações são a única forma de criar/evoluir schema de ingestão; devem ser aditivas, idempotentes, com rollback documentado. Hibernate `ddl-auto=update` permanece como conveniência de desenvolvimento e é reconhecido como **segunda fonte de schema** a reconciliar (Fase A/G). [CÓDIGO: `application.properties`; `005/006` rollback em comentários]
- **FR-036**: Após estabilizar o código, o cache `.agents/protocol/docs/codebase-explorer.json` DEVE ser atualizado pelo mecanismo do projeto (`persist_artifact.py`, se confirmado) — hoje aponta o commit `c70d48e` e está **stale** em relação à árvore de trabalho. [CÓDIGO: metadados do JSON]

### Key Entities *(include if feature involves data)*

- **User**: consumidor final; `id` inteiro `SERIAL`/IDENTITY, `name` nullable. Sem coleção de registros (DECISÃO 003) — `@OneToMany`/campo **removidos** em 13/10/2026 15:57; métodos auxiliares órfãos restantes quebram a compilação (D1, Apêndice D §D.1).
- **Product**: catálogo canônico compartilhado; 8 campos (FR-001); identidade determinística; NUNCA alterado por cadastro individual.
- **RegistryUserProduct**: associação N:N resolvida; `id UUID`, FKs `user_id`/`product_id` NOT NULL, `quantity`, `avg_active_hours` (h/dia, estimativa do usuário), `hours_standby` (h/dia, opcional); `UNIQUE(user_id, product_id)` no SQL.
- **ProductSourceObservation**: modelo específico observado numa fonte; proveniência completa (standby, tensão, energia bruta, `is_generic`); `UNIQUE(source, external_id)`.
- **EnergyLabelClass**: classe ENCE (A+++…G) por produto (INMETRO/PBE).
- **AggregateReference**: estatística anônima por fonte/país/ano/métrica (IEA) — nunca produto.
- **TariffQuote**: cotação imutável de tarifa de referência (R$/kWh + metadados + status).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Convergência de contratos — `Product.java`, DDL Python, `create.sql` e diagrama concordam nos 8 campos canônicos; auditoria campo a campo sem divergência não resolvida/pendência não registrada.
- **SC-002**: Procedência 100% — cada valor persistido tem fonte + id externo + unidade + período (observação), e nenhum dado genérico/estrangeiro aparece como especificação brasileira.
- **SC-003**: Idempotência — reexecução integral do coletor produz 0 novas inserções e 0 alterações (apenas duplicatas contabilizadas); nenhum UPDATE/DELETE/DDL executado.
- **SC-004**: Correção dimensional — todos os cenários do Apêndice B passam (ex.: 200W×5h×2 = 2 kWh/dia = 730 kWh/ano; 1000W×2h×2 = 4 kWh/dia = 1460 kWh/ano; custo 1460×0,78938 = R$ 1152,49), com unidades verificadas nos testes.
- **SC-005**: Sem anualização dupla — nenhum teste/fluxo multiplica ×365 valor já anual (`sourceAnnualKwh` cobre o caminho da fonte).
- **SC-006**: Precisão — `BigDecimal` em toda a cadeia Java; custos com 2 casas HALF_UP apenas na saída; nenhum `double/float` em tarifa.
- **SC-007**: Standby — métricas de standby retornam indisponível (`Optional.empty()`) enquanto não houver potência de standby verificada; nenhum caminho usa `avgPowerW` como standby (verificado por teste).
- **SC-008**: Tarifa rastreável — cada custo carrega distribuidora/classe/modalidade/vigência/status/fonte; tarifas `OUTDATED` nunca aparecem como vigentes.
- **SC-009**: API íntegra — DTOs sem ciclos de serialização de entidades; retorno sem dados é explícito (contrato vazio definido por endpoint); erros mapeados por `@ControllerAdvice` [ALVO].
- **SC-010**: Agregações corretas — total/média/máximo no mesmo período; média por registro ≠ média por unidade; empate e lista vazia com comportamento testado.
- **SC-011**: OQ1 reproduzível — entradas (1460 kWh; 789,38 R$/MWh; vigência; HALF_UP) documentadas e teste verde; divergência do rascunho explicada por migração de fonte tarifária.
- **SC-012**: Suítes verdes — `./mvnw test` e `pytest` executados com resultado real registrado após cada fase (baseline desta spec: 176 + 290 testes, 13/10/2026).

## Assumptions

- **Ano comercial de 365 dias** e mês médio = ano/12: convenções explícitas do domínio (não bissexto, não ponderado por mês real) [CÓDIGO: `ConsumptionCalculator.java:64-68`].
- **`avgActiveHours` é estimativa declarada pelo usuário** — o backend nunca deriva; anotação do DEV no diagrama. [CÓDIGO: `drawio`; `ProductForRegistry`]
- **Tarifa de referência ≠ conta real**: o custo apresentado é estimativa de energia (TUSD+TE) sem ICMS/PIS/COFINS/bandeiras/iluminação pública/valores mínimos — rotulado como estimativa, nunca como fatura. [FONTE Enel SP 13/10/2026 — a página lista bandeiras e serviços separadamente]
- **`validUntil` da tarifa (2027-07-03)** é projeção do ciclo anual de reajuste (histórico da página: resoluções sempre fim de junho/início de julho); a fonte não publica data fim. [HIPÓTESE]
- **Fontes são consultadas no momento da execução** — tarifas, datasets e exportações mudam; a data de consulta (13/10/2026) acompanha cada afirmação externa (Apêndice C).
- **`ProductForRegistry` substitui `RegistryUserProductDTO`** (deletado do repositório, `git status` `D`); migração completa assumida. [CÓDIGO]
- **IEA permanece fora do CLI** até o workbook real ser verificado (adapter existe, não registrado em `sources/registry.py`). [CÓDIGO]
- **WattSimple pode ficar indisponível** (HTTP 429/challenge observado em 13/10/2026); a fonte é tratada como benchmark genérico com fixtures offline nos testes. [FONTE]

## Open Questions — limite de três (NEEDS CLARIFICATION)

1. **OQ1 — Confirmação do resultado tarifário (Cenário B)** [FR-024]: o DEV confirma **R$ 1152,49** (1460 kWh × 0,78938, Enel SP/Resolução 3.596/2026, vigente em 13/10/2026) como resultado canônico, encerrando o rascunho R$ 1550,41 (escrito contra Enel Rio 1061,10)? Impacto: valor financeiro apresentado. A semântica do valor (TUSD+TE B1 convencional) já está verificada na fonte; resta o aceite formal. Impacto: saída financeira da API.
2. **OQ2 — Resolução da potência de standby** [FR-002, Story 5]: standby deve ser resolvido (a) pela observação de fonte (`product_source_observation.standby_power_w` — preferível quando não comparável entre fontes), (b) por novo campo canônico validado em `Product` (ex.: ressuscitar `avg_idle_energy_for_hour`, hoje contraditado pela 005), ou (c) permanecer indisponível? Impacto: arquitetura do contrato canônico + viabiliza as métricas de standby.
3. **OQ3 — Atualização de catálogo sob INSERT-only** [FR-010]: aceitar que `ON CONFLICT DO NOTHING` mantém o registro antigo quando a fonte muda (comportamento seguro, sem sobrescrita silenciosa) e planejar fluxo futuro controlado (observações versionadas + nova projeção, ou rotina administrativa/migração aprovada)? Nenhum `DO UPDATE` deve ser introduzido sem autorização explícita. Impacto: frescor do catálogo vs. política de escrita.

## Artefatos relacionados (apêndices técnicos)

| Apêndice | Conteúdo |
|---|---|
| [appendix-data-model.md](appendix-data-model.md) | Modelo relacional completo (PK/FK/nullability/unidades), dicionário de dados, estado atual vs. alvo, divergências de schema. |
| [appendix-formulas.md](appendix-formulas.md) | Catálogo de fórmulas com derivação LaTeX, análise dimensional, hipóteses, arredondamento, casos-limite, exemplos numéricos e OQ1. |
| [appendix-sources.md](appendix-sources.md) | Registro de fontes (URL, proprietário, campos, unidade, data de consulta, limitações, adapter/testes) e política de precedência. |
| [appendix-current-state-and-evolution.md](appendix-current-state-and-evolution.md) | Estado atual vs. desejado (arquitetura, API, coletores), decisões 001–006, divergências briefing↔código, backlog e plano de fases A–G. |

**Fluxo de dados (conceitual, validado contra o código)**:

```
Fontes públicas/oficiais (INMETRO XLSX · ENERGY STAR/Socrata · WattSimple CSV · IEA*)
        │  energy_collector (Python) — coleta, normalização, procedência
        ▼
Projeção canônica (merge_products, só fonte primária BR elegível)
        │  INSERT ... ON CONFLICT DO NOTHING (sem DDL; verify_schema antes)
        ▼
PostgreSQL (neondb local) — product (8 cols) + product_source_observation + ENCE + agregados
        │  JPA (Java/Spring) — leitura
        ▼
Catálogo API (/products) ──► Usuário seleciona produto
        │  POST /registryUserProducts (ProductForRegistry) ──► RegistryUserProduct
        ▼
Hub ConsumeMetricsService ──► Formula Bank (ConsumptionCalculator, BigDecimal)
        │                                    ▲
        │                                    └── TariffService (TariffQuote, R$/MWh→R$/kWh, vigência)
        ▼
DTOs (ResultDTO…) ──► API HTTP ──► Frontend (exibe; NÃO recalcula fórmulas autoritativas)
```
(\*) IEA: adapter pronto, fora do CLI até workbook verificado [CÓDIGO].

**Responsabilidades por camada** [DECISÃO + CÓDIGO]: Python = coleta/normalização/procedência/carga autorizada do catálogo; Java = entidade canônica da aplicação, associação usuário-produto, perfil de uso, regras de cálculo, tarifa e resposta da API; PostgreSQL = persistência autoritativa evoluída por migrações; Frontend = captura/apresentação (sem duplicar fórmulas).
