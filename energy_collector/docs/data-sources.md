# Fontes de dados de produtos e energia

## Modelo operacional

O coletor mantém quatro conceitos separados:

- `Product`: registro normalizado recebido de uma fonte durante o pipeline.
- produto canônico: projeção global por tipo de aparelho, persistida na tabela `product`.
- `product_source_observation`: modelo/registro específico da fonte, ligado ao produto
  canônico e contendo os valores ajustados para leitura no banco.
- `AggregateRecord`: observação agregada, sem marca/modelo, persistida em `aggregate_reference`.

Registros de fonte continuam possuindo uma identidade própria (`source + source_id`),
preservando os UUIDs existentes do ENERGY STAR. A nova projeção canônica usa apenas a
taxonomia global (`category + subcategory`), permitindo agrupar, por exemplo, modelos de
geladeira do INMETRO, ENERGY STAR e a referência genérica WattSimple.

Para cada grupo canônico, os valores conhecidos são agregados com `AVG`. Valores nulos não
participam da média. A média é persistida na tabela `product`, enquanto os valores de cada
fonte ficam em `product_source_observation`.

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

## INMETRO / PBE

- Página de tabelas: <https://www.gov.br/inmetro/pt-br/assuntos/regulamentacao/avaliacao-da-conformidade/programa-brasileiro-de-etiquetagem/tabelas-de-eficiencia-energetica/tabelas-de-eficiencia-energetica>
- Sistema PBE: <https://pbe.inmetro.gov.br/>
- Exemplo de categoria: refrigeradores, frigobares, combinados e combinados frost-free.

O INMETRO informa que as tabelas apresentam produtos aprovados no PBE e autorizados a
ostentar a ENCE. As categorias possuem formatos próprios; portanto, o adapter deve ser
específico por categoria ou por contrato de exportação. O fixture CSV atual suporta
refrigeradores e converte `kWh/mês` para `kWh/ano` multiplicando por 12. Marca, modelo,
classe e consumo são dados de modelos reais; nenhum valor deve ser inventado quando
ausente.

O transporte real do sistema PBE ainda não foi ativado no CLI. Antes disso, é necessário
confirmar o formato/exportação oficial e um identificador estável por registro.

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

## Compatibilidade com Spring

O contrato atual da entidade Java `Product` continua sendo atendido pela tabela `product`:

```text
product.id
product.name
product.category
product.subcategory
product.avg_power_w
product.annual_energy_kwh
```

A aplicação Spring não precisa conhecer os detalhes de cada fonte para consultar o produto
canônico. Consultas futuras que precisarem de origem, marca, modelo ou valor individual
podem acessar `product_source_observation` por `canonical_product_id`. A migration não
remove nem altera IDs já referenciados por `registry_user_product`.

Produtos antigos do catálogo não são reidentificados automaticamente, pois o schema legado
não possui proveniência suficiente para reconstruir sua origem com segurança. O backfill
desses registros deve ser uma operação explícita e auditada.
