# Apêndice A — Modelo de Dados e Dicionário (Ampares)

**Spec principal**: [spec.md](spec.md) · **Data**: 2026-10-13 · Estados de evidência conforme legenda da spec.

## A.1 Diagrama relacional (estado atual verificado)

```
users ──────────< registry_user_product >────────── product
(id SERIAL PK)    (id UUID PK)                      (id UUID PK, 8 colunas canônicas)
                  user_id FK → users.id   NOT NULL
                  product_id FK → product.id NOT NULL
                  UNIQUE (user_id, product_id)
                                                    │
                                                    └──< product_source_observation
                                                          (id UUID PK,
                                                           canonical_product_id FK → product.id ON DELETE CASCADE,
                                                           UNIQUE (source, external_id))
                                                    └──< energy_label_class
                                                          (id UUID PK FK → product.id ON DELETE CASCADE)
aggregate_reference  (independente — sem FK para product)
```

- Relação conceitual **muitos-para-muitos** entre `users` e `product`, resolvida por `registry_user_product`. [CÓDIGO `create.sql:100-108`]
- `ON DELETE CASCADE` apenas nas tabelas de proveniência/roteiro (observação e ENCE) — criadas por migração 004/006. [CÓDIGO]

## A.2 Dicionário de dados — tabelas

### `users` [CÓDIGO `create.sql:21-24`; `User.java:14-23`]

| Coluna | Tipo | Nulo | Fonte Java | Unidade/Semântica |
|---|---|---|---|---|
| `id` | SERIAL (PK) | não | `int id` `GenerationType.IDENTITY` | identificador; login do cliente reusa o mesmo id |
| `name` | VARCHAR(50) | sim | `String name` `@Column(nullable = true)` | nome; criado como `"user <id>"` no login por id |

Obs.: a entidade Java declara `name` nullable; o seed usa `'Usuário Teste'`. `User.java` (estado pós-15:57 de 13/10/2026): `@OneToMany` e o campo `registryUserProducts` foram **removidos** (DECISÃO 003 aplicada na entidade), mas os métodos auxiliares órfãos (l.45-92) ainda referenciam o campo/import removidos → **arquivo não compila** (javac, 13/10/2026) — ver §A.5/D.1.

### `product` — contrato canônico de 8 colunas [CÓDIGO `create.sql:40-49`; `Product.java:12-29`; `database.py:70-75`]

| Coluna | Tipo | Nulo | Java | Python (dataclass) | Unidade/Semântica |
|---|---|---|---|---|---|
| `id` | UUID (PK) | não | `UUID id` `GenerationType.UUID` | `product_id()` uuid5 determinístico | uuid5 sobre `source|chave estável` (canonicalizada NFKC/casefold) [CÓDIGO `models.py:118-140`] |
| `name` | VARCHAR(150) | sim | `name` | `name` (truncate 150) | composto marca+modelo quando a fonte separa |
| `brand` | VARCHAR(255) | sim | `brand` | `brand` | marca declarada |
| `model` | VARCHAR(255) | sim | `model` | `model` | modelo declarado |
| `category` | VARCHAR(255) | sim | `category` | taxonomia global (`taxonomy.py`) | categoria do app (nunca o slug técnico do dataset) |
| `subcategory` | VARCHAR(255) | sim | `subcategory` | taxonomia global | subcategoria do app |
| `avg_power_w` | NUMERIC | sim | `BigDecimal avgPowerW` | `Decimal \| None` | **potência média em W**; ausente → NULL, nunca estimado |
| `annual_energy_kwh` | NUMERIC | sim | `BigDecimal annualEnergyKwh` | `Decimal \| None` | **energia anual em kWh/ano**; INMETRO converte kWh/mês ×12 exatamente uma vez |

**Não pertencem ao canônico** (decisão de domínio, migração 005): `standby_power_w`, `is_generic`, tensão, energia bruta — vivem na observação. `Product.java` NÃO possui `standbyPowerW`, `isGeneric` nem campos de tensão. [CÓDIGO]

### `registry_user_product` [CÓDIGO `create.sql:100-108`; `RegistryUserProduct.java:15-36`]

