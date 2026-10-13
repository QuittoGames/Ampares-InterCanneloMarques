# Apêndice C — Registro de Fontes Externas e Precedência

**Spec principal**: [spec.md](spec.md) · **Data de execução das consultas**: 2026-10-13 · Estados de evidência conforme legenda da spec.

Regra da spec: fontes tarifárias, formatos de exportação, APIs e datasets **mudam** — toda afirmação externa carrega a data da consulta e deve ser revalidada em execuções futuras.

## C.1 Registro de fontes

### C.1.1 Fonte primária — INMETRO/PBE (Brasil) — TIER PRIMARY

| Campo | Registro |
|---|---|
| Nome/Proprietário | Sistema PBE — Instituto Nacional de Metrologia, Qualidade e Tecnologia (INMETRO) |
| Portal | https://pbe.inmetro.gov.br/ (não consultado nesta execução — sem API REST pública conhecida) |
| Tabelas oficiais | http://www.inmetro.gov.br/CONSUMIDOR/pbe/ (páginas `.asp` por categoria) |
| **Transporte verificado** | **XLSX** `Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx` — **HTTP 200 OK** em 13/10/2026 (curl -sI; Content-Type `application/octet-stream`, servidor IIS) |
| Estrutura (verificada no parser) [CÓDIGO `inmetro_xlsx.py`] | `FORNECEDOR \| MARCA \| MODELO \| TIPO DE PRODUTO \| SISTEMA DE DEGELO \| AGENTE DE EXPANSÃO DA ESPUMA \| Nº DE REGISTRO \| VOLUME INTERNO (l) \| CONSUMO DE ENERGIA (kWh/mês) → 127 V / 220 V / VA` + faixas de classificação (Padrões 2015/2022) por tensão; versão do arquivo informada no próprio XLSX (ex. 12/11/2021) |
| Campos usados | marca, modelo, registro (certificado — não usado como identidade), consumo kWh/mês por tensão, classe ENCE (A+++…G) |
| Unidade/período | **kWh/mês** → `annual_energy_kwh` com ×12 **exatamente uma vez**; coluna **VA ignorada** (potência aparente ≠ energia) |
| Tensão | cada (modelo, tensão) vira UMA observação com a tensão ORIGINAL; sem conversão |
| Frequência/atualização | XLSX versionado; cadência a decidir (TODO.md TASK-036) |
| Limitações | sistema interativo PBE sem API pública REST; algumas categorias só em PDF; versão do arquivo pode defasar; escopo atual = refrigeradores e assemelhados (Portaria INMETRO 736/2024, categorias 1–6) |
| Adapter/Testes | `sources/inmetro.py` + `sources/inmetro_xlsx.py`; `tests/test_inmetro.py`, `tests/test_inmetro_xlsx.py`, `tests/test_brazil_normalization.py` (offline, fixtures) |

**Status da integração**: transporte real implementado e registrado no CLI (`--source inmetro`) [CÓDIGO `registry.py:72-90`]. **Não se afirma** que o sistema interativo é API.

### C.1.2 Referência regulatória — tarifa (Enel SP / ANEEL)

| Campo | Registro |
|---|---|
| Nome/Proprietário | Enel Distribuição São Paulo (concessionária); ANEEL (reguladora) |
| URL consultada | https://www.enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html — **13/10/2026** |
| Dado confirmado [FONTE] | "TARIFAS ... RESOLUÇÃO HOMOLOGATÓRIA Nº 3.596/2026 de 30/06/26 DA ANEEL — **VÁLIDAS A PARTIR DE 04/07/26**"; B1 RESIDENCIAL: **TUSD 472,42 R$/MWh + TE 316,96 R$/MWh** (= 789,38); tabela Grupo B (baixa tensão) também exibe 789,38 R$/MWh para RESIDENCIAL B1 |
| Componentes incluídos/excluídos | Inclui TUSD+TE (convencional). **Exclui**: impostos, bandeiras tarifárias (seção própria na página), iluminação pública (B4a/B4b distintos), serviços, valores mínimos mensais, Tarifa Social |
| Modalidade Branca | Publicada com postos ponta/intermediário/fora de ponta (valores distintos) — o Ampares usa CONVENCIONAL [CÓDIGO `TariffProperties`] |
| Vigência fim | **Não publicada**; `validUntil = 2027-07-03` é projeção do ciclo anual (histórico de resoluções jun/jul na própria página) [HIPÓTESE] |
| Outras referências | ANEEL ranking: https://www.gov.br/aneel/pt-br/assuntos/tarifas (referenciada pela própria página Enel; **não consultada nesta execução** — limitação registrada); Enel RJ: https://www.enel.com.br/pt/Tarifas_Enel.html (**não consultada** — nunca misturar distribuidoras) |
| Histórico de migração | Referência anterior: Enel **Rio** (1061,10 R$/MWh, vigência 2026-03-15…2027-03-14) — origem do rascunho 1550,41 do OQ1; migrada em 13/10/2026 [DECISÃO DEV registrada na spec predecessora] |
| Adapter/Testes | `TariffProperties`/`TariffService`/`TariffQuote`; `TariffServiceTest` (10 testes). **Sem atualização dinâmica** — validação temporal de valor configurado |

