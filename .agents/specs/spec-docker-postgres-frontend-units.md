# SPEC — Script Docker PostgreSQL + Formatador de Unidades do Frontend

- **Data:** 15/10/2026
- **Autor:** specification-engineer (spec STANDARD, duas tasks independentes)
- **Estado:** PROPOSTA aguardando aceite do DEV para implementação
- **Base de evidência:** commit `41b9a84` (HEAD em 15/10/2026) + inspeção direta de
  arquivos/container; cache `.agents/protocol/docs/codebase-explorer.json`
  (13/10, commit `a1d9415` — levemente stale, estruturalmente válido).

---

## 0. Contexto e Escopo

Duas tasks **independentes** (nenhuma depende da outra):

| # | Task | Tipo | Complexidade |
|---|------|------|--------------|
| 1 | Script bash de instância PostgreSQL em Docker (Linux) | tooling/ops | STANDARD |
| 2 | Formatador de unidades do frontend (terminologia W / V / kWh / R$) | feature frontend localizada | STANDARD |

**Origem da Task 2:** feedback do revisor Dino (13/10/2026): *"corrija a
voltagem, o correto é 127 volts (127v)"* — valores de tensão foram descritos
com "W" (ex.: "127w de tomada"). O frontend precisa exibir unidades corretas:
**potência em W, voltagem/tensão em V, energia em kWh, custo em R$**.

### Fora de escopo (OUT-OF-SCOPE FINDINGS)

- Expor voltagem no backend (`Product` não tem coluna de tensão; tensão vive
  em `product_source_observation.voltage_*`, sem entidade JPA e sem endpoint).
  A Task 2 entrega o formato de exibição **pronto** para quando expor; criar
  endpoint/DTO novo é decisão do DEV e não faz parte desta spec.
- Corrigir rótulos errados **armazenados no banco** (dados de origem) —
  domínio do coletor/backend, não do frontend.
- Redesign visual. As classes `.results__*` do `style.css` existente são
  reutilizadas; **nenhuma mudança de CSS é necessária**.
- Arquivos atualmente modificados pelo DEV na worktree
  (`MetricsController.java`, `MetricsByUserDTO.java`) — NÃO tocar.
- Scripts legados `migrations/migrate.sh` e `migrations/migrate_remote.sh`
  NÃO são alterados (apenas registram o padrão a NÃO repetir: credenciais
  hardcoded — `migrate.sh:84,119-158` — e paths externos `/home/quitto/migration`).

---

## 1. TASK 1 — Script de instância PostgreSQL em Docker

### 1.1 Objetivo

Um script bash único, idempotente, que deixa o banco local do projeto
(**coerente com `application.properties`**) pronto: container saudável +
schema + dados (dump preferencial) + validação + string de conexão reportada.

### 1.2 Fontes de configuração (contrato de leitura)

**FACT** — `src/main/resources/application.properties:6-10`:

```properties
spring.config.import=optional:file:.env[.properties]
spring.datasource.url=jdbc:postgresql://localhost:5432/neondb?sslmode=disable
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASSWORD}
```

O script DEVE:

1. **Parsear a URL JDBC** de `spring.datasource.url` em
   `application.properties` → extrair host, porta e dbname
   (regex: `jdbc:postgresql://HOST:PORT/DBNAME`). ATUAL: `localhost:5432/neondb`.
2. **Ler credenciais do `.env` na raiz** (`DB_USER`, `DB_PASSWORD`) por
   parsing textual (`grep '^DB_' .env | cut -d= -f2-`), **NUNCA** `source`
   do arquivo (evita execução de conteúdo). `.env` está no `.gitignore`
   (FACT, `.gitignore`) — o script também não deve imprimir seu conteúdo.
3. **Fallback seguro** (ordem): flag CLI > variável de ambiente > `.env` >
   erro com mensagem clara. Se a URL JDBC não for parseável → erro imediato
   (não adivinhar host/porta/dbname).
4. Se host JDBC ≠ `localhost`/`127.0.0.1` → `WARN` explícito (a instância
   Docker só serve conexões mapeadas localmente) e seguir.

### 1.3 Ciclo de vida do container

**FACT (inspeção live, 15/10/2026)** — container existente:

```
Name: neondb-local          Image: postgres:18 (PG 18.6)
Env:  POSTGRES_USER=neondb_owner  POSTGRES_DB=neondb
      POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C
Health: pg_isready -U neondb_owner -d neondb
Volume: migration_postgres_data (named) -> /var/lib/postgresql
Ports: 5432->5432
```

