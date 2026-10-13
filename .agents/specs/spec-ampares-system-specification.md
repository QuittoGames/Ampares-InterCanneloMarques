# SPEC — Especificação completa do sistema Ampares (Java/Spring + Coletor Python + PostgreSQL)

**Projeto:** Ampares-InterCanneloMarques — `cannelo.marques.interdisciplinar.interdisciplinar`
**Base auditada:** branch `main` @ `c70d48e`, worktree SUJA (58 arquivos modificados/novos — refactor do motor de consumo em andamento). Nada foi commitado ou descartado.
**Data da auditoria:** 2026-10-13
**Status:** SPEC — somente especificação. Nenhum código, migração ou dado alterado.
**Local:** `.agents/specs/` (SpecKit NÃO inicializado neste repo — sem `.specify/` nem `.opencode/commands/speckit.*.md`; CLI `specify` existe globalmente. Localização canônica do projeto seguida conforme precedent `.agents/specs/spec-registry-refactor-unified-consumption-engine.md`).
**Suítes executadas nesta auditoria:** Java `./mvnw test` → **114 tests, 0 failures, 0 errors** (surefire 15:34, Postgres local `localhost:5432/neondb` v18.6, OSIV warning observado). Python `pytest tests/` → **290 passed** (offline, determinístico). Sem CI (`.github/` ausente).

**Estados de evidência:** `[VC]` VERIFICADO NO CÓDIGO (arquivo:linha) · `[VE]` VERIFICADO NA FONTE EXTERNA (URL + data) · `[D]` DECISÃO JÁ TOMADA (decision record/briefing) · `[ALVO]` ALVO PLANEJADO (não implementado) · `[H]` HIPÓTESE · `[PEND]` PENDÊNCIA DE DECISÃO.

---

## 1. Resumo executivo, objetivos e não-objetivos

O Ampares é um app Spring Boot (porta 8081) que mantém um **catálogo de produtos** (persistido por um coletor Python multi-fonte no PostgreSQL) e permite que um **usuário registre produtos em uso** (`registry_user_product`: quantidade + horas ativas/standby por dia) para receber **métricas de consumo energético** (diário/anual, standby, produto mais consumidor) e **custo estimado** via tarifa de referência única (Enel SP B1). O coletor Python normaliza fontes públicas (INMETRO/PBE, ENERGY STAR/Socrata, WattSimple, IEA) com procedência e grava INSERT-ONLY.

**Objetivos da spec:** (1) descrever o sistema como ele é hoje, com evidência; (2) registrar o contrato canônico e reconciliar Java↔Python↔SQL↔diagrama; (3) catalogar fórmulas com derivação/unidades; (4) registrar tarifa + OQ1; (5) listar divergências, requisitos, fases e pendências.

**Não-objetivos:** implementar código; executar import; alterar schema; commit/push; especificar frontend em detalhe (vanilla JS `src/main/resources/static/`, sem cálculo local `[VC]` cache).

## 2. Estado atual auditado

### 2.1 Stack e config `[VC]`
- `pom.xml`: Java 21, Spring Boot **4.1.1** (Jackson 3 `tools.jackson`), starters data-jpa, data-rest, webmvc, validation, webservices, restclient, aspectj, actuator, h2console; springdoc 3.1.1; postgresql + h2 runtime; lombok declarado e não usado.
- `application.properties`: port 8081; `spring.datasource.url=jdbc:postgresql://localhost:5432/neondb?sslmode=disable`; credenciais via `${DB_USER}/${DB_PASSWORD}` importadas de `.env`; **`ddl-auto=update`** (sem Flyway — migrações manuais em `migrations/`); `debug=true`; springdoc `/v3/api-docs` + swagger.
- Sem `@ControllerAdvice`/`@ExceptionHandler` (grep vazio hoje) → qualquer RuntimeException vira 500 sem corpo legível.
- Sem `docker-compose.yml` no repo (find vazio); `migrations/migrate.sh`/`migrate_remote.sh` o referenciam e contêm credenciais em texto (não reproduzidas aqui). `.env` raiz só tem `DB_USER`/`DB_PASSWORD` — **incompatível** com o coletor (`config.py` exige `DB_URL`/`DATABASE_URL` ou `DB_HOST`/`DB_USERNAME`/`DB_PORT`/`DATABASE`) → coletor não conecta com o `.env` atual.
- `opencode.jsonc` aponta para path antigo (`Projects/Java/interdiciplinar/`) — obsoleto. `.agents/AGENTS.md`, `RULES.md`, `TODO.md`, `VISUALSPEC.md` são arquivos vazios (0 bytes).