### C.1.3 Fonte secundária internacional — ENERGY STAR / Socrata — TIER FOREIGN

| Campo | Registro |
|---|---|
| Nome/Proprietário | U.S. EPA — programa ENERGY STAR; plataforma Socrata (`data.energystar.gov`) |
| Catalog API | https://api.us.socrata.com/api/catalog/v1 — **consultada 13/10/2026** |
| Datasets confirmados ao vivo (todos retornados com `provenance: official`) | `p5st-her9` Refrigerators · `pd96-rr3d` Televisions · `rxdj-2c88` Computers · `bghd-e2wd` Clothes Washers |
| Campos confirmados [FONTE+CÓDIGO `config.py:75-104`] | `p5st-her9`: `annual_energy_use_kwh_yr` (sem potência on-mode). `pd96-rr3d`: `reported_annual_energy_consumption_kwh` + `power_consumption_in_on_mode_watts` + **`measured_standby_mode_power_w`**, `power_consumption_in_standby_mode_when_network_(not_)connected_watts`, `reported_standby_active_low_mode_power_watts`. `rxdj-2c88`: `tec_of_model_kwh`. `bghd-e2wd`: `annual_energy_use_kwh_year` (correção TASK-008 validada contra coluna real) |
| Unidades | kWh/ano (anual); watts (potências); **não** são W nem kWh/mês — não confundir |
| Condições de ensaio | ex.: lavadoras = 295 ciclos/ano (descrição do dataset); TVs via CTA-2037C/AEC — condições da fonte, não do usuário |
| Identificadores | `pd_id` (ENERGY STAR Unique ID), `energy_star_model_identifier`, `model_number` |
| Limite/JSON | acesso anônimo; `SOCRATA_APP_TOKEN` opcional [CÓDIGO `config.py:286-289`]; rate limiter no client |
| Limitações | especificação americana/Canada markets — **nunca** apresentar como equivalente brasileiro; sem tensão; sem cruzamento fuzzy com INMETRO (D7=A) |
| Adapter/Testes | `sources/energy_star.py` (wrapper 1:1 sobre `SocrataClient`), `services/socrata_service.py`; `tests/test_socrata_service.py`, `tests/test_multi_source.py` (mocks/fixtures) |

### C.1.4 Fonte estatística — IEA — TIER AGGREGATE (fora do CLI)

| Campo | Registro |
|---|---|
| Nome/Proprietário | International Energy Agency |
| Produtos | Household Appliances Database (pilot, XLSX gratuito; stock/difusão/penetração, 100+ países, atualização ~2×/ano); Energy End-uses and Efficiency Indicators (PJ/indicadores) |
| URLs | https://www.iea.org/data-and-statistics/data-product/household-appliances-database · https://www.iea.org/data-and-statistics/data-product/energy-end-uses-and-efficiency-indicators (**não consultadas nesta execução**) |
| Uso no sistema | Cada linha → `AggregateRecord` → tabela `aggregate_reference` (país/ano/métrica/aparelho/valor/unidade) — **nunca** produto individual [CÓDIGO `iea.py`; `006`] |
| Estado | Adapter implementado com testes (`tests/test_iea.py`), porém **não registrado no CLI** (`sources/registry.py:95-99`) até o workbook real ser verificado [CÓDIGO docstring] |
| Limitações | indicadores agregados com lacunas temporais/nacionais; unidades preservadas sem conversão (PJ permanece PJ) |

### C.1.5 Fonte genérica — WattSimple — TIER GENERIC