| Coluna | Tipo | Nulo | Java | Unidade/Semântica |
|---|---|---|---|---|
| `id` | UUID (PK) | não | `UUID id` `GenerationType.UUID` | gerado pelo JPA |
| `user_id` | INT, FK → users | **não** | `@ManyToOne @JoinColumn(user_id, nullable=false)` | dono do registro |
| `product_id` | UUID, FK → product | **não** | `@ManyToOne @JoinColumn(product_id, nullable=false)` | produto em uso |
| `quantity` | INT | **não** | `int quantity` (primitivo) | nº de unidades idênticas; validado ≥ 1 |
| `avg_active_hours` | NUMERIC | sim | `BigDecimal avgActiveHours` | **h/dia** — estimativa do usuário; validado ∈ [0,24]; obrigatório no registro |
| `hours_standby` | NUMERIC | sim | `BigDecimal hoursStandby` | **h/dia** — opcional; ausente permanece NULL (nunca `24 − ativo`) |

`UNIQUE (user_id, product_id)` existe **no SQL**; a entidade JPA NÃO declara a constraint — a checagem de duplicidade é feita em serviço (`RegistryUserService.findByUserAndProduct`). [CÓDIGO]

### `product_source_observation` [CÓDIGO `create.sql:61-82`; `models.py:235-286`; `database.py:80-88`]

| Coluna | Tipo | Nulo | Semântica |
|---|---|---|---|
| `id` | UUID (PK) | não | uuid5 sobre `OBSERVATION|source|external_id` |
| `canonical_product_id` | UUID FK | não | âncora no produto canônico (`product.canonical_id()`) |
| `source` | VARCHAR(50) | não | `INMETRO` · `ENERGY STAR` · `WATTSIMPLE` · `CANONICAL` · `IEA` (agregados em tabela própria) |
| `external_id` | VARCHAR(255) | não | id do registro na fonte (ou dedup key) |
| `brand`, `model`, `dataset_id` | VARCHAR(255) | sim | rastreabilidade |
| `power_w` | NUMERIC ≥ 0 | sim | potência observada (W) |
| `annual_energy_kwh` | NUMERIC ≥ 0 | sim | energia anual observada (kWh/ano, já normalizada) |
| `standby_power_w` | NUMERIC ≥ 0 | sim | **potência de standby (W)** — insumo do OQ2 |
| `is_generic` | BOOLEAN NOT NULL DEFAULT FALSE | não | marca a linha como estimativa genérica (WattSimple) |
| `voltage_raw` | VARCHAR(50) | sim | declaração verbatim (`"110 V"`, `"Bivolt"`) |
| `voltage_kind` | VARCHAR(16) `unknown\|monovolt\|bivolt\|range` DEFAULT 'unknown' | não | classificação — nunca inferida por país |
| `voltage_min_v` / `voltage_max_v` | NUMERIC > 0 | sim | valores declarados em V (monovolt: min = max) |
| `raw_energy_value` | NUMERIC ≥ 0 | sim | energia **antes** da conversão |
| `raw_energy_unit` | VARCHAR(30) | sim | unidade/período original (`kWh/mês`, `kWh/ano`…) |
| `observed_at` | TIMESTAMPTZ DEFAULT now() | não | momento da observação |

`UNIQUE (source, external_id)`: mesma origem re-coletada → DO NOTHING; a observação armazenada **permanece intacta**. [CÓDIGO]

### `energy_label_class` [CÓDIGO `006:20-25`; `database.py:91-95`]

| Coluna | Tipo | Semântica |
|---|---|---|
| `id` | UUID PK FK → product | mesmo id do produto canônico |
| `label_class` | VARCHAR(10) CHECK `A+++…G` | classe ENCE declarada (INMETRO/PBE); `A+++` existe na tabela PBE real (Padrão 2022, verificado no XLSX oficial — comentário da migração) |
| `updated_at` | TIMESTAMPTZ | momento da gravação |

### `aggregate_reference` [CÓDIGO `006:28-38`; `models.py:374-412`]

| Coluna | Tipo | Semântica |
|---|---|---|
| `id` | UUID PK | uuid5 sobre `source|país|ano|metrica|aparelho` |
| `source` | VARCHAR(50) | ex. `IEA` |
| `country` | VARCHAR(100) | país do indicador |
| `ref_year` | SMALLINT ≥ 1900 | ano de referência |
| `metric` | VARCHAR(100) | ex. `stock`, `diffusion`, `energy_per_stock` |
| `appliance` | VARCHAR(100) NULL | aparelho (NULL = setor inteiro) |
| `value` | NUMERIC NOT NULL | valor |
| `unit` | VARCHAR(30) | unidade preservada (PJ, contagem, kWh…) — não convertida |

