# Setup do PostgreSQL local em Docker

> Script: `scripts/setup_postgres_docker.sh`
> Documenta o comportamento implementado do script (código como fonte de
> verdade). Todo trecho abaixo foi verificado lendo o script e os arquivos
> que ele consome.

---

## 1. Propósito

Deixar a instância PostgreSQL local do projeto (Docker) pronta e validada:
**container saudável + schema (dump ou migrations) + dados + validação final**,
de forma **idempotente** — reexecuções preservam dados existentes.

### Por que ANTES do Spring

`src/main/resources/application.properties:12` usa
`spring.jpa.hibernate.ddl-auto=update`. Se o Spring subir antes do script, o
Hibernate pode criar colunas divergentes do schema canônico. Ordem correta:

```text
bash scripts/setup_postgres_docker.sh   # primeiro
# ... depois suba o Spring
```

---

## 2. Pré-requisitos

| Requisito | Detalhe |
|---|---|
| Docker | daemon acessível (`docker info`); cliente PostgreSQL no host **não** é necessário — `psql`/`pg_restore` rodam via `docker exec` no container |
| `src/main/resources/application.properties` | com `spring.datasource.url` no formato `jdbc:postgresql://HOST:PORT/DBNAME` |
| `.env` na raiz (ou variáveis de ambiente) | chaves `DB_USER=` e `DB_PASSWORD=` (formato `KEY=value`, sem prefixo `export `) |
| Dump (opcional) | `backups/*.dump` — o mais recente é usado automaticamente |

---

## 3. Fontes de configuração

| Dado | De onde vem |
|---|---|
| host, porta, dbname | URL JDBC em `application.properties` (`spring.datasource.url`, linha 8: `jdbc:postgresql://localhost:5432/neondb?sslmode=disable`) — parse por regex; URL fora do formato esperado → erro (host/porta/dbname nunca são adivinhados) |
| `DB_USER` | variável de ambiente > `.env` > erro |
| `DB_PASSWORD` | variável de ambiente > `.env` > erro |

Garantias de segurança implementadas:

- **Zero credencial hardcoded**;
- o `.env` é lido por **parsing textual** (`grep KEY=`) — nunca com `source`;
- a **senha nunca aparece** em log, stdout, stderr ou mensagem de erro
  (relatório final mostra `***`; parâmetros `password=` de URL são mascarados
  por `mask_url`);
- não há flag de senha na CLI (evitaria exposição via `ps`).

---

## 4. Defaults

| Item | Default |
|---|---|
| Container | `neondb-local` |
| Imagem | `postgres:18` |
| Volume | `neondb_local_data` |
| Porta | a da URL JDBC → `5432` no container |
| Timeout do healthcheck | `120` s (polling de 2 s) |

---

## 5. Uso

```bash
bash scripts/setup_postgres_docker.sh [--opções]
bash scripts/setup_postgres_docker.sh --help
```

| Flag | Efeito |
|---|---|
| `--container NAME` | nome do container (default `neondb-local`) |
| `--image TAG` | imagem Postgres (default `postgres:18`) |
| `--volume NAME` | volume de dados (default `neondb_local_data`) |
| `--dump PATH` | dump custom `-Fc` a restaurar (default: mais recente em `backups/*.dump`) |
| `--no-restore` | ignora dump disponível e usa migrations + seed (Caminho B) |
| `--seed` | força seed também no caminho com dump |
| `--no-seed` | pula seed no caminho sem dump |
| `--recreate` | **destrutivo (container)**: remove e recria o container; o volume é **mantido** |
| `--purge-volume` | **destrutivo (dados)**: remove o volume — exige `--recreate` |
| `--timeout SECONDS` | timeout do healthcheck (default 120) |
| `--help` | ajuda |

Exemplos:

```bash
bash scripts/setup_postgres_docker.sh                       # uso normal (idempotente)
bash scripts/setup_postgres_docker.sh --seed                # caminho A + seed
bash scripts/setup_postgres_docker.sh --recreate            # só container (volume mantido)
bash scripts/setup_postgres_docker.sh --recreate --purge-volume   # apaga os dados
```

`--seed` e `--no-seed` são mutuamente exclusivos; `--purge-volume` sem
`--recreate` é erro.

---

## 6. Ciclo de vida do container

- **Container existente é REUTILIZADO** — nunca recriado nem parado (a menos
  que `--recreate`); se estiver parado, `docker start` (dados preservados).