Comportamento obrigatório:

1. **Se container do nome-alvo já existe:**
   - saudável → **reutilizar** (idempotência; nunca recriar nem parar);
   - exists mas não saudável → aguardar healthcheck (§1.5); se não ficar
     saudável → falhar com `docker logs` (últimas ~30 linhas) no erro.
2. **Se não existe:** `docker run -d` coerente com as fontes de config:
   - `--name` (default `neondb-local`, sobrescrevível por flag);
   - `-e POSTGRES_DB=<dbname da URL JDBC>`, `-e POSTGRES_USER=<DB_USER>`,
     `-e POSTGRES_PASSWORD=<DB_PASSWORD>`;
   - `-e POSTGRES_INITDB_ARGS=--encoding=UTF8 --locale=C` (paridade com o
     container existente — FACT);
   - `-p <porta JDBC>:5432` e healthcheck `pg_isready -U <user> -d <db>`;
   - **volume nomeado persistente** (default `neondb_local_data`; se a porta
     5432 já estiver ocupada por outro container, falhar com mensagem clara —
     não usar `--force` nem remover nada);
   - imagem default `postgres:18` (paridade com o existente), sobrescrevível
     por flag.
3. **Coerência:** se o container existente tem `POSTGRES_USER`/`POSTGRES_DB`
   diferentes dos parseados → **erro** (não dá para alinhar sem recriar);
   se `POSTGRES_PASSWORD` divergir → `WARN` com o SQL de correção sugerido
   (`ALTER USER ... WITH PASSWORD`), sem executá-lo e sem ecoar senha.
4. **Destruição de dados somente com flag explícita** `--recreate`
   (remove APENAS o container, não o volume; imprime aviso antes). Remover
   volume exige flag adicional `--purge-volume` **combinada** com
   `--recreate`. Sem essas flags o script NUNCA executa `docker rm`/`down -v`.

### 1.4 Migrações e dados — ordem canônica

**FACT** — conteúdo dos arquivos lidos (15/10/2026):