`UNIQUE (source, country, ref_year, metric, appliance)`. **Nunca vira `product`.**

## A.3 Fluxo de identidade (UUIDs determinísticos) [CÓDIGO `models.py`]

```
Produto de fonte  : uuid5(NAMESPACE_URL, "{source}|{canonical(source_id)}")
                    fallback: "{source}|{marca}|{modelo}|{dataset_category}"
Projeção canônica : uuid5(NAMESPACE_URL, "CANONICAL|{category}|{subcategory}")
Observação        : uuid5(NAMESPACE_URL, "OBSERVATION|{source}|{canonical(external_id)}")
Agregado (IEA)    : uuid5(NAMESPACE_URL, "{source}|{país}|{ano}|{métrica}|{aparelho}")
```

Canonicalização: NFKC + casefold + colapso de whitespace, separador `|` (revisão de segurança R8). ENERGY STAR preserva UUIDs **bit a bit** (o `source` da instância permanece o literal `"ENERGY STAR"`). Identidade por tensão no INMETRO: `marca|modelo|tensão` — cada (modelo, tensão) com consumo vira UMA observação. [CÓDIGO `inmetro_xlsx.py`]

## A.4 Contrato Java ↔ coletores ↔ SQL (matriz de convergência)

| Campo canônico | `Product.java` | DDL Python (`database.py` INSERT) | `create.sql` | `arquiteture.drawio` | Converge? |
|---|---|---|---|---|---|
| id UUID | ✔ l.15 | ✔ | ✔ | ✔ | ✔ |
| name VARCHAR(150) | ✔ | ✔ | ✔ | ✔ | ✔ |
| brand / model | ✔ | ✔ | ✔ | ✔ | ✔ |
| category / subcategory | ✔ l.23-24 | ✔ | ✔ l.45-46 | ✔ | ✔ |
| avg_power_w | ✔ l.25-26 | ✔ | ✔ | ✔ | ✔ |
| annual_energy_kwh | ✔ l.28-29 | ✔ | ✔ | ✔ | ✔ |
| standby (em product) | ✘ | ✘ (vai p/ observação) | ✘ | ✘ (removido) | ✔ (fora do canônico) |
| avg_idle_energy_for_hour | ✘ | ✘ | ✘ | ✘ (removido do diagrama) | ⚠ migração órfã `add_avg_idle_energy_for_hour.sql` (§A.5) |

Observação do diagrama preservada: *"Avg Active Hours represent only estimative been got for user"* (com typos no XML original). O diagrama (página única "Database") reflete `product_source_observation`, `energy_label_class`, `aggregate_reference`, `data_raw_product (in-memory)`. [CÓDIGO grep no XML]

## A.5 Divergências de schema registradas (estado atual)