### 2.2 Entidades e associação `[VC]`
- `Models/Product.java:14-29`: `id UUID`, `name(150)`, `brand`, `model`, `category`, `subcategory`, `avgPowerW`, `annualEnergyKwh` — **8 campos; sem `standbyPowerW`, `isGeneric`, tensão**.
- `Models/User.java`: `id int` IDENTITY (L18-20), `name`; **`@OneToMany(mappedBy="user")` AINDA EXISTE (L35-36)** com javadoc defensivo (LAZY, init inline, `removeIf` por id L102-109). **Divergência com decision_003** ("User sem coleção") — estado atual ≠ decisão; remover é trabalho pendente (Fase C), não feito.
- `Models/RegistryUserProduct.java:22-36`: `@ManyToOne user/product` (nullable=false), `quantity int` primitivo, `avgActiveHours`/`hoursStandby` `BigDecimal` anuláveis. Sem `@UniqueConstraint` — UNIQUE existe só no SQL (`create.sql`, `seed.sql`); unicidade checada em código (`RegistryUserService:85-92` → `IllegalStateException`).
- `interfaces/MetricsService.java`: package `interfaces` (OQ2 do spec anterior **resolvido**); genérica `<Client extends User, OperationValue extends Number>`; 8 métodos: `calculate→Optional<ResultDTO>`, `calculateAverageEnergyByUser`, `calculateMostConsumerProduct`, `calculateMostConsumerProductByCategory`, `calculateStandbyConsumeAvg`, `calculateStandbyConsumesForProduct`, `getProductsRegistrys→List`, `avg`.

### 2.3 Motor de cálculo — Formula Bank `[VC]` (`Services/Metrics/ConsumptionCalculator.java`, 523 linhas)
Camada primitiva `static`, pura, `BigDecimal`/`MathContext.DECIMAL128`; constantes `DAYS_PER_YEAR=365`, `MONTHS_PER_YEAR=12`, `WATTS_PER_KILOWATT=1000`, `MONETARY_SCALE=2` (HALF_UP), `HOUR_SCALE=4`, `MAX_HOURS_PER_DAY=24`.
| Método (linha) | Fórmula | Unidade | Falha |
|---|---|---|---|
| `dailyKwh` L117 | `P×h×q/1000` | kWh/dia | `InputValidationException` (null, P≤0, h∉[0,24], q<1) |
| `monthlyKwh` L138 | `daily×days` | kWh/período | idem |
| `averageMonthKwh` L160 | `annual/12` (mês médio, rotulado) | kWh/mês | idem |
| `annualKwh` L176 | `daily×365` | kWh/ano | idem |
| `sourceAnnualKwh` L200 | `E_fonte×q` (**nunca ×365 de novo**) | kWh/ano | idem |
| `sourceDailyKwh` L218 | `E_fonte×q/365` | kWh/dia | idem |
| `cost` L264 | `kWh×T(R$/kWh)`, 2 casas HALF_UP | R$ | idem |
| `standbyDailyKwh` L294 | `P_sb×h_sb×q/1000`; **P_sb null → Optional.empty()** | kWh/dia | null→vazio; inválido→exceção |
| `standbyAnnualKwh` L320 / `standbyAnnualCost` L341 | `×365` / `×T` | kWh/ano / R$/ano | idem |
| `inverseDailyHours` L376 | `E×1000/(P×q×365)`; fora [0,24] → vazio (sem clamp) | h/dia (escala 4) | idem |
Legado mantido: `calculate(registry, hoursProvider)` L414 (**null→ZERO silencioso** — compatibilidade) e `calculateDailyActiveHours` L461 (retorna null em inválido).

### 2.4 Hub `ConsumeMetricsService` `[VC]` (446 linhas) — decisions 001/004/006
`implements MetricsService<User, BigDecimal>`, `AVG_SCALE=6` HALF_UP. Filtro `hasComputableActiveInputs` (L104: presença + try/catch `InputValidationException`) **exclui registros inconsistentes dos 4 agregados sem derrubar os demais** (D006). `calculate` (L194): vazio/sem válidos → `Optional.empty()` (tarifa nem consultada); monta `ResultDTO(avgDailyKwh, avgUseInYear, totalDailyKwh, totalAnnualKwh, dailyCost, annualCost, productsList)` com custo via `ConsumptionCalculator.cost` e tarifa de `TariffService.getReferenceTariff(LocalDate.now())` (L229) — **`LocalDate.now()` inline torna o teste dependente de relógio**. Ranking: `max(comparing(calculateDailyKwh))` L304 (linear, correto); categoria `equalsIgnoreCase` DESC L332. **Standby: ambos os métodos retornam sempre `Optional.empty()`** (L355-358, L377-381) — potência de standby não existe em `Product`; nunca usa potência ativa. `getProductsRegistrys` nunca lança por lista vazia (L395-398). `avg(OperationValue, List<?>)` L421 filtra `Number`, escala 6 (OQ curinga aberto em D004).

