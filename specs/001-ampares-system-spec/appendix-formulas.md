# Apêndice B — Catálogo de Fórmulas (Formula Bank) com derivação e unidades

**Spec principal**: [spec.md](spec.md) · **Data**: 2026-10-13 · Estados de evidência conforme legenda da spec.

Convenções globais do motor [CÓDIGO `ConsumptionCalculator.java:62-86`]:
- `DAYS_PER_YEAR = 365` (ano de 365 dias, sem bissexto); `MONTHS_PER_YEAR = 12` (mês médio = ano/12); `WATTS_PER_KILOWATT = 1000`.
- Precisão interna `MathContext.DECIMAL128` (34 dígitos); arredondamento monetário `HALF_UP` com 2 casas **somente na saída** (`MONETARY_SCALE = 2`); escala de horas derivadas `HOUR_SCALE = 4`; escala de médias `AVG_SCALE = 6` (hub).
- Sempre `BigDecimal`; `double/float` proibidos em domínio monetário.

## B.1 B.1 Derivação física base

Potência média é energia por unidade de tempo:

$$P_{\mathrm{méd}}=\frac{\Delta E}{\Delta t}$$

Isolando a energia (para potência constante):

$$\Delta E = P_{\mathrm{méd}}\cdot\Delta t$$

A multiplicação surge da definição: potência constante ⇒ energia acumulada cresce linearmente com o tempo. Se a potência variar, a forma geral é $E=\int P(t)\,dt$ ou a soma por intervalos (modelo multi-modo documentado em `docs/data_normalizate.md`, alinhado ao ENERGY STAR: $E_{\text{ano}}=\frac{1}{1000}\sum_i P_i H_i$ com $\sum_i H_i = 8760$ h).

Análise dimensional: $W \times h = Wh$; $1000\,Wh = 1\,kWh$; o fator 1000 é **conversão de unidade**, não ajuste empírico. Multiplicar por quantidade $q$ equivale a somar $q$ unidades idênticas.

## B.2 Catálogo de fórmulas implementadas [CÓDIGO]

### F1 — Consumo diário personalizado (kWh/dia)

$$E_{\mathrm{dia,kWh}}=\frac{P_W\cdot h_{\mathrm{dia}}\cdot q}{1000}$$

- Implementação: `ConsumptionCalculator.dailyKwh(powerW, hoursPerDay, quantity)` (l.117-124). Hub: `calculateDailyKwh(r)` (l.128-133) com $q$ de `getQuantity()`.
- Variáveis: $P_W$ potência média ativa (W), $h_{\mathrm{dia}}$ horas/dia do perfil, $q$ quantidade (unidades).
- Validações: $P_W > 0$; $h_{\mathrm{dia}}\in[0,24]$; $q\ge 1$; `null` → `InputValidationException`.
- Ausência nunca vira zero silencioso nos métodos novos; métodos **legados** (`calculate(userProduct, hoursProvider)`, l.414-435) preservam `null→ZERO` por compatibilidade — marcados LEGADO.
- Teste: `ConsumptionCalculatorTest` — Cenário A (21 testes) e Cenário B (3).
- Exemplo: $200\,W \times 5\,h \times 2 = 2000\,Wh = 2\,kWh/dia$.

### F2 — Consumo anual a partir do diário (kWh/ano)

$$E_{\mathrm{ano,kWh}}=E_{\mathrm{dia,kWh}}\cdot 365=\frac{P_W\cdot h_{\mathrm{dia}}\cdot q\cdot 365}{1000}$$

- Implementação: `annualKwh(dailyKwh)` (l.176-179); hub `calculateAnnualKwh(r)` (l.146-148).
- Hipótese: uso diário constante ao longo do ano (estimativa, não medição).
- Teste: Cenário A → 365 kWh/ano; Cenário B → 1460 kWh/ano. ✓ (verdes)

### F3 — Consumo mensal

$$E_{\mathrm{mês}}=E_{\mathrm{dia}}\cdot d_{\mathrm{mês}} \qquad\text{e}\qquad E_{\mathrm{mês,médio}}=\frac{E_{\mathrm{ano}}}{12}$$

