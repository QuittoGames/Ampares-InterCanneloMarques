# Fontes de dados de produtos e energia

## Modelo operacional

O coletor mantém quatro conceitos separados:

- `Product`: registro normalizado recebido de uma fonte durante o pipeline.
- produto canônico: projeção global por tipo de aparelho, persistida na tabela `product`.
- `product_source_observation`: modelo/registro específico da fonte, ligado ao produto
  canônico e contendo os valores ajustados para leitura no banco.
- `AggregateRecord`: observação agregada, sem marca/modelo, persistida em `aggregate_reference`.

Registros de fonte continuam possuindo uma identidade própria (`source + source_id`),
preservando os UUIDs existentes do ENERGY STAR. A projeção canônica usa apenas a
taxonomia global (`category + subcategory`).

**Precedência de fontes** (seção 4 da spec, implementada em
`collector/precedence.py`): apenas registros de fonte primária brasileira
(`INMETRO`/PBE e futuras fontes oficiais de fabricante registradas em
`PRIMARY_BR_SOURCES`) alimentam as métricas da projeção canônica.
Fontes estrangeiras (`ENERGY STAR`), genéricas (`WATTSIMPLE`) e agregados
(`IEA`) ficam SOMENTE em `product_source_observation` — nunca são
média-los com dados brasileiros e nunca sobrescrevem especificação
verificada. Quando não há registro elegível para uma métrica, ela fica
`NULL` (indisponível) — nunca inventada.

**Agregação canônica**: por grupo (`category + subcategory`), cada métrica
(`avg_power_w` em W, `annual_energy_kwh` em kWh/ano) é a média aritmética
apenas dos membros elegíveis com valor não-nulo. A normalização de
ingestão garante unidade/periodo comparáveis (INMETRO: kWh/mês → kWh/ano,
×12 exatamente uma vez).

**Persistência INSERT-ONLY**: o coletor grava com
`ON CONFLICT DO NOTHING` (produto por `id`; observação por
`(source, external_id)`). Nada é atualizado nem apagado — repetições são
contabilizadas como duplicatas. O coletor NÃO executa DDL: o schema é
propriedade das migrations (004/005/006 e `create.sql`); contra um banco
sem as migrations, o coletor falha rápido em `verify_schema()`.

**Tensão** (seção 3 da spec): preservada por observação como
proveniência (`voltage_raw` verbatim + `voltage_kind`
`unknown|monovolt|bivolt|range` + `voltage_min_v/max_v` em V). O valor
físico NUNCA é convertido (220 V permanece 220 V; rótulo 110 V é
distinto de especificação 127 V); ausência fica `unknown` — nunca
inferida por país/estado.

## WattSimple

- Página: <https://www.wattsimple.com/data>
- Dataset: `Household appliance wattage reference`
- CSV: <https://www.wattsimple.com/data/appliance-wattage/csv>
- Finalidade: valores típicos para aparelhos domésticos.
- Campos oficiais: `appliance`, `category`, `running_watts`, `starting_watts`,
  `typical_hours_per_day`.
- Escopo confirmado: 143 registros; a página informa que são valores típicos,
  não uma pesquisa de medições universais.
- Licença informada pela fonte: CC BY 4.0, com atribuição e link.

Mapeamento atual:

| Campo WattSimple | Destino | Regra |
|---|---|---|
| `appliance` | nome e identidade da observação | aparelho genérico |
| `running_watts` | `Product.avg_power_w` | potência típica em W |
| `starting_watts` | raw disponível no registro | não é potência média |
| `typical_hours_per_day` | raw disponível no registro | não é gravado como consumo derivado |
| `category` | contexto bruto | taxonomia do sistema é resolvida pelo adapter |

O client aceita conteúdo CSV, arquivo local ou o endpoint oficial. Valores típicos não
devem ser tratados como medição universal nem como verdade absoluta.

## INMETRO / PBE — transporte REAL verificado

- Página da categoria: <http://www.inmetro.gov.br/CONSUMIDOR/pbe/refrigeradores.asp>
- Tabela oficial (download direto, link da página):
  <http://www.inmetro.gov.br/CONSUMIDOR/pbe/Tabela_Inmetro_Refrigeradores_e_Assemelhados.xlsx>
- Sistema interativo PBE: <https://pbe.inmetro.gov.br/> (web app, sem API
  pública REST conhecida — não há endpoint inventado; o transporte usa a
  tabela XLSX oficial publicada).
- Tabela verificada em out/2026: Excel 2007+, ~996 linhas, versão
  informada no próprio arquivo (12/11/2021).

Estrutura verificada (cabeçalho de 3 níveis, células mescladas):

| Grupo (linha 1) | Sub-colunas (linha 3) |
|---|---|
| FORNECEDOR, MARCA, MODELO, TIPO DE PRODUTO, SISTEMA DE DEGELO, AGENTE DE EXPANSÃO DA ESPUMA | — |
| Nº DE REGISTRO | número do certificado (ex.: `008370/2019`) |
| VOLUME INTERNO (l) | REFRIGERADOR / CONGELADOR / TOTAL — não ingerido |
| **CONSUMO DE ENERGIA (kWh/mês)** | **127 V** / **220 V** / VA |
| CONSUMO PADRÃO (Cp) | VA, a, b, Cp — não ingerido |
| ÍNDICE DE EFICIÊNCIA | 127 V / 220 V — não ingerido |
| NÍVEIS DE CLASSIFICAÇÃO | limiares A+++..C — não ingerido |
| FAIXA DE CLASSIFICAÇÃO Padrão 2015 / 2022 | 127 V / 220 V → classe ENCE |

Regras de ingestão (`collector/sources/inmetro_xlsx.py`):