### 2.5 Tarifa — fonte única `[VC]` + `[VE]`
- `config/TariffProperties.java` (prefixo `ampares.energy.tariff`, defaults em código): `ENEL_SP`, `B1_RESIDENCIAL`, `CONVENCIONAL`, `publishedValuePerMwh=789.38`, vigência `2026-07-04..2027-07-03` (inclusiva), `sourceUrl` Enel SP. Overrides opcionais; `application.properties` intocada (escopo humano — D003 do spec anterior).
- `TariffService.getReferenceTariff(date)` (L55-84): nulo/≤0 → `TariffUnavailableException` (nunca valor inventado); divide por 1000 → R$/kWh; `resolveStatus` (L93-99): `validFrom<=date<=validUntil` → `VALID`; janela ausente/incoerente → `OUTDATED` (nunca substitui tarifa). `TariffQuote` record com `originUnit="R$/MWh"` e metadados.
- **`[VE]` Enel SP (consulta 2026-10-13):** página confirma Resolução Homologatória ANEEL **nº 3.596/2026 (30/06/2026), válidas a partir de 04/07/2026** — B1 Residencial: TUSD **472,42** + TE **316,96** = **789,38 R$/MWh** (tabela "Grupo B" mostra 789,38 para RESIDENCIAL B1). **Resolve a semântica de `publishedValuePerMwh`: é TUSD+TE somados (tarifa de energia de referência); EXCLUI tributos (ICMS/PIS/COFINS), bandeiras tarifárias, iluminação pública e custos de disponibilidade** → resultado é estimativa, nunca conta final.
- **`[VE]`** dataset Socrata `pd96-rr3d` (TVs) expõe potências de standby medidas (`power_consumption_in_standby_mode_when_network_not_connected_watts`, `..._network_connected_watts`, `measured_standby_mode_w`) — caminho real futuro para standby de TVs. `[VE]` Catálogo Socrata 2026-10-13: os 4 datasets vivos, atualizados 12-13/10/2026.

### 2.6 Registro de produto (fluxo) `[VC]`
`POST /registryUserProducts` (`RegistryUserProductController:74-80`, `@Valid`) → `RegistryUserService.registerUserProduct` (L65-97): resolve User/Product (`UserNotFoundException`/`ProductNotFoundException`), valida faixas (`InvalidRegistryException`; `avgActiveHours` ∈[0,24] **é estimativa do usuário, nunca derivada**; `hoursStandby` null permanece null — derivação `24−ativo` proibida), duplicata (user,product) → `IllegalStateException`, converte (`ProductForRegistryConverter` puro) e salva. `GET /registryUserProducts/user/{userId}` → 200 lista (via `UserService.findAllProductrs` → hub). Legado `UserService.addProduct` (L40-57) tem `userOptional.get()` sem guarda (NoSuchElementException→500) e `quantity 0→1` silencioso; `removeProduct` (L59-71) **busca mas nunca deleta** (código morto).

### 2.7 Contratos HTTP `[VC]`
`POST /api/metrics/users/calculate` → 200 `ResultDTO` | 404 se vazio. `average-energy` e `standby-*` → **200 com `orElse(BigDecimal.ZERO)`** (mapeia Optional.empty→0 na borda HTTP — divergência do princípio "vazio≠zero", ver §5). `most-consumer-product` → 200/404. `GET /api/metrics/search/{userId}?search=` → só o 1º produto, senão `ProductNotFoundException`. `GET /products?search&size` → **entidades `Product` direto**. **Sem `@JsonIgnore`/`@JsonManagedReference` em lugar nenhum** + OSIV ativo (warning no log dos testes) + `ResultDTO.productsList` é `List<RegistryUserProduct>` → **risco real de recursão infinita Jackson (RegistryUserProduct→User→registryUserProducts→…)** em calculate e na listagem de registros. `[H]` não confirmado em runtime (suítes não serializam grafo populado) — verificação obrigatória (Fase C).

### 2.8 Coletor Python `[VC]`
- **`database.py`: política INSERT-ONLY IMPLEMENTADA** — `INSERT ... ON CONFLICT DO NOTHING` em todas as escritas (`_INSERT_PRODUCT_SQL` L70-75 com exatamente as 8 colunas; observação L80-88 conflito `(source, external_id)`; labels L91-95; agregados L98-103); `verify_schema` (L139-169) só lê `information_schema` e falha rápido; **zero DDL, zero `DO UPDATE`, zero `ensure_table`** — a divergência relatada no briefing (DDL/DO UPDATE em database.py) **está RESOLVIDA no worktree atual**. Lotes ordenados por UUID (anti-deadlock); `users`/`registry_user_product` nunca tocados.
- `models.py`: `Product` dataclass — 8 canônicos + **proveniência em memória** (`standby_power_w`, `is_generic`, `voltage_raw/kind/min/max`, `raw_energy_value/unit`, `label_class`) que NUNCA vão ao INSERT de `product` (vão à observação); UUID5 determinístico (`dedup_key` L118-140, canonicalização NFKC+casefold); `merge_products` (L306-371) projeta canônico por `category|subcategory` com **média aritmética só de elegíveis** (fonte primária BR não-genérica); `AggregateRecord` para IEA (nunca produto).
- `precedence.py`: `PRIMARY_BR_SOURCES={"INMETRO"}`, `FOREIGN={"ENERGY STAR","ENERGY_STAR","ENERGYSTAR"}`, `GENERIC={"WATTSIMPLE"}`, `AGGREGATE={"IEA"}`, `CANONICAL_SOURCE="CANONICAL"`; desconhecida = conservadora (não contribui).
- `normalization.py`: **sem fórmulas derivadas** (motor Python removido; `test_normalization.py:197-200` afirma que `compute_equivalent_hours_year`/`compute_estimated_cost` NÃO existem); `_to_decimal` seguro (negativo/NaN/inf→None); vazio→None; tensão via `voltage.py` (nunca converte; `unknown/monovolt/bivolt/range`; faixa plausível 50-600 V).
- Fontes: `inmetro.py` (fixture CSV; **kWh/mês→ano ×12 exatamente uma vez** L360-391; anual explícito tem precedência e nunca leva ×12; ENCE validada A+++..G; subcategoria das categorias oficiais 1-6; marca+modelo obrigatórios; `avg_power_w=None` — PBE não declara potência instantânea), `inmetro_xlsx.py` (**transporte REAL**: XLSX oficial, consumo POR TENSAO 127/220 V como observações distintas, coluna `VA` ignorada, identidade `marca|modelo|tensão`, parser stdlib), `energy_star.py` (Socrata 1:1, UUIDs bit-a-bit preservados), `wattsimple.py` (CSV oficial, `is_generic=True`), `iea.py` (agregado only), `registry.py` (3 fontes no CLI; IEA fora).
- `config.py`: `DbConfig.from_env` (3 estilos, senha `repr=False`, nunca em log); `DEFAULT_TARIFF_PER_KWH=None`; `KNOWN_DATASETS` com mapeamentos (ver §3). `data_collector.py`: CLI legado + `--source` multi-fonte. `taxonomy.py`: taxonomia global (fallback "Outros/Não categorizado").

