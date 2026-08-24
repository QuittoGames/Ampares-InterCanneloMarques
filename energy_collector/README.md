# ENERGY STAR Data Collector

Coletor Python independente que varre dados públicos de eficiência energética da
**ENERGY STAR / EPA** (plataforma Socrata `data.energystar.gov`), normaliza os
registros e persiste num PostgreSQL.

> Fonte pública e verificável. Nenhum dado é inventado: campos ausentes ficam
> `NULL`. Apenas atributos **intrínsecos** do aparelho são persistidos — o
> payload original e a URL da fonte **não** são guardados (sem `raw_data` /
> `source_url`).

> Todos os arquivos deste coletor ficam dentro da pasta `energy_collector/`,
> isolados do projeto Java. Execute os comandos a partir dessa pasta.

## 1. Instalação

Requer **Python 3.12+**.

```bash
cd energy_collector
python -m pip install -r requirements.txt
```

## 2. Configuração do `.env`

Copie o exemplo e preencha com suas credenciais (nunca hardcoded no código):

```bash
cd energy_collector
cp .env.example .env
```

```env
# Opção A — URL completa
DATABASE_URL=postgresql://postgres:password@localhost:5432/energy

# Opção B — partes individuais
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=energy
# DB_USER=postgres
# DB_PASSWORD=password

# Token Socrata (OPCIONAL — acesso anônimo funciona; o token só eleva o limite)
# SOCRATA_APP_TOKEN=seu_token
```

O `.env` **não deve ser commitado** (já está no `.gitignore`).

## 3. Execução

```bash
cd energy_collector

# Uma categoria, até 1000 registros
python data_collector.py --category refrigerators --limit 1000

# Todas as categorias
python data_collector.py --all

# Retomar de onde parou (usa .collector_state.json)
python data_collector.py --all --resume

# Busca concorrente (asyncio): várias categorias em paralelo
python data_collector.py --all --concurrent --max-concurrency 4
```

Logs vão para o console (INFO) e para `data_collector.log` (DEBUG, rotativo).

## 4. Categorias disponíveis

`refrigerators`, `clothes_washers`, `clothes_dryers`, `dishwashers`,
`televisions`, `computers`, `displays`, `room_air_conditioners`, `freezers`,
`electric_cooking_products`, `ceiling_fans`, `ventilating_fans`.

Cada categoria é mapeada para um **dataset Socrata próprio** (IDs 4x4 diferentes).
Os IDs das categorias mais comuns estão fixos em `collector/config.py`; as demais
são descobertas em tempo de execução via catálogo da ENERGY STAR.

## 5. Origem dos dados

- **Primária:** ENERGY STAR / EPA Product Data (Socrata `data.energystar.gov`).
- Acesso anônimo ou com `SOCRATA_APP_TOKEN` opcional.
- Nunca scraping de marketplaces, blogs ou sites comerciais.

## 6. Paginação

- Usa `$limit` / `$offset` da API Socrata, com `$order=pd_id` para ordem estável.
- `--limit` limita registros por categoria; `--page-size` ajusta o tamanho da página.
- Progresso salvo em `.collector_state.json`; `--resume` continua de onde parou.
- Página vazia encerra a categoria normalmente (sem erro).

## 7. Idempotência

Cada registro tem uma chave determinística:

- `source::source_id` (quando `source_id` existe), ou
- `source::brand::model::category` (fallback).

Essa chave vira um **UUID determinístico** (`uuid5`) usado como chave primária
da tabela `product`. Uma segunda execução **não duplica**: o `INSERT ... ON
CONFLICT (id) DO UPDATE` atualiza a linha existente (contada em `updated`).

## 8. Tratamento de erros

- Timeout HTTP configurado.
- Retry com backoff exponencial para `429` / `5xx`; respeita `Retry-After`.
- JSON inválido ou erro de parse → registro descartado com log.
- Erro de banco → rollback da página atual (não corrompe o resto).
- Nenhum mecanismo para burlar rate limit.

## 9. Estrutura dos dados normalizados

Cada produto vira um **`Product`** (`collector/models.py`, dataclass tipada — fonte
única dos nomes de campo). Campos equivalentes ao dicionário que o schema produzia:

```python
Product(
    name="Samsung RF28T",        # composto de brand + model
    brand="Samsung",
    model="RF28T",
    category="refrigerators",
    avg_power_w=None,            # só quando a fonte dá potência (W)
    annual_energy_kwh=228.0,     # só quando a fonte dá consumo anual
    source="ENERGY STAR",        # usado só p/ derivar o id determinístico
    source_id="2206033",
)
```

O `Product` carrega a identidade e as regras como métodos:
- `dedup_key()` / `product_id()` → UUID determinístico (`uuid5`) p/ upsert idempotente.
- `validate()` → `(ok, motivo)`; rejeita sem identificador estável, potência
  negativa ou energia negativa. Não inventa valor nenhum.

**Regra importante:** `avg_power_w` e `annual_energy_kwh` nunca são
convertidos um no outro sem matemática válida. Se a fonte só fornece consumo
anual (ex.: geladeiras), a potência fica `None`.

## 10. Estrutura de código (MVC básico)

```
data_collector.py                # Controller: args → wiring → service → report
collector/
├── config.py                    # Dados: settings + catálogo de datasets
├── models.py                    # Model: Product (shape + validação + id)
├── normalization.py             # Model: raw dict → Product
├── api_client.py                # I/O: transporte HTTP (SocrataClient)
├── database.py                  # Persistência: ensure_table + upsert(Product)
├── pagination.py                # Fetch loop + resume
└── services/collection.py       # Service: resolve → fetch → normalize → validate → persist
```

O **Service** (`CollectionService`) concentra o pipeline completo e é usado
pelos dois caminhos do CLI (sequencial e `--concurrent`), evitando duplicação.

### Armazenamento

O coletor escreve diretamente na tabela **`product`** (a mesma entidade JPA do
app), com **apenas os atributos intrínsecos** do aparelho: `name`, `brand`,
`model`, `category`, `avg_power_w`, `annual_energy_kwh`. Não cria tabela
auxiliar nem guarda metadados da API. O objetivo é estimar consumo/ocioso, não
montar um catálogo completo.

O schema segue `docs/arquiteture.drawio` + `Product.java` (após o refactor que
moveu os campos de **uso** — `quantity`, `avg_active_hours`, `hours_standby` —
para a tabela intermediária `userproduct`, onde pertencem). `source` /
`source_id` são usados apenas para gerar o UUID determinístico do produto.