- Implementação: `monthlyKwh(daily, daysInPeriod)` (l.138-144, $d_{\mathrm{mês}}\ge 1$) e `averageMonthKwh(annual)` (l.160-163).
- A aproximação por mês médio **só** é válida rotulada como média ($365/12$ dias); não equivale a um mês real.
- Teste: `ConsumptionCalculatorTest` (mês médio vs período explícito).

### F4 — Energia anual declarada pela fonte (kWh/ano) — camada separada

$$E_{\mathrm{ano,ref}}=E_{\mathrm{anual,fonte}}\cdot q \qquad E_{\mathrm{dia,ref}}=\frac{E_{\mathrm{ano,ref}}}{365} \qquad E_{\mathrm{mês,ref}}=\frac{E_{\mathrm{ano,ref}}}{12}$$

- Implementação: `sourceAnnualKwh`, `sourceDailyKwh`, `sourceAverageMonthKwh` (l.200-242).
- **PROIBIDO** anualizar novamente ($\times 365$ sobre dado já anual) — [DECISÃO 004] e camada separada com comentário explícito no código (l.184-186).
- Especificações anuais refletem condições de ensaio da fonte (ex.: ENERGY STAR usa 295 ciclos/ano para lavadoras [FONTE 13/10/2026, descrição do dataset `bghd-e2wd`]) — não o perfil real do usuário.
- Os dois conceitos (**estimativa personalizada** vs **referência da fonte**) nunca são somados/trocados silenciosamente; fallback só com rótulo explícito.

### F5 — Custo (R$)

$$C_{R\$}=E_{kWh}\cdot T_{R\$/kWh} \qquad\qquad T_{R\$/kWh}=\frac{T_{R\$/MWh}}{1000}$$

- Implementação: `cost(kwh, tariffPerKwh)` (l.264-269, HALF_UP 2 casas) e conversão em `TariffService.getReferenceTariff` (l.68-70, `MWH_TO_KWH_DIVISOR = 1000`, DECIMAL128).
- Consumo e tarifa devem compartilhar o mesmo período. A tarifa de referência não é a fatura completa (sem impostos/bandeiras/iluminação pública — ver [Apêndice C](appendix-sources.md) §C.2).
- Teste: 1460 kWh × 0,78938 R$/kWh = 1152,49480 → **1152,49** (HALF_UP) — `TariffServiceTest:116-132`.

### F6 — Standby (modo espera)

$$E_{\mathrm{standby,dia,kWh}}=\frac{P_{\mathrm{standby,W}}\cdot h_{\mathrm{standby,dia}}\cdot q}{1000}\qquad E_{\mathrm{standby,ano}}=E_{\mathrm{standby,dia}}\cdot365\qquad C_{\mathrm{standby,ano}}=E_{\mathrm{standby,ano}}\cdot T$$

- Implementação: `standbyDailyKwh` / `standbyAnnualKwh` / `standbyAnnualCost` (l.294-347); $P_{\mathrm{standby}}=\mathrm{null}$ → `Optional.empty()` (indisponível, nunca zero, nunca $P$ ativa).
- **PROIBIDO** usar `avgPowerW` como standby [CÓDIGO comentários + DECISÃO 004].
- No hub, as métricas de standby retornam `Optional.empty()` **enquanto** não houver potência de standby confiável (OQ2): `ConsumeMetricsService.java:354-381`.
- Nota de insumo: o dataset ENERGY STAR de TVs expõe `measured_standby_mode_power_w` e `power_consumption_in_standby_mode_when_(network_)connected_watts` [FONTE 13/10/2026] — candidato a insumo por observação, não por campo canônico, até decisão do OQ2.

### F7 — Horas equivalentes inferidas (inversa) — condicional

$$h_{\mathrm{dia}}=\frac{E_{\mathrm{ano,kWh}}\cdot 1000}{P_W\cdot q\cdot 365}$$

- Implementação: `inverseDailyHours(annualKwh, powerW, quantity)` (l.376-389) — exige $P_W>0$, $q\ge1$; resultado fora de $[0,24]$ → `Optional.empty()` (nunca trunca em 24); escala 4.
- Legado: `calculateDailyActiveHours(avgPowerW, annualEnergyKwh)` (l.461-480) **não inclui** $q$ e não valida [0,24] — divergência documentada; usar apenas para o caller legado `RegistryUserService` até absorção [DECISÃO 001].
- Port Python original: `compute_equivalent_hours_year(_day)` (`docs/data_normalizate.md`; `RegistryCalculator` @Deprecated espelha).
- Só usar quando energia anual e potência representarem **o mesmo modelo/condições/unidades**.