### 2.9 Migrações `[VC]`
- `create.sql` (reconciliado): `users(id SERIAL, name VC(50))`; `product` **8 colunas** (com `subcategory`); `product_source_observation` (procedência completa, CHECKs ≥0, `UNIQUE(source, external_id)`, índices); `registry_user_product` (FKs NOT NULL, `UNIQUE(user_id, product_id)`). Cabeçalho lista as fontes autoritativas.
- `004` (base observação), `005` (`subcategory` + procedência; **deprecia `product.standby_power_w`/`is_generic`** — mantidos sem escrita), `006` (`energy_label_class` CHECK A+++..G; `aggregate_reference` UNIQUE(source,country,year,metric,appliance)) — todos idempotentes, aditivos.
- **`add_avg_idle_energy_for_hour.sql`: coluna `product.avg_idle_energy_for_hour NUMERIC` órfã** — `Product.java` NÃO tem o campo, logo o comentário do script ("Hibernate aplica a partir da entidade") é falso hoje; o hub não lê a coluna (standby → Optional.empty). Nome também ambíguo (diz "por hora" mas semântica alvo é potência W). Aplicar ou remover é decisão (Fase C/D).
- `seed.sql`: thresholds legados (≥1000W→4h/20h; ≥200W→8h/16h) — superseded pelo perfil do usuário; usa `ON CONFLICT DO UPDATE` no nome do user de teste (script de dev, não é o coletor).
- Diagrama `docs/arquiteture.drawio` atualizado: User/registry_user_product/Product(8)/product_source_observation/energy_label_class/aggregate_reference + `data_raw_product (in-memory)` — **sem** `avg_idle_energy_for_hour` (assert em `test_brazil_normalization.py:399`).

### 2.10 Suítes de teste `[VC]`
Java: 13 classes — `ConsumptionCalculatorTest`, `HourServiceTest`, `TariffServiceTest`, `ConsumeMetricsServiceTest`, `RegistryCalculatorTest`, `RegistryUserServiceTest`, `ProductForRegistryConverterTest`, controllers, `UserTest`, `ProductRepositorySearchTest` (H2), contextLoads (Postgres real). Python: 12 arquivos, 290 testes offline (fixtures determinísticas, sem rede). Cobertura desejada adicional no §9.

## 3. Registro de fontes externas (consulta 2026-10-13)

| Fonte | Proprietário | URL | Dado usado (unidade) | Verificação | Limitações |
|---|---|---|---|---|---|
| PBE Refrigeradores (XLSX oficial) | INMETRO | `inmetro.gov.br/CONSUMIDOR/pbe/refrigeradores.asp` → `Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx` | consumo kWh/mês (→×12 uma vez), por tensão 127/220 V; marca/modelo; ENCE | `[VE]` página viva, link EXCEL confirmado | consumo por tensão; sem potência instantânea; XLSX versionado (~996 linhas, versão 12/11/2021 citada); `pbe.inmetro.gov.br` é web app sem API REST conhecida — NENHUM endpoint inventado |
| ENERGY STAR Refrigerators | EPA (Socrata) | `data.energystar.gov` id `p5st-her9` | `annual_energy_use_kwh_yr` (kWh/ano), `brand_name`, `model_number`, `pd_id` | `[VE]` dataset vivo, atualizado 2026-10-13 | sem campo de potência; referência estrangeira (não equivale a produto BR) |
| ENERGY STAR Televisions | EPA | `pd96-rr3d` | `power_consumption_in_on_mode_watts` (W), `reported_annual_energy_consumption_kwh` (kWh/ano), **standby: `power_consumption_in_standby_mode_when_network_(not_)connected_watts`, `measured_standby_mode_w`** | `[VE]` vivo 2026-10-12 | standby dividido em 2 modos (rede conectada/não) — escolha de domínio pendente se usado |
| ENERGY STAR Computers | EPA | `rxdj-2c88` ("Computers V9.0") | `tec_of_model_kwh` (TEC kWh/ano) | `[VE]` vivo | TEC é teste padronizado, não uso real |
| ENERGY STAR Clothes Washers | EPA | `bghd-e2wd` | `annual_energy_use_kwh_year` (kWh/ano) | `[VE]` vivo 2026-10-13 | **o briefing dizia `annual_energy_use_kwh_yr` — INCORRETO; `config.py:101` está certo (`_year`)**; base 295 cargas/ano DOE |
| WattSimple | wattsimple.com | `wattsimple.com/data/appliance-wattage/csv` | `running_watts` (W típico), `starting_watts`, `typical_hours_per_day` | `[VC]` adapter + docs do coletor (143 registros, CC BY 4.0) | genérico por categoria — NUNCA tratado como spec de fabricante |
| IEA Household Appliances | IEA | `iea.org/data-and-statistics/data-product/household-appliances-database` | agregados país/ano (stock, difusão) | `[VC]` adapter; `[PEND]` página não reconsultada nesta execução | workbook real não verificado → fora do registry; nunca vira produto |
| Enel SP tarifas | Enel/ANEEL | `enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html` | B1: TUSD 472,42 + TE 316,96 = 789,38 R$/MWh (RH 3.596/2026, desde 04/07/2026) | `[VE]` 2026-10-13 | exclui tributos/bandeiras/iluminação pública; reajuste anual esperado ~jun/jul |
| ANEEL Ranking das Tarifas | ANEEL | `gov.br/aneel/pt-br/assuntos/tarifas/ranking-das-tarifas` | — | `[PEND]` não consultada nesta execução | revalidar antes de usar |
| NIST SP 811 (Wh/kWh/J) | NIST | nist.gov/pml/special-publication-811 | fatores de conversão | `[PEND]` não consultada; conversões usadas são elementares (1 kWh=1000 Wh) |