- **Container novo** só é criado se não existir; antes o script verifica se a
  porta da URL JDBC já está publicada por outro container (conflito → erro,
  nada removido).
- Ao reutilizar, o script confere coerência:
  - `POSTGRES_USER`/`POSTGRES_DB` do container vs `.env`/URL JDBC → divergência
    fatal (sugere `--recreate`);
  - `POSTGRES_PASSWORD` divergente → apenas WARN com o `ALTER USER` sugerido
    (o script **não** executa alteração nem exibe a senha);
  - porta mapeada ≠ porta da URL JDBC → fatal (o Spring não conectaria).
- O volume **real** do container (montado em `/var/lib/postgresql`) tem
  prioridade sobre o default em recriações — evita montar volume vazio e
  orfar volume com dados.
- Sem `--recreate`/`--purge-volume` o script **nunca** executa `docker rm` nem
  `docker volume rm`.
- Healthcheck aguardado com timeout; container sem healthcheck cai para
  polling de `pg_isready`. Timeout/falha → erro + últimas 30 linhas de
  `docker logs`.

---

## 7. Schema e dados — ordem canônica

### Caminho A (dump disponível; não há `--no-restore`)

1. `pg_restore` do dump (mais recente de `backups/*.dump`, ou `--dump PATH`),
   com `--no-owner --no-privileges --exit-on-error`
2. `migrations/create.sql`
3. `migrations/004_canonical_product_observations.sql`
4. `migrations/005_canonical_product_contract.sql`
5. `migrations/006_collector_ingestion_tables.sql`
6. `migrations/add_avg_idle_energy_for_hour.sql`
7. `migrations/rename_userproduct_to_registry_user_product.sql` — **condicional**:
   só aplica se `userproduct` existir e `registry_user_product` ainda não
   existir
8. `migrations/seed.sql` — **apenas** com `--seed` (dados vieram do dump)

**Guard de idempotência:** o `pg_restore` só roda se a tabela `users` não
existir ou estiver vazia. Se um restore anterior falhou no meio (tabela
criada mas sem dados), o restore roda de novo; se `users` já tem dados, ele é
pulado para preservar dados.

### Caminho B (sem dump, ou com `--no-restore`)

1. `migrations/create.sql`
2. `004` → `005` → `006` → `add_avg_idle`
3. rename condicional (mesma regra do Caminho A)
4. `migrations/seed.sql` — salvo `--no-seed`

Observação: 4 tabelas (`energy_raw_measurement`, `energy_specification`,
`source_metadata`, `source_product`) **não têm DDL versionado no repo** —
vêm exclusivamente do dump do banco original. No Caminho B elas podem faltar;
o script emite WARN e as reporta, mas **não** improvisa DDL delas.

Todas as queries/SQL rodam no container com `psql -v ON_ERROR_STOP=1` —
qualquer falha aborta o script com mensagem clara.

---

## 8. Validação final

Após schema/dados, o script valida e só termina com sucesso se tudo passar:

1. **10 tabelas esperadas**: `users`, `product`, `registry_user_product`,
   `product_source_observation`, `energy_label_class`,
   `energy_raw_measurement`, `energy_specification`, `source_metadata`,
   `source_product`, `aggregate_reference`
   - Caminho A: ausência de qualquer uma é fatal;
   - Caminho B: ausência das 4 tabelas sem DDL no repo é WARN (as demais,
     fatal).
2. **Contagens** por tabela (reportadas).
3. **Limiares**: Caminho A exige `users >= 1` e `product >= 1`; Caminho B
   exige `users >= 1` (seed), `product` só reportado.
4. **Integridade referencial**: contagem de órfãos em
   `registry_user_product → users` / `registry_user_product → product` /
   `product_source_observation → product`; qualquer órfão → erro fatal.
5. **Probe TCP host-side**: `HOST:PORTA` da URL JDBC deve aceitar conexão TCP
   a partir do host (um container com porta divergente não passa aqui).

Relatório final (senha sempre mascarada): container/ação, volume, caminho
(A/B), status do restore e do seed, tabelas presentes, conexão e JDBC
mascarados.

---

## 9. Relação com os demais artefatos

- Fonte da especificação original:
  `.agents/specs/spec-docker-postgres-frontend-units.md` (Task 1).
- Scripts legados `migrations/migrate.sh` e `migrations/migrate_remote.sh`
  **não** são alterados nem substituídos por este script.
- Teste do script: sintaxe verificada com `bash -n` (a execução completa
  depende de Docker + `.env` no ambiente de operação).