| Campo | Registro |
|---|---|
| Nome/Proprietário | WattSimple (referência de potência típica por aparelho) |
| URL | Página https://www.wattsimple.com/data · CSV https://www.wattsimple.com/data/appliance-wattage/csv |
| Disponibilidade na consulta | **HTTP 429 (challenge Vercel/bot mitigation) em 13/10/2026** — fonte **instável** para ingestão automatizada; tratamento: fixtures offline nos testes, erro isolado por fonte |
| Escopo confirmado (doc interna [CÓDIGO `data-sources.md`]) | 143 registros; valores **típicos**, não medições universais; licença CC BY 4.0 com atribuição |
| Campos oficiais | `appliance`, `category`, `running_watts`, `starting_watts`, `typical_hours_per_day` |
| Mapeamento | `running_watts` → `avg_power_w`; `starting_watts`/`typical_hours_per_day` preservados como raw (não são potência média/consumo); `is_generic=True` |
| Regras | sem marca/modelo fictício; sem misturar médias genéricas com modelos identificados; identidade `WATTSIMPLE\|{nome}` |
| Adapter/Testes | `sources/wattsimple.py`; `tests/test_wattsimple.py` |

## C.2 Precedência e reconciliação [CÓDIGO `precedence.py`; `data-sources.md`]

1. **TIER PRIMARY** — modelo brasileiro identificado (INMETRO/PBE; futuras fontes oficiais de fabricante registradas em `PRIMARY_BR_SOURCES` = `{INMETRO}`). Única elegível para as métricas da projeção canônica (`is_canonical_eligible`: fonte primária E `is_generic=False`).
2. **TIER FOREIGN** — especificação estrangeira identificada (`ENERGY STAR`): preservada como observação/referência; nunca sobrescreve especificação brasileira; nunca misturada em média.
3. **TIER GENERIC** — estimativa de categoria (`WATTSIMPLE`, `is_generic=True`): fallback claramente rotulado, se a aplicação permitir usá-lo.
4. **TIER AGGREGATE** — estatística contextual (`IEA`): nunca registro de aparelho individual.
5. **UNKNOWN** — fonte não registrada: tratamento conservador (não contribui até o DEV classificar — decisão de política, não do coletor).

**Agregação canônica** (`merge_products`, [CÓDIGO `models.py:306-371`]): por grupo `category|subcategory`, cada métrica = média aritmética dos membros elegíveis com valor não-nulo; só agregam valores com unidade/período/domínio comparáveis (ingestão já entrega W e kWh/ano); sem elegível → `NULL`; registro canônico criado mesmo sem métricas (âncora das observações); `label_class` só de elegíveis. **Sem merge fuzzy** entre países/modelos/fontes incompatíveis; IDs externos e procedência preservados.

## C.3 Fontes mencionadas no briefing — status de verificação nesta execução

| Fonte | URL | Status (13/10/2026) |
|---|---|---|
| PBE portal | https://pbe.inmetro.gov.br/ | Não consultada (sem API conhecida); XLSX oficial verificado 200 OK |
| PBE consulta produtos (gov.br) | página gov.br condicionadores | Não consultada — escopo atual refrigeradores |
| ANEEL ranking tarifas | https://www.gov.br/aneel/pt-br/assuntos/tarifas/ranking-das-tarifas | **Não consultada** (limitação) — tarifa primária verificada na página Enel SP |
| Enel SP tarifas | https://www.enel.com.br/pt-saopaulo/Para_Voce/tarifa-energia-eletrica.html | **VERIFICADA** — Resolução 3.596/2026, TUSD 472,42 + TE 316,96 |
| Enel RJ tarifas | https://www.enel.com.br/pt/Tarifas_Enel.html | Não consultada (fontes distintas — nunca misturar) |
| ENERGY STAR data / Socrata catalog | https://data.energystar.gov/ · https://api.us.socrata.com/api/catalog/v1 | **VERIFICADAS** — 4 datasets + campos confirmados |
| IEA (2 produtos) | iea.org (2 URLs) | Não consultadas; adapter fora do CLI |
| NIST Guide SI (Wh/kWh/J) | https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b9 | Não consultada — conversões usadas (÷1000, ×12, ×365) são definições padrão de unidade, hipótese segura [HIPÓTESE] |
| Spec Kit specify template | https://github.com/github/spec-kit/blob/main/templates/commands/specify.md | Não consultada — template real usado: `.specify/templates/spec-template.md` local (CLI 1.1.3 instalado e inicializado nesta execução) |