| # | Divergência | Evidência | Estado |
|---|---|---|---|
| D1 | DECISÃO 003 **aplicada pela metade** (13/10/2026 15:57): `@OneToMany`, campo `registryUserProducts` e imports (`List`, `OneToMany`) removidos de `User.java`, mas `set/add/removeRegistryUserProduct` (l.45-92) sobreviveram referenciando o campo/import removidos → **compilação quebrada** (javac: `cannot find symbol: class List`, l.52) | `User.java` atual; `git diff`; javac 13/10/2026 | **PENDÊNCIA crítica de implementação** — remover os 3 métodos órfãos e corrigir callers (Fase C); baseline de testes 15:51 antecede a edição |
| D2 | Migração `add_avg_idle_energy_for_hour.sql` adiciona `product.avg_idle_energy_for_hour NUMERIC` — contradiz o contrato de 8 colunas da 005 (`product.standby_power_w/is_generic` DEPRECADOS; standby mora na observação) e a remoção do campo no diagrama | arquivo inteiro vs `005` l.13-16 | **ÓRFÃ/OBSOLETA** — não aplicar; resolução no OQ2 |
| D3 | Javadoc do hub cita `Product.avg_idle_energy_for_hour` como futura fonte de standby — campo não existe em `Product.java` | `ConsumeMetricsService.java:342-348,364-368` | Documentação dessincronizada; amarrar ao OQ2 |
| D4 | Hibernate `ddl-auto=update` evolui schema em paralelo às migrações (segunda fonte de verdade) | `application.properties` | Reconhecido; reconciliação nas fases A/G (FR-035) |
| D5 | `.env` do projeto raiz contém apenas `DB_USER` e `DB_PASSWORD` (nomes registrados; valores NÃO inspecionados) — o coletor espera `DB_URL`/`DATABASE_URL` ou `DB_HOST`/`DB_USERNAME`/`DB_PASSWORD`/`DATABASE` | `.env` (2 chaves); `config.py:189-265` | **Incompatibilidade de nomes** — coletor não conectaria com o `.env` atual; pendência de configuração (TASK-035 relacionada) |
| D6 | Sem `docker-compose.yml` no repositório — requisito "banco Docker" do briefing não é atendido por artefato existente | busca exaustiva `find -name "docker-compose*"` | **Ausência registrada**; não inventar arquivo |
| D7 | Docstrings do coletor ainda mencionam Supabase; banco real é Postgres local (`neondb`) desde o commit `c70d48e` | `config.py` docstrings; log Maven | Documentação obsoleta a atualizar (Fase G) |
| D8 | Migração 004 é subconjunto da 005 (evolução aditiva mantida por compatibilidade) — correta, mas exige ordem de aplicação | `004` vs `005` | OK (histórico); registrar ordem no runbook |
| D9 | `seed.sql` usa `ON CONFLICT (id) DO UPDATE` em `users` — aceitável em **seed de teste** (não é o pipeline de ingestão), mas contrasta com a política INSERT-only do coletor | `seed.sql:10-13` | OK com nota; não estender a produção |
| D10 | Registry calculado por thresholds no seed antigo (16/8/4 h por potência) vs. hoje estimativa do usuário — dados legados podem ter horas inconsistentes (ex.: 316,12 h/dia no `neondb`) | `seed.sql:34-49`; DECISÃO 006 | Tratado pela exclusão de inconsistentes dos agregados; limpeza de dados = TASK-029 |

## A.6 Contratos entre entidades, DTOs, repositórios, serviços e endpoints (resumo)

| Camada | Artefato | Contrato (resumo) |
|---|---|---|
| Repositório | `ProductRepository` | `searchByTerm` (5 campos, LOWER LIKE), `findByBrand/Category/Model...`, paginação via `PageRequest` |
| Repositório | `RegistryUserProductRepository` | `findByUser(User)`, `findByUserAndProduct`, `countByUser`, variações de filtro |
| Repositório | `UserRepository` | `findByName*`, `existsByName`, CRUD padrão (PK Integer) |
| Serviço | `RegistryUserService` | `registerUserProduct(ProductForRegistry)` — resolve/valida/duplicidade/salva; `createRegistry` @Deprecated delegante |
| Serviço | `ConsumeMetricsService` (hub) | 8 métodos de `MetricsService` (ver Apêndice B §B.1) |
| Serviço | `HourService` | `totalDailyHours(active, standby)` / `(RegistryUserProduct)` — Hday = Hactive + Hstandby |
| Serviço | `TariffService` | `getReferenceTariff(LocalDate)` → `TariffQuote` |
| Conversor | `ProductForRegistryConverter` | DTO→entidade puro, sem derivação, PK por conta do JPA |
| Controller | `RegistryUserProductController` | `POST /registryUserProducts` (@Valid) → 200 entidade; `GET /user/{userId}` → lista |
| Controller | `MetricsController` | 5 POSTs de métricas + `GET /search/{userId}` |
| Controller | `ProductController` | `GET /products?search=&size=` |
| Controller | `AuthController` | `POST /auth/login` · `POST /auth/logout` |
| DTO entrada | `ProductForRegistry`, `MetricsByUserDTO`, `MetricsStandbyByProductDTO`, `LoginDTO` | records com Bean Validation |
| DTO saída | `ResultDTO`, `SearchResponseDTO` | records; `ResultDTO` contém `List<RegistryUserProduct>` (ver FR-026) |

Fluxo de criação de registro (pensado e implementado): `POST /registryUserProducts` → `RegistryUserService.registerUserProduct` → resolve `User`/`Product` por id → valida faixas → checa duplicidade → `ProductForRegistryConverter.toEntity` → `save`. [CÓDIGO]