- **Consumo é declarado POR TENSAO**: cada (modelo, tensão) com consumo
  declarado (> 0) vira UMA observação com `voltage_raw` = "127 V"/"220 V".
  Modelo bivolt gera duas observações — cada uma com o consumo DECLARADO
  da sua tensão (ex.: PRF406I: 40 kWh/mês @127 V → 480 kWh/ano; 43
  @220 V → 516 kWh/ano). Nenhuma conversão por tensão é aplicada.
- **VA é potencia aparente (volt-ampere), não kWh/mês** — coluna
  excluída da ingestão.
- **`Nº DE REGISTRO` não é único por modelo** (um certificado cobre
  vários modelos; re-registros do mesmo modelo existem — verificado:
  PRF406I em `008370/2019` e `001111/2015` com consumos distintos). A
  identidade é `marca|modelo|registro|tensão`; o registro segue como
  proveniência no registro bruto em memória.
- **kWh/mês → kWh/ano ×12 exatamente uma vez**; valor bruto e unidade
  originais ficam em `raw_energy_value`/`raw_energy_unit`.
- **ENCE**: faixa Padrão 2022 tem precedência sobre 2015; `A+++` (Padrão
  2022) é válido — vocabulário `A+++..G` (migration 006).
- **Forward-fill de cabeçalho mesclado**: a coluna 220 V herda o grupo
  `CONSUMO DE ENERGIA` da célula mesclada — sem isso a variante 220 V
  seria silenciosamente ignorada (bug detectado e coberto por teste).
- Validação real (arquivo oficial baixado): **542 observações**
  (266 @127 V + 276 @220 V), zero identidades duplicadas, classes
  A+++×173, A++×74, A+×62, A×214, B×10, C×9; subcategorias Geladeira 361,
  Congelador 101, Frigobar 80.

O fixture CSV (`InmetroClient`) permanece para testes determinísticos;
o transporte de produção é o XLSX (`--source inmetro` via
`collector/sources/registry.py`).

## IEA Household Appliances Database

- Página: <https://www.iea.org/data-and-statistics/data-product/household-appliances-database>

A IEA é tratada como fonte de referência agregada: presença, estoque, difusão, penetração
e estatísticas por país/mercado. Ela não é forçada para a tabela de produtos físicos.
O adapter retorna `AggregateRecord` e o destino é `aggregate_reference`, preservando a
unidade original no campo `unit`.

O parser XLSX real ainda requer confirmação da estrutura do workbook, sheets, dimensões,
indicadores, valores ausentes e unidades. Até essa confirmação, o fixture CSV permanece
intencionalmente separado do caminho produtivo.

## Manutenção

1. Atualize o transporte de uma fonte sem alterar a normalização de outra.
2. Preserve `source`, `source_id`, dataset e unidade ao mapear novos campos.
3. Use `NULL` quando a fonte não fornecer potência, horas ou consumo.
4. Não altere a composição das chaves ENERGY STAR sem migração e decisão explícita.
5. Não faça deduplicação física automática entre WattSimple, INMETRO, IEA e ENERGY STAR.
6. Antes de registrar uma fonte no CLI, adicione fixture representativa, teste de parser,
   teste de identidade e teste de idempotência.
7. O coletor é INSERT-ONLY (`ON CONFLICT DO NOTHING`) e NÃO executa DDL:
   alterações de schema são migrations versionadas (004/005/006,
   `create.sql`); o coletor valida o schema em `verify_schema()` e falha
   rápido se as migrations não foram aplicadas.
8. Nova fonte primária brasileira (fabricante oficial) deve ser
   registrada em `PRIMARY_BR_SOURCES` (`collector/precedence.py`) com
   decisão do DEV — fontes desconhecidas nunca alimentam a projeção
   canônica.
9. Fórmulas de consumo/custo (horas equivalentes, custo, standby, perfis
   de uso) são do motor Java (BigDecimal); o coletor entrega apenas
   dado bruto normalizado com unidade/periodo.

## Compatibilidade com Spring

O contrato canônico é EXATAMENTE a entidade Java `Product`
(seção 1 da spec — verificado por teste de alinhamento entre Java,
`create.sql`, DDL do coletor e diagrama drawio):

```text
product.id                UUID
product.name              VARCHAR(150)
product.brand             VARCHAR(255)
product.model             VARCHAR(255)
product.category          VARCHAR(255)
product.subcategory       VARCHAR(255)
product.avg_power_w       NUMERIC      -- W
product.annual_energy_kwh NUMERIC      -- kWh/ano
```

A aplicação Spring não precisa conhecer os detalhes de cada fonte para consultar o produto
canônico. Proveniência de fonte fica em `product_source_observation`
(`canonical_product_id`, `source`, `external_id`, `brand`, `model`,
`dataset_id`, `power_w`, `annual_energy_kwh`, `standby_power_w`,
`is_generic`, `voltage_raw/kind/min_v/max_v`, `raw_energy_value/unit`,
`observed_at`); a classe ENCE fica em `energy_label_class`. As colunas
legadas `product.standby_power_w` e `product.is_generic` foram
desprezadas da escrita (migration 005): quem as quiser consulta a
observação de origem. As fórmulas de uso (horas ativas/standby, custo
com tarifa) permanecem no Java — `registry_user_product` carrega
`quantity`, `avg_active_hours` e `hours_standby`.

A migração não remove nem altera IDs já referenciados por
`registry_user_product`. Produtos antigos do catálogo não são
reidentificados automaticamente, pois o schema legado
não possui proveniência suficiente para reconstruir sua origem com segurança. O backfill
desses registros deve ser uma operação explícita e auditada.
