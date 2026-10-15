# Unidades do frontend — módulo `units.js`

> Módulo: `src/main/resources/static/units.js` (`window.Units`)
> Documenta o comportamento implementado (código como fonte de verdade),
> verificado pela leitura do módulo, do `app.js` e pela execução do smoke
> test.

---

## 1. Propósito

Único lugar do frontend onde unidades de grandezas são escritas para
exibição:

| Grandeza | Unidade | Função |
|---|---|---|
| Potência | `W` | `Units.formatPowerW` |
| Voltagem/tensão | `V` | `Units.formatVoltage` |
| Energia | `kWh` (pt-BR) | `Units.formatEnergyKwh` |
| Tempo de uso | `h/dia` | `Units.formatHoursPerDay` |
| Custo | `R$` (pt-BR, `Intl`) | `Units.formatBrl` |
| Números pt-BR | base | `Units.formatNumberPtBR` |

Objetivo: terminologia centralizada — nenhuma formatação de unidade espalhada
pelo código de UI.

---

## 2. Carregamento e integração

- `index.html` carrega `<script src="/units.js"></script>` **antes** de
  `<script src="/app.js"></script>` (sem bundler/ES modules — padrão vanilla
  do projeto; o módulo IIFE congela e expõe `window.Units`).
- Há um guard `module.exports` no fim do módulo para permitir carregá-lo no
  Node (é o que viabiliza o smoke test sem dependências).

### Migração no `app.js` — 4 pontos de exibição (7 chamadas)

| Ponto de exibição | Função no `app.js` | Chamadas |
|---|---|---|
| Potência no nome do produto | `formatProduct` | `Units.formatPowerW(product.avgPowerW)` |
| Horas ativo/standby no detalhe de registro | `formatRegistryDetails` | `Units.formatHoursPerDay` ×2 |
| Consumo diário/anual no resultado | `renderCalculationResult` | `Units.formatEnergyKwh` ×2 |
| Gasto por dia/ano (R$) no resultado | `renderCalculationResult` | `Units.formatBrl` ×2 |

Alterações associadas no `app.js`:

- `brlFormatter` (Intl pt-BR BRL local) foi **removido** — a formatação
  monetária agora é só `Units.formatBrl`;
- linhas de consumo kWh **sem valor formatado são puladas** (evita label
  órfão com string vazia na lista de resultados);
- linhas de horas vazias continuam omitidas pelo mesmo padrão (`''` → filtrado).

---

## 3. Contrato das funções

`parseNumber` (interno): aceita `number`, string numérica com ponto
(`"150.00"`), vírgula pt-BR (`"62,50"`) e milhar+decimal pt-BR
(`"1.032,5"` → `1032.5`). Inválido/ausente → `null`.

| Função | Comportamento | Ausente/inválido |
|---|---|---|
| `formatNumberPtBR(value, {maxFractionDigits})` | base pt-BR, `maxFractionDigits` default 3 | `''` |
| `formatPowerW(value)` | `150` → `'150 W'`; `'62.50'` → `'62,5 W'`; ≤2 casas | `0`, negativo, `null` → `''` (zero/negativo nunca exibidos) |
| `formatVoltage(voltage)` | ver §4 | `''` |
| `formatEnergyKwh(value, period)` | 3 casas decimais; `period` `'dia'`/`'ano'` → sufixo `kWh/dia`/`kWh/ano`; outro → `kWh` | `''` |
| `formatHoursPerDay(value)` | 1 casa decimal quando fracionário: `8` → `'8 h/dia'`, `8.5` → `'8,5 h/dia'`; **zero declarado é exibido** (`'0 h/dia'`) | `null`/`undefined` → `''` |
| `formatBrl(value)` | idêntico a `Intl.NumberFormat('pt-BR', {style:'currency', currency:'BRL'})` | `''` |

O objeto exportado é `Object.freeze(...)` — API imutável.

---

## 4. Regras de voltagem (`formatVoltage`)

Espelha `energy_collector/collector/voltage.py`. Regras **fechadas**:

- **NUNCA converter tensão**: `110 V` não vira `127 V` (sem fator algum);
- **NUNCA inferir tensão ausente**: `unknown`/nulo → `''` (não deduzir por
  país/categoria);
- unidade sempre `V` maiúsculo; valores exibidos como inteiros.

Entradas e formatos:

| Entrada | Saída |
|---|---|
| `127` (number/string numérico) | `'127 V'` |
| `{kind:'monovolt', minV:110, maxV:110}` | `'110 V'` (nunca 127) |
| `{kind:'bivolt', minV:110, maxV:220}` | `'110/220 V'` |
| bivolt com números incompletos ou ausentes | `'Bivolt'` (preserva o fato bivolt; `raw` **nunca** é exibido) |
| bivolt completo com par igual | `'110 V'` |
| `{kind:'range', minV:100, maxV:240}` | `'100-240 V'` |
| `{kind:'unknown'}` ou entrada nula | `''` |
| string não numérica (`'127 V'`) | `''` |

### Status: pronto, porém INATIVO

`formatVoltage` está implementado e testado, mas **não é chamado por
nenhum ponto de exibição do `app.js`**: o backend não expõe tensão — busca
em `src/main/java` por `voltage`/`tensão` não retorna nenhuma ocorrência
(`Product` não tem campo de tensão; a tensão vive em
`product_source_observation.voltage_*`, sem entidade JPA/endpoint). A função
fica pronta para quando o backend expor o dado; expor endpoint/DTO é decisão
do DEV.

---

## 5. Smoke test

```bash
node scripts/unit_tests/units_smoke_test.js
```

- Node puro, sem dependências e sem `package.json` (faz
  `require('../../src/main/resources/static/units.js')`);
- **27 casos** cobrindo as 6 funções — inclusive os casos de regra
  (`110 V` nunca vira `127 V`, `raw` nunca exibido, zero em `h/dia` exibido,
  `formatBrl` igual ao `Intl` pt-BR BRL);
- imprime `units_smoke_test: <passed>/<total> casos passaram` e sai com
  **exit code 1** se algum caso falhar.

Resultado da última execução neste trabalho documental:
`units_smoke_test: 27/27 casos passaram` (exit 0).

---

## 6. Relação com os demais artefatos

- Fonte da especificação original:
  `.agents/specs/spec-docker-postgres-frontend-units.md` (Task 2).
- Semântica de voltagem: `energy_collector/collector/voltage.py`.
- Semântica de consumo: `docs/data_normalizate.md` (fórmulas de energia).