### F8 — Horas totais do dia [DECISÃO 005]

$$H_{\mathrm{day}} = H_{\mathrm{active}} + H_{\mathrm{standby}}$$

- Implementação: `HourService.totalDailyHours(...)` (l.60-101). Componente `null` → `Optional.empty()`; componente negativo/>24 → exceção; soma >24 → `InputValidationException` (sem clamp).
- Testes: `HourServiceTest` (13 testes: soma válida, null→empty, componente fora da faixa, soma >24).

### F9 — Agregações e ranking [CÓDIGO `ConsumeMetricsService`]

$$E_{\mathrm{total}}=\sum_{i=1}^{n}E_i \qquad \bar{E}_{\mathrm{registro}}=\frac{\sum E_i}{n_{\mathrm{válidos}}} \qquad \bar{E}_{\mathrm{unidade}}=\frac{\sum E_i}{\sum q_i} \qquad \text{mais consumidor}=\arg\max_i E_i$$

- Total: soma dos válidos, sem arredondamento forçado (l.220-226). Média **por registro**: Σ anual ÷ nº de registros válidos, escala 6 HALF_UP (l.208-216, l.266-283). Média por unidade física: métrica **distinta** (não implementada; nome explícito obrigatório se criada).
- Ranking: `max(Comparator.comparing(...calculateDailyKwh))` (l.302-305) — busca linear máxima, **não** binária (lista não ordenada). Categoria: `equalsIgnoreCase` + sort DESC (l.322-337). Empate: vence o primeiro na ordem do stream (definir/testar).
- Filtro de elegibilidade: `hasComputableActiveInputs` (l.104-114) — presença + tentativa `calculateDailyKwh` com catch → exclui inconsistente dos agregados sem derrubar os demais [DECISÃO 006].
- `getProductsRegistrys` → lista possivelmente vazia, nunca exceção por zero linhas (l.395-398).
- `avg(BigDecimal, List<?>)` (l.421-445): guarda de validade + soma apenas de elementos `Number` via `BigDecimal`; contagem = elementos somados; limitação do curinga registrada [DECISÃO 004 OQ].

## B.10 — Tabela-resumo (unidades e implementação)

| # | Métrica | Fórmula (unidades) | Método Java | Unidade de saída | Estado |
|---|---|---|---|---|---|
| F1 | Consumo diário | $P\cdot h\cdot q/1000$ | `dailyKwh` | kWh/dia | Implementado + testes |
| F2 | Consumo anual | $E_d\cdot365$ | `annualKwh` | kWh/ano | Implementado + testes |
| F3 | Mensal | $E_d\cdot d$ / $E_a/12$ | `monthlyKwh` / `averageMonthKwh` | kWh/mês | Implementado |
| F4 | Fonte anual | $E_{a,fonte}\cdot q$ (nunca ×365) | `sourceAnnualKwh` + derivadas | kWh/ano, kWh/dia, kWh/mês | Implementado |
| F5 | Custo | $E\cdot T_{R\$/kWh}$ | `cost` / `TariffService` | R$ (2 casas) | Implementado + testes |
| F6 | Standby | $P_{sb}\cdot h_{sb}\cdot q/1000$ (×365 p/ ano) | `standbyDaily/Annual/Cost` | kWh/dia, kWh/ano, R$/ano | Motor pronto; hub → `empty()` (OQ2) |
| F7 | Horas equivalentes | $E_a\cdot1000/(P\cdot q\cdot365)$ | `inverseDailyHours` | h/dia (escala 4) | Implementado + legado divergente |
| F8 | Horas do dia | $H_a+H_{sb}$ | `HourService` | h/dia | Implementado + testes |
| F9 | Agregações | Σ, média, argmax | hub (streams) | kWh (período explícito) | Implementado + testes |

## B.11 — Casos-limite obrigatórios (cobertura de teste)