**Precedência (implementada em `precedence.py`):** 1º modelo BR identificado (INMETRO/PBE ou fabricante) → alimenta projeção canônica; 2º especificação estrangeira → só observação (`product_source_observation`), nunca média com BR; 3º genérica (WattSimple) → `is_generic=True`, rotulada; 4º agregado IEA → `aggregate_reference`, nunca produto. Sem fuzzy merge entre países/modelos/fontes; IDs externos e procedência preservados; sem elegível → métrica NULL (nunca inventada). `[VC]`

**Tensão:** NUNCA converter 220↔127/110; rótulo 110 V ≠ spec 127 V; bivolt e faixa classificados (`voltage_kind`); ausente = `unknown` (nunca inferida por país/estado); consumo por tensão = observações distintas (`marca|modelo|tensão`); coluna `VA` ignorada (VA ≠ kWh). Entidade Java canônica NÃO tem tensão — adicionar é decisão de domínio. `[VC]`

## 4. Contrato canônico `Product` — reconciliação

| Campo | `Product.java` | DDL `create.sql` | Coletor (INSERT) | drawio | Status |
|---|---|---|---|---|---|
| id UUID / name(150) / brand / model / category | ✓ | ✓ | ✓ | ✓ | CONSISTENTE |
| subcategory | ✓ | ✓ | ✓ | ✓ | CONSISTENTE |
| avg_power_w NUMERIC (W) / annual_energy_kwh NUMERIC (kWh/**ano**) | ✓ | ✓ | ✓ | ✓ | CONSISTENTE |
| standby_power_w, is_generic | ✗ (deprecado) | — (observação) | — (observação) | — | **RESOLVIDO** (005: ficam na observação) |
| tensão / raw_energy_* | ✗ | observação | observação | observação | CONSISTENTE (procedência) |
| avg_idle_energy_for_hour | ✗ | script órfão | ✗ | ✗ | **DIVERGENTE** (§5-D1) |

Semântica por camada: especificação de modelo individual (observação por fonte) → projeção canônica por categoria (média de elegíveis INMETRO) → perfil do usuário (`registry_user_product`) → valores calculados (nunca persistidos no catálogo). O coletor não calcula perfil; Java não deriva horas do usuário; conversões Python só quando a unidade é declarada (kWh/mês→ano ×12 uma vez; ausente nunca vira zero). `[VC]`

## 5. Divergências conhecidas (estado atual × alvo)

- **D1** `[VC]` `add_avg_idle_energy_for_hour.sql` órfão: coluna sem campo JPA; comentário afirma que Hibernate a cria (falso); hub retorna vazio. Alvo: decisão — criar `standbyPowerW` canônico validado (nome inequívoco) OU remover o script e resolver standby só via observação (OQ-2).
- **D2** `[VC]` `User.@OneToMany` existe ≠ decision_003 (User sem coleção). Risco: ciclo de serialização Jackson com OSIV (§2.7) + acoplamento. Alvo (Fase C): remover coleção e métodos de lista; navegação só `@ManyToOne` + repositório/hub.
- **D3** `[VC]` Sem `@ControllerAdvice`: UserNotFound/ProductNotFound/InvalidRegistry/InputValidation/TariffUnavailable → 500 genérico. Alvo: advice com 400/404/409 + corpo com `message` (Fase C).
- **D4** `[VC]` Bordas HTTP convertem `Optional.empty()` → `BigDecimal.ZERO` (average-energy, standby-avg, standby-by-product) — "vazio" vira "zero" na API. Alvo: contrato explícito por métrica (404/204/corpo com status), nunca zero ambíguo.
- **D5** `[VC]` Exposição de entidades JPA: `ResultDTO.productsList`, `most-consumer-product`, `GET /products`, `GET /registryUserProducts/user/{id}` retornam entidades. Alvo: DTOs estáveis sem ciclos (registros só com campos de uso + id/nome do produto).
- **D6** `[VC]` `UserService` legado: `addProduct` com `.get()` sem guarda e `quantity 0→1` silencioso; `removeProduct` nunca deleta. Alvo: deletar ou completar endpoints; sem defaults silenciosos.
- **D7** `[VC]` `.env` raiz (DB_USER/DB_PASSWORD) ≠ chaves do coletor (DB_USERNAME/DB_HOST/DB_PORT/DATABASE ou DB_URL) → coletor não conecta hoje; sem `docker-compose.yml` no repo apesar de `migrate.sh` referenciá-lo. Docs do coletor ainda citam Supabase; banco alvo é o Postgres local Docker (`localhost:5432/neondb`). Alvo: alinhar variáveis + compose + role restrito INSERT-only (TODO TASK-035).
- **D8** `[VC]` Naming de fonte: legado usa `"ENERGY STAR"` (espaço, `SOURCE_NAME`), multi-fonte `"ENERGY_STAR"` (`SOURCE_CODE`); `precedence.py` aceita ambos. Alvo: um único código canônico por fonte.
- **D9** `[VC]` `noRegisteredProductsException`/`ProductEmptyException` definidas e não usadas (resquício). Alvo: usar ou remover.
- **D10** `[VC]` `metricsService.calculate` usa `LocalDate.now()` inline (L229) — teste de custo depende do relógio. Alvo: injetar `Clock`/data.
- **D11** `[VC]` Cache `.agents/protocol/docs/codebase-explorer.json` (13:31 @ c70d48e) STALE: descreve DDL/DO UPDATE e fórmulas derivadas em Python que não existem mais, e estrutura pré-refactor. Alvo: regenerar APÓS estabilizar (script `persist_artifact.py` confirmado no repo? — verificar na execução).
- **D12** `[VC]` `metricsByCategoryDTO`/categoria: método do hub existe, sem endpoint HTTP. Alvo: expor ou remover (decisão).
- **D13** `[H]` Recursão Jackson em produção (§2.7) — reproduzir e corrigir junto com D2/D5.

## 6. OQ1 — divergência numérica da tarifa

Cenário B (1000 W × 2 h/dia × 2 un = 4 kWh/dia → 1460 kWh/ano):
- **Rascunho:** R$ 1.550,41 (implicaria ~1,06193 R$/kWh ≈ referência antiga Enel **Rio** 1061,10 R$/MWh → 1549,21).
- **Cálculo atual:** 1460 × 0,78938 = **R$ 1.152,49** (HALF_UP) sob ENEL_SP 789,38 R$/MWh.
- **Resolução `[VE]`:** a tarifa configurada foi verificada na página oficial (RH ANEEL 3.596/2026; TUSD 472,42 + TE 316,96 = 789,38 R$/MWh; vigência desde 04/07/2026). A fórmula e as entradas estão corretas; o rascunho foi escrito contra outra referência e **não deve ser forçado**. `validUntil=2027-07-03` é hipótese de janela de 1 ano `[H]` (o próximo reajuste ~30/06/2027 segue o padrão das RHs 3.339/2024, 3.477/2025, 3.596/2026). `publishedValuePerMwh` = **TUSD+TE** — pendência OQ-1 encerrada como VERIFICADA com fonte e data; restam excluídos tributos/bandeiras (documentado).

## 7. Fórmulas — derivação (referência)

Potência média `P = ΔE/Δt` ⟹ `ΔE = P·Δt` (integral `E=∫P dt` se variável). `W×h = Wh`; `1000 Wh = 1 kWh` (fator de conversão, não ajuste empírico). `×q` soma unidades idênticas; aparelhos distintos somam individualmente `Σ(Pi·hi)/1000`. `×365` acumula o diário (ano de 365 dias, sem bissexto — convenção do código). Energia anual DECLARADA pela fonte é referência de ensaio: usa-se `E_fonte×q` e `/365` p/ dia — **nunca re-anualizar**. `kWh/mês→ano` só ×12 quando a fonte declara mensal (INMETRO). `R$/MWh÷1000 = R$/kWh`. Inversa `h = E×1000/(P·q·365)` — só com mesmo modelo/unidades; fora de [0,24] → não calculável. Standby: `P_sb×h_sb×q/1000` (+×365; ×T p/ custo) — exige `P_sb` verificada; sem ela = INDISPONÍVEL, nunca zero, nunca `avgPowerW`. Agregações: total `ΣEi`, média por registro `ΣEi/n`, média por unidade `ΣEi/Σqi` (métricas DISTINTAS com nomes próprios); máximo = busca linear (`max`), não binária; mesmo período/unidade em toda soma; empate: primeiro encontrado pela ordenação do stream (definir se exigir desempate determinístico). Precisão: `BigDecimal`/`DECIMAL128` intermediário; dinheiro 2 casas HALF_UP só na saída; `double/float` proibidos.

## 8. Requisitos numerados e critérios de aceitação

1. **FR-01 Catálogo canônico consistente** — Java/Python/SQL/diagrama concordam (§4); divergências resolvidas ou pendentes explícitas. AC: tabela §4 sem linha DIVERGENTE.
2. **FR-02 Procedência** — todo valor com fonte, id externo, unidade e período; genérico/estrangeiro rotulado. AC: observação persiste `source, external_id, raw_energy_value/unit, voltage_*`; `is_generic` na observação.
3. **FR-03 Normalização segura** — conversões só com unidade declarada (×12 uma vez); ausência ≠ zero; re-coleta sem duplicatas. AC: testes `test_inmetro*`, `test_brazil_normalization`, `test_bit_identical_uuids` verdes.
4. **FR-04 Banco único autoritativo** — coletor no Postgres de produção via env; INSERT-only `DO NOTHING`; sem DDL; nunca toca `users`/`registry_user_product`; schema só por migrações (`verify_schema` falha rápido). AC: grep sem DDL/DO UPDATE no coletor; testes `test_database` verificam conflito sem update/delete.
5. **FR-05 Cálculo dimensionalmente correto** — fórmulas do §2.3/§7; unidades explícitas; nunca dupla anualização. AC: cenários A (100W,5h,2 → 1 kWh/dia; 365 kWh/ano) e B (1000W,2h,2 → 4; 1460) verdes.
6. **FR-06 Precisão decimal** — BigDecimal; dinheiro 2 casas HALF_UP na saída. AC: `cost(1460, 0.78938)=1152.49`.
7. **FR-07 Standby correto** — só com `P_standby` verificada; senão indisponível (Optional.empty). AC: métodos standby do hub retornam vazio hoje; teste proíbe uso de potência ativa.
8. **FR-08 Tarifa rastreável** — `TariffQuote` com distribuidora/classe/modalidade/unidade original/vigência/status/sourceUrl; OUTDATED nunca apresentado como atual; ausente → `TariffUnavailableException`. AC: `TariffServiceTest` cobre limites inclusivos, antes/depois, janela ausente/incoerente.
9. **FR-09 API consistente** — DTOs tipados, validação `@Valid`, sem ciclos, retorno vazio explícito (não ZERO silencioso — resolver D4), `getProductsRegistrys` lista vazia ≠ erro. AC: controller tests + teste de serialização sem StackOverflow (D13).
10. **FR-10 Ranking/agregação** — total/média-por-registro/média-por-unidade distintas; máximo linear; mesmo período; empate e lista vazia definidos; registro inconsistente excluído sem derrubar os demais (D006). AC: `ConsumeMetricsServiceTest`.
11. **FR-11 Tensão preservada** — sem conversão artificial; 110/127/220/bivolt/faixa distintos; ausente unknown. AC: `voltage.py` tests.
12. **FR-12 OQ1 reproduzível** — entradas documentadas (1460 kWh × 0,78938) com resultado rastreável e status VALID na janela; divergência do rascunho explicada (§6). AC: teste de custo anual do cenário B.
13. **NFR-01 Segurança** — senha fora de repr/log; sem segredo em docs; URL de conexão nunca logada; cookies HttpOnly existentes `[VC]`; auth por ID é limitação conhecida de projeto escolar (registro em Known Limitations, não expandir aqui).
14. **NFR-02 Idempotência/FK** — UUID5 determinístico; reimport sem duplicatas; integridade referencial; falha de lote isolada; falha de fonte não apaga dado válido.
15. **NFR-03 Testabilidade offline** — adapters com fixtures; sem rede nos testes (290 testes Python offline comprovado).
16. **NFR-04 Sem operações destrutivas implícitas** — migrações aditivas; nada de DROP/TRUNCATE no pipeline; seed é script de dev separado.

## 9. Testes a planejar (lacunas além do existente)

Serialização JSON de `ResultDTO`/listagem sem recursão (D13) · bordas HTTP de Optional.empty (D4) · integração real do fluxo calculate→custo com tarifa (Clock fixo, D10) · `energy_label_class`/`aggregate_reference` end-to-end · `inmetro_xlsx` contra o XLSX real (fixture derivada do arquivo oficial) · conflito de observação `(source, external_id)` não atualiza · categoria sem match → Optional.empty · `Hday>24` → exceção (HourService já cobre) · reparo/decisão dos métodos legados `calculate` (null→ZERO) quando absorvidos.

## 10. Plano de evolução (fases — sem implementar agora)

- **Fase A — Contrato/auditoria (parcialmente FEITA nesta spec):** reconciliação §4 confirmada; restam D1 (coluna órfã) e validação do `persist_artifact.py`.
- **Fase B — Integridade dos cálculos:** OQ1 fechada (§6); manter fonte única de cada fórmula (hub→motor); testes A/B/C determinísticos; Clock injetável (D10).
- **Fase C — JPA/serviços/API:** D2 (remover `@OneToMany`), D3 (ControllerAdvice), D5 (DTOs sem ciclos), D4 (contrato de vazio), D6 (UserService), D9, D12 — com backup/plano antes de qualquer dado.
- **Fase D — Tarifa:** manter validação temporal do valor configurado (não é atualização live); decidir histórico/atualização futura; rotular sempre "estimativa pela tarifa de referência TUSD+TE, sem tributos/bandeiras".
- **Fase E — Coletor/persistência:** D7 (env/compose/role restrito INSERT-only), aplicar migrações 004/005/006 no banco real com backup (TASK-034/035), primeiro import real auditado (TASK-037).
- **Fase F — Fonte brasileira:** expandir INMETRO (novas categorias `.asp`, cadência — TASK-036); mapear standby de TVs do dataset `pd96-rr3d` (campos verificados) para alimentar `P_standby` futura; IEA continua fora até workbook verificado.
- **Fase G — Consistência/docs:** diagrama e docs pós-decisões; suítes completas; regenerar `codebase-explorer.json` (D11) com o script real, sem segredos.

## 11. Decisões pendentes — máximo 3

1. **OQ-2 Standby `[PEND]`:** resolver `P_standby` via **observação de fonte** (recomendado — dados não são universalmente comparáveis; TVs já têm campos `[VE]`) ou campo canônico `standby_power_w` validado (+ reconciliar/eliminar o script órfão D1)? Estado atual, alternativas e risco em D1/D13; sem resposta, standby permanece indisponível (comportamento atual correto).
2. **OQ-3 Atualização de catálogo no modo INSERT-only `[PEND]`:** aceitar que conflito NÃO atualiza (estado alvo: seguro, sem sobrescrever) e planejar rotina futura controlada (observações versionadas + nova projeção/migração aprovada), ou formalizar outra estratégia? **Proibido introduzir `DO UPDATE` sem autorização explícita do DEV.**
3. **OQ-4 Contrato HTTP de vazio `[PEND]` (D4):** métricas sem dados → 404, 204 ou corpo com status? Afeta front e testes; atual `orElse(ZERO)` é ambíguo.

Questões já decididas NÃO reabrir: hub único (D001), User sem coleção (D003 — pendência é executar, não decidir), contrato null/Optional (D004), HoursService (D005), exclusão de inconsistentes (D006), tarifa fonte única Enel SP (D + `[VE]`), INSERT-only (D + código), precedência de fontes, tensão sem conversão.

## 12. Estado atual, decisões e backlog (registro §17 do briefing)

Implementado e verificado: Formula Bank completo (§2.3); hub com contrato D004/D006 (§2.4); TariffService/Quote/Properties com defaults verificados `[VE]`; HourService D005; registro sem derivação de horas; coletor INSERT-only sem DDL; migrações reconciliadas; diagrama atualizado; 114+290 testes verdes. Histórico/alvo pendente: remoção efetiva do `@OneToMany` (D003→D2); absorção/eliminação final de `RegistryCalculator` (@Deprecated, mantido p/ testes) e dos métodos legados `calculate`/`calculateDailyActiveHours` (null→ZERO); `AVG_SCALE=6` já nomeado (renomeação de `DIVISION_SCALE` tornou-se irrelevante — constante nova); `User.getId()` `int` vs DTO `Integer` (consistente via autoboxing; manter contrato HTTP estável); `ProductForRegistry` com tipos fortes conforme alvo `[VC]`; login cria user com o MESMO id (fluxo corrigido vs bug antigo do cache); `.agents/AGENTS.md`/`RULES.md` vazios — instruções do ecossistema ainda não persistidas neste repo.

## 13. Checklist de qualidade da spec (manual — SpecKit não instalado)

- [x] Problema/objetivos claros e não-objetivos definidos (§1)
- [x] Toda afirmação de código com arquivo:linha (§2, §4-§6)
- [x] Toda afirmação externa com URL + organização + data de consulta; não consultadas marcadas `[PEND]` (§3)
- [x] Fórmulas com derivação, unidades, hipóteses, arredondamento e casos-limite (§2.3, §7)
- [x] Estados de evidência separados (VC/VE/D/ALVO/H/PEND) em todo o documento
- [x] Estado atual vs alvo explícitos; divergências numeradas (D1-D13)
- [x] Requisitos numerados + critérios de aceitação verificáveis (§8)
- [x] Plano de fases com dependências e critérios (§10)
- [x] Pendências de decisão ≤ 3, sem reabrir decidido (§11)
- [x] Sem credenciais/segredos; sem número de tarifa sem vigência e fonte (§3, §6)
- [x] Testes existentes executados com resultado real (114 + 290) e lacunas listadas (§9)
- [ ] Checklist `speckit.checklist`/`analyze`: NÃO EXECUTADO — SpecKit ausente no repo (limitação registrada; análise manual acima)
- [ ] Apêndices adicionais: dispensados — spec única autocontida

## 14. Handoff

Pronta para `/speckit.clarify` ou `/speckit.plan` **após** inicialização do SpecKit pelo DEV (não inicializado aqui — nenhum `--force` executado). Implementador deve ler: este arquivo + `.agents/decisions/decision_001..006.json` + `.agents/specs/spec-registry-refactor-unified-consumption-engine.md` (histórico). Não re-investigar: estado do código (§2), fontes externas verificadas (§3), OQ1 (§6), divergências (§5). Baseline: 114 testes Java e 290 Python verdes em 2026-10-13; worktree suja — não descartar mudanças locais; sem commit/push.