- `migrations/create.sql` = schema completo canônico para bancos NOVOS
  (users, product com 9 colunas, `product_source_observation` JÁ COM as
  colunas de tensão, `registry_user_product`); cabeçalho registra que espelha
  004/005 e `add_avg_idle_energy_for_hour` ("espelhadas aqui para bancos
  novos" — `create.sql:62`).
- `004`, `005`, `006`, `add_avg_idle_energy_for_hour.sql` = todos
  idempotentes (`IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` / bloco `DO`
  idempotente em 006).
- `rename_userproduct_to_registry_user_product.sql` = legado: em banco novo
  **falharia** (`ALTER TABLE userproduct` — relação inexistente) com
  `ON_ERROR_STOP`. Só se aplica a bancos com a tabela antiga `userproduct`.
- `seed.sql` = idempotente (`ON CONFLICT (id) DO UPDATE` p/ user 1;
  `WHERE NOT EXISTS` p/ vínculos; só vincula produtos JÁ existentes).
- `migrate_remote.sh` consome arquivos EXTERNOS (`neon_to_local.sql`,
  `neon_data.sql`) que não estão no repo — fora da ordem canônica.

**DECISÃO ESPECIFICADA (ordem canônica de aplicação):**

```text
CAMINHO A — dump presente (backups/neondb_backup_*.dump, mais recente):
  1. pg_restore do dump (--no-owner --no-privileges, --exit-on-error)
  2. create.sql                                    (reconciliação, no-op)
  3. 004_canonical_product_observations.sql        (no-op idempotente)
  4. 005_canonical_product_contract.sql            (no-op idempotente)
  5. 006_collector_ingestion_tables.sql            (idempotente)
  6. add_avg_idle_energy_for_hour.sql              (no-op idempotente)
  7. rename_userproduct... — CONDICIONAL: só se a tabela `userproduct` existir
  8. seed.sql — NÃO aplicar por padrão neste caminho (dados vieram do dump);
     aplicar apenas com flag --seed

CAMINHO B — sem dump (fallback):
  1. create.sql
  2. 004 → 3. 005 → 4. 006 → 5. add_avg_idle_energy_for_hour.sql
  6. rename_userproduct... — CONDICIONAL (idem A)
  7. seed.sql (obrigatório neste caminho, salvo --no-seed)
```

Regras:

- Toda execução de SQL com `-v ON_ERROR_STOP=1` (falha rápida e limpa).
- Preferência: **pg_restore quando existir dump** (`backups/*.dump`, formato
  custom `-Fc` — FACT). Escolher o dump de **timestamp mais recente**;
  flag `--dump <arquivo>` permite apontar outro.
- O passo 2-6 no Caminho A é reconciliação proposital (dump antigo + campos
  novos, ex.: se o dump preceder `avg_idle_energy_for_hour`).
- `rename_userproduct` NUNCA entra incondicionalmente (falharia em banco
  novo). Checagem: `to_regclass('public.userproduct') IS NOT NULL`.
- Conexão dos passos SQL/restore: preferir `docker exec -i <container> psql`
  (sem dependência de cliente host e sem expor senha por processo);
  fallback: `psql` do host com `PGPASSWORD` em ambiente do processo
  (`/usr/bin/psql` e `/usr/bin/pg_restore` existem no host — FACT).
- `spring.jpa.hibernate.ddl-auto=update` (FACT,
  `application.properties:12`) também cria colunas via Hibernate: o script
  DEVE documentar no `--help` que deve rodar **antes** de subir o Spring.

### 1.5 Healthcheck e validação

1. **Aguardar saúde:** loop em
   `docker inspect --format '{{.State.Health.Status}}'` até `healthy`,
   timeout default 120 s (flag `--timeout`), sleep 2 s. Timeout → erro com
   logs do container.
2. **Validação final (obrigatória, via psql):**
   - existência das 10 tabelas esperadas (FACT — presentes no dump/seed e
     referenciadas em `migrate.sh:173-182`): `users`, `product`,
     `registry_user_product`, `product_source_observation`,
     `energy_label_class`, `energy_raw_measurement`, `energy_specification`,
     `source_metadata`, `source_product`, `aggregate_reference`;
   - contagens de linhas reportadas para cada uma;
   - **limiares:** Caminho A → `product >= 1` (dump real) e
     `users >= 1`; Caminho B → `users >= 1` (seed) e `product >= 0`
     (reportar, sem falhar — produto só popula via coletor/dump).
   - integridade referencial básica (mesmas queries de
     `migrate.sh:189-194`): registros de `registry_user_product` com FK
     válida para `users` e `product`; `product_source_observation` → `product`.
3. **Relatório final:** string de conexão efetiva **sempre mascarada**:
   `postgresql://<user>:***@<host>:<porta>/<db>?sslmode=disable` + a URL JDBC
   equivalente; nome do container, imagem, volume, caminho do dump aplicado
   (ou "seed"), resumo de contagens. **NUNCA** imprimir `DB_PASSWORD`,
   `POSTGRES_PASSWORD` ou o conteúdo do `.env`.

### 1.6 Interface do script

```text
Uso: bash <script>.sh [opções]

  --container NAME   nome do container (default: neondb-local)
  --image TAG        imagem Postgres (default: postgres:18)
  --volume NAME      volume de dados (default: neondb_local_data)
  --dump PATH        dump custom -Fc a restaurar (default: mais recente em backups/)
  --no-restore       ignora dump disponível e usa migrations + seed
  --seed             força seed também no caminho com dump
  --no-seed          pula seed no caminho sem dump
  --recreate         DESTRUTIVO (container): recria o container (mantém volume)
  --purge-volume     DESTRUTIVO (dados): exige --recreate junto
  --timeout SECONDS  timeout do healthcheck (default: 120)
  --help
```

Requisitos não funcionais: `set -euo pipefail`; bash/Linux; helpers de log
com cores estilo `migrate.sh:16-25` (`[INFO]/[OK]/[WARN]/[ERR]`) — **sem**
copiar as credenciais hardcoded dele; sair com código != 0 em qualquer falha;
sem `docker-compose` obrigatório (usa `docker run`; se o container existente
veio de compose, apenas reutiliza — não chama compose).

### 1.7 Localização proposta

**PROPOSAL:** `scripts/setup_postgres_docker.sh` (novo diretório `scripts/`).
Alternativa: raiz do repo. O repo hoje não tem `scripts/` e os scripts
existentes em `migrations/` são legados com propósito diferente — separar
evita confusão. *Decisão de convenção pertence ao DEV.*

---

## 2. TASK 2 — Formatador de unidades do frontend

### 2.1 Objetivo

Centralizar em um único módulo a formatação de TODAS as grandezas exibidas
(W, V, kWh, h/dia, R$), com terminologia correta e pt-BR, e deixar a exibição
de voltagem **pronta** para o dia em que o backend expuser o dado.

### 2.2 Pontos de exibição atuais (FACT — `app.js` lido integralmente)

| Local | Linha | Hoje | Unidade |
|---|---|---|---|
| `formatProduct` | 373-378 | `(${product.avgPowerW} W)` — valor cru, truthy-check | potência W |
| `formatRegistryDetails` | 190-203 | `Ativo: ${h} h/dia`, `Standby: ${h} h/dia`, `Quantidade: N` | horas |
| `renderCalculationResult` | 288-289 | `${result.avgDailyKwh} kWh/dia`, `${result.avgUseInYear} kWh/ano` — valor cru | energia |
| `renderCalculationResult` | 292-293 | `brlFormatter.format(...)` (Intl pt-BR BRL) — **correto** | custo |
| voltagem | — | **não exibida** (nada no frontend) | — |

**FACT:** `index.html` não tem unidades hardcoded; carrega apenas
`<script src="/app.js"></script>` (linha 191). **FACT:** não há `package.json`
— sem testes JS automatizados; validação é manual/Playwright.

**FACT:** `/products` retorna `List<Product>` (entidade JPA —
`ProductController.java:35-51`); `Product.java` NÃO tem campo de tensão.
`product_source_observation.voltage_raw/voltage_kind/voltage_min_v/voltage_max_v`
não tem entidade JPA nem endpoint (cache codebase-explorer, FACT). → A
exibição de voltagem fica **estruturada e inativa** até existir fonte.

### 2.3 Módulo de unidades

**PROPOSAL (estrutura):** novo arquivo `src/main/resources/static/units.js`,
carregado em `index.html` ANTES de `app.js` (sem bundler; funções puras,
sem estado). Alternativa aceitável: bloco `const Units = {...}` no topo de
`app.js`. Contrato público (assinaturas — PROPOSAL):

```js
// Base numérica pt-BR: aceita number | string numérica ("150.00") | null/undefined
formatNumberPtBR(value, { maxFractionDigits = 3 } = {})   // '150' | '62,5' | '' (inválido/ausente)

formatPowerW(value)        // → '150 W' | '62,5 W' | '' (null/undefined/''/0 → oculta)
formatVoltage(voltage)     // voltage: { kind, minV, maxV, raw } | null → ver §2.4
formatEnergyKwh(value, period)  // period: 'dia' | 'ano' → '1,032 kWh/dia' | '536,4 kWh/ano'
formatHoursPerDay(value)   // → '8 h/dia' | '8,5 h/dia' | ''
formatBrl(value)           // delega ao Intl BRL já existente (app.js:9)
```

Regras numéricas:

- Parse tolerante: `Number(String(value))` — BigDecimal/Jackson chega como
  number ou string com ponto decimal; strings pt-BR com vírgula também
  aceitas (`replace(',', '.')`) — paridade com `numberFromForm`
  (`app.js:395-397`).
- `Intl.NumberFormat('pt-BR', { maximumFractionDigits: N })`; N = 2 p/ W,
  3 p/ kWh, 1 p/ h/dia. Trailing zeros caem naturalmente
  (`150.00 → '150'`; `1.032000 → '1,032'`). Tensão sempre inteiro.
- `null`/`undefined`/string vazia/NaN → `''` (o ponto de exibição OMITE o
  item; **nunca** exibir "0" inventado). Manter o comportamento atual de
  `formatProduct` ocultar potência `0`/ausente (truthy-check preservado).
- Custos: `formatBrl` mantém exatamente o `Intl` BRL atual (2 casas, R$).

### 2.4 Contrato de voltagem (espelha `collector/voltage.py` — FACT)

`energy_collector/collector/voltage.py` define a semântica canônica:
**NUNCA converter tensão** (220 ≠ 127; sem multiplicar/dividir), rótulo
verbatim preservado em `raw` (auditoria), classificação
`unknown|monovolt|bivolt|range`, valores em `min_v`/`max_v` (monovolt:
`min==max`; par ordenado ascendente para bivolt), faixa plausível 50–600 V.

Regras de EXIBIÇÃO (formato pronto; o formato de entrada
`{ kind, minV, maxV, raw }` espelha as colunas
`voltage_kind/voltage_min_v/voltage_max_v/voltage_raw`):

| kind | minV/maxV | Exibição |
|---|---|---|
| `monovolt` | 127/127 | `127 V` |
| `monovolt` | 110/110 | `110 V` (**nunca** virar 127) |
| `bivolt` | 110/220 | `110/220 V` (ordenado, valores como declarados) |
| `bivolt` | null | `Bivolt` |
| `bivolt` | par incompleto (só minV ou só maxV) | `Bivolt` (fato bivolt preservado — nunca mostrar só um número) |
| `range` | 100/240 | `100-240 V` |
| `unknown` | null | `''` — omite (nunca inferir por país/categoria) |
| entrada nula | — | `''` |

Invariantes: unidade sempre **`V` maiúsculo** (nunca `w`/`v` minúsculo);
valores inteiros; `raw` **nunca exibido** no caminho de exibição (apenas
auditoria/observabilidade — decisão de revisão pós-implementação); **nenhuma
conversão física**.

### 2.5 Integração nos pontos de exibição

| Ponto | Mudança |
|---|---|
| `formatProduct` (375) | potência via `formatPowerW(product.avgPowerW)`; **quando** o produto passar a ter tensão, apendar `· ${formatVoltage(v)}` (campo futuro — UNKNOWN de forma; a chamada fica atrás de `product.voltage != null`) |
| `formatRegistryDetails` (196-201) | `Ativo: ${formatHoursPerDay(...)}`, `Standby: ${formatHoursPerDay(...)}`; `Quantidade` permanece inteiro cru |
| `renderCalculationResult` (288-289) | `formatEnergyKwh(result.avgDailyKwh, 'dia')` / `(result.avgUseInYear, 'ano')` |
| `renderCalculationResult` (292-293) | `formatBrl(result.dailyCost/annualCost)` (mesmo Intl) |
| `metricRow` / rótulos | rótulos textuais ("Consumo médio diário", "Gasto por dia") inalterados |
| `style.css` / `index.html` | CSS **sem mudanças** (classes `.results__*` reusadas); `index.html` só ganha o `<script src="/units.js"></script>` antes de `app.js` (se PROPOSAL A) |

### 2.6 Critérios de terminologia (o pedido do revisor)

- Potência SEMPRE `W` (maiúsculo, com espaço antes): `150 W`.
- Voltagem/tensão SEMPRE `V`: `127 V`, `220 V`, `110/220 V`, `100-240 V`.
  **Nunca** `127w`, `127 W`, `127v` em qualquer tela.
- Energia: `kWh/dia`, `kWh/ano` (como hoje — mantido).
- Custo: `R$` via Intl BRL (como hoje — mantido).

---

## 3. Critérios de Aceitação

### Task 1 (script)

- **AC-1.1** `bash <script>.sh` termina 0: container healthy, validação verde,
  string de conexão mascarada impressa.
- **AC-1.2** Idempotente: 2ª execução seguida reutiliza o container
  (nenhum `docker rm`/recriação; dados preservados), sem flags.
- **AC-1.3** Host/porta/dbname vêm da URL JDBC de `application.properties`;
  user/senha do `.env`; **zero** credencial literal no código; senha nunca
  aparece em stdout/stderr/erros.
- **AC-1.4** Com dump presente → pg_restore executado; sem dump →
  `create.sql → 004 → 005 → 006 → add_avg_idle → seed`;
  `rename_userproduct` aplicado apenas se `userproduct` existir (nunca
  falha em banco novo).
- **AC-1.5** Healthcheck aguardado com timeout configurável; timeout → erro
  claro + logs do container.
- **AC-1.6** Validação final: 10 tabelas presentes, contagens reportadas,
  limiares por caminho (§1.5.2) e FKs checadas.
- **AC-1.7** Destruição só com `--recreate` (container) e
  `--recreate --purge-volume` (dados), com aviso impresso antes.
- **AC-1.8** Container novo criado com `postgres:18`, env coerentes com
  application.properties + `.env`, healthcheck `pg_isready`, volume nomeado.

### Task 2 (frontend)

- **AC-2.1** Terminologia: potência sempre `W`, voltagem sempre `V`,
  energia `kWh/dia|ano`, custo `R$` — em todos os pontos de exibição;
  nenhum `w`/`v` minúsculo como unidade exibida.
- **AC-2.2** `formatPowerW(150) → '150 W'`; `formatPowerW('62.50') → '62,5 W'`;
  `formatPowerW(null) → ''` (item omitido, comportamento atual preservado).
- **AC-2.3** kWh em pt-BR com vírgula: `1.032000 → '1,032 kWh/dia'`;
  custos idênticos aos atuais (Intl BRL).
- **AC-2.4** `formatVoltage`: monovolt 127 → `127 V`; 110 → `110 V` (não
  converte); bivolt 110/220 → `110/220 V`; range 100/240 → `100-240 V`;
  bivolt sem números → `Bivolt`; unknown/null → `''`.
- **AC-2.5** Nenhum valor de tensão é convertido ou reinferido (semântica
  `voltage.py` preservada na exibição).
- **AC-2.6** Regressão: fluxo login → lista de produtos (com `150 W`) →
  registro → cálculo (kWh/R$) funciona; visual inalterado (mesmas classes;
  style.css sem diff).
- **AC-2.7** Centralização: nenhuma unidade de grandezas escrita em template
  literal fora do módulo (grep por ` W)`/`kWh`/`h/dia` em `app.js` aponta só
  para chamadas do módulo).

---

## 4. Registro de Evidências

| Afirmação | Classe | Fonte |
|---|---|---|
| URL JDBC `localhost:5432/neondb`, user/senha via `.env` | FACT | `application.properties:6-10` |
| Container `neondb-local` postgres:18, healthy, vol `migration_postgres_data`, user/db `neondb_owner/neondb` | FACT | `docker inspect` (15/10/2026) |
| Dump custom `-Fc` em `backups/neondb_backup_20261013_162001.dump` | FACT | `backups/` (41 KB) |
| `create.sql` é schema completo novo (inclui tensão e 9ª coluna) | FACT | `create.sql:1-116` |
| 004/005/006/add_avg_idle idempotentes; rename legado falha em banco novo | FACT | leitura dos 4 arquivos |
| `seed.sql` idempotente; só vincula produtos existentes | FACT | `seed.sql:10-59` |
| `migrate.sh` tem credenciais hardcoded e paths externos (padrão a evitar) | FACT | `migrate.sh:11-12,84,119-158` |
| `/products` retorna `List<Product>`; entidade sem tensão; sem endpoint de tensão | FACT | `ProductController.java:35-51`, `Product.java`, cache explorer |
| Semântica de tensão: nunca converter; raw verbatim; kinds unknown/monovolt/bivolt/range | FACT | `voltage.py:1-173` |
| Pontos de exibição e linhas do app.js | FACT | `app.js:190-378` |
| Sem tooling JS (sem package.json) | FACT | raiz do repo |
| Localização `scripts/setup_postgres_docker.sh` | PROPOSAL | convenção nova |
| Módulo `units.js` separado (vs bloco em app.js) | PROPOSAL | — |
| Máx. casas decimais (W=2, kWh=3, h=1) | PROPOSAL | escolha de exibição |
| Forma do payload de tensão no frontend (`{kind,minV,maxV,raw}`) | INFERENCE | espelha colunas `product_source_observation` (create.sql:81-85) |
| Se dump precede coluna nova, reconciliação cobre | INFERENCE | migrations idempotentes + dump de 13/10 (dia da coluna) |
| Como o backend exporá tensão no futuro | UNKNOWN | decisão do DEV, fora do escopo |
| Contagem atual de linhas do banco | UNKNOWN | cache (253 product) de 13/10, não re-verificado |

## 5. Riscos

- **R1** `pg_restore` pode tropeçar em roles/ownership do Neon → mitigado com
  `--no-owner --no-privileges` + `--exit-on-error` (falha limpa e relatada).
- **R2** Conflito de porta 5432 com outra instância → erro claro, sem
  ações destrutivas.
- **R3** Hibernate `ddl-auto=update` rodando antes do script pode criar
  colunas divergentes → script documenta ordem (rodar antes do Spring).
- **R4** Dump futuro sem tabelas do coletor → reconciliação (passos 2-6) cobre.
- **R5** Formatação pt-BR dentro de `<option>` — texto simples via
  `textContent` (sem risco de HTML).
- **R6** Valores BigDecimal como string/number no JSON → parser tolerante
  especificado (§2.3).

## 6. Handoff

- **Consumidor:** agente de implementação (code-implementer).
- **Ler antes:** esta spec; `app.js` integral; `migrations/create.sql`;
  `voltage.py` (só §docs para regras de tensão).
- **Não reinvestigar:** ordem das migrations (§1.4, fechada); contrato de
  `/products` (sem tensão — FACT); config de conexão (§1.2); pontos de
  exibição (§2.2); inexistência de tooling JS.
- **Decisões pendentes do DEV** (não bloqueiam início das partes não
  afetadas): D1 localização do script (default: `scripts/`);
  D2 `units.js` separado (default) vs bloco em `app.js`;
  D3 futuro endpoint/DTO de tensão (fora do escopo);
  D4 casas decimais propostas (§2.3).