1. 200 W × 5 h/dia × 2 = **2 kWh/dia** e **730 kWh/ano** (hipótese 365 dias). ✓ verde
2. 1000 W × 2 h/dia × 2 = 4 kWh/dia → 1460 kWh/ano → **R$ 1152,49** (OQ1). ✓ verde
3. Valor anual da fonte **não** é anualizado novamente. ✓ (camada fonte separada)
4. kWh/mês → kWh/ano **somente** com ×12 quando a fonte declara mensal (INMETRO). ✓ (`test_inmetro*`)
5. Quantidade vs soma de unidades distintas. ✓
6. Média por registro ≠ média por unidade física. ✓ (javadoc + testes do hub)
7. Potência/horas nulas, negativas, fora de [0,24] → erro explícito / exclusão do agregado. ✓
8. Standby nunca usa potência ativa. ✓ (`Optional.empty()`)
9. R$/MWh → R$/kWh (÷1000) e custo do mesmo período. ✓
10. Vigência: início/fim inclusivos, antes, depois, ausente/incoerente → VALID/OUTDATED. ✓
11. Lista vazia / `Optional` / máximo / empates / filtro de categoria. ✓
12. FK, duplicidade user-product, UUID/Integer, integridade após conclusão da DECISÃO 003 (remoção do `@OneToMany`/campo feita em 13/10; métodos órfãos de `User` pendentes — D1) [ALVO].
13. Conflito no coletor não atualiza nem apaga; ingestão sem DDL. ✓ (`test_database.py`)
14. INMETRO ausente/inválido, registro estrangeiro, produto genérico, observação não comparável. ✓
15. Tensão 110/127/220/bivolt/faixa preservada sem conversão. ✓ (`voltage.py` + `test_brazil_normalization`)
16. Re-coleta idempotente; falha de fonte não limpa dados existentes. ✓

## B.12 — OQ1: divergência numérica tarifária (rastreabilidade completa)

**Entradas do caso (Cenário B)** [CÓDIGO tests + spec predecessora]:
- Energia: $E_{\mathrm{ano}} = 1460$ kWh (1000 W × 2 h/dia × 2 unidades × 365 dias ÷ 1000).
- Tarifa: `publishedValuePerMwh = 789.38` R$/MWh (Enel **SP**, B1 residencial convencional, TUSD 472,42 + TE 316,96 — Resolução Homologatória ANEEL nº 3.596/2026, vigentes a partir de 04/07/2026 [FONTE 13/10/2026]).
- Conversão: 789,38 ÷ 1000 = 0,78938 R$/kWh.
- Cálculo: $1460 \times 0{,}78938 = 1152{,}49480$ → HALF_UP 2 casas → **R$ 1152,49**.

**Origem do rascunho (1550,41)**: escrito quando a referência era a **Enel Rio** (1061,10 R$/MWh ⇒ 1,06110 R$/kWh; 1460 × 1,06110 = 1549,21; o 1550,41 implica tarifa ≈ 1,06193 R$/kWh). A referência foi migrada para Enel SP em 13/10/2026 (revisão registrada na spec predecessora). Diferença = **migração de fonte tarifária**, não erro de fórmula.

**Semântica do valor configurado (resposta ao ponto de precisão do briefing)**: `publishedValuePerMwh` = **TUSD + TE** da classe B1 residencial convencional publicadas pela distribuidora — verificadо na página oficial da Enel SP em 13/10/2026 (a tabela "B1 - RESIDENCIAL" lista exatamente 472,42 e 316,96 R$/MWh). **Exclui**: impostos (ICMS/PIS/COFINS), bandeiras tarifárias, iluminação pública, serviços e valores mínimos mensais — a página os trata em seções próprias. Logo, o custo do Ampares é **estimativa de energia (TUSD+TE)**, rotulada como referência, nunca fatura completa.

**Reprodução**: `TariffServiceTest` ("arredondamento: 1460 kWh × 0.78938 = 1152.49480 → HALF_UP 2 casas = 1152.49") e `ConsumptionCalculatorTest` ("cost anual"). Ambos verdes em 13/10/2026.

**Decisão pendente ao DEV**: aceitar formalmente 1152,49 como resultado canônico do cenário (OQ1 na spec principal). A matemática não deve ser alterada para igualar o rascunho.
