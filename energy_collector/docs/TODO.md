# TODO

## Human
- [H][HIGH] Decidir estratégia de identificação determinística (uuid5 base usando dataset_id + brand + model + category ou combinação marca+modelo+categoria) e tamanho de lote de upsert (ex.: 5000 linhas). **Done when**: decisão documentada no TODO e aprovada por Quitto.
- [H][HIGH] Decidir criar role dedicado no Supabase com privilégio mínimo (substituir uso de superusuário postgres). (R1 risk)
- [H][MEDIUM] Executar git rm --cached data_collector.log e __pycache__/*.pyc.
- [H][MEDIUM] Atualizar .gitignore raiz com *.log, .env.*, .collector_state.json.
- [H][MEDIUM] Decidir se executar varredura completa final (final scan).

## Agent
- [A][MECHANICAL] Implementar leitor de .env com strip de espaços e suporte a DB_SSLMODE=true → sslmode=require. **Done when**: função lê .env (strip de espaços), DB_SSLMODE=true resulta em sslmode=require, DBConfig.password usa repr=False, e variáveis são disponibilizadas ao código.
- [A][MECHANICAL] Implementar pool de conexões thread-safe (psycopg_pool). **Done when**: pool criado, thread-safe, e disponibilizado via função get_connection().
- [A][MECHANICAL] Implementar ensure_table() que cria tabela product com schema definido (id UUID PK, name VARCHAR(150), brand VARCHAR(255), model VARCHAR(255), category VARCHAR(255), avg_power_w NUMERIC, annual_energy_kwh NUMERIC). **Done when**: tabela existe no banco e schema corresponde.
- [A][MECHANICAL] Implementar geração de id determinístico (uuid5) usando chave "ENERGY STAR|{source_id}" (se houver identificador oficial) ou "ENERGY STAR|{brand}|{model}|{category}" (caso contrário), canonicalizada com NFKC, casefold e colapso de whitespace. **Done when**: id gerado é consistente entre execuções para mesmo registro e diferente para registros diferentes.
- [A][MECHANICAL] Implementar normalização de registros brutos para contrato Product (mapeamento de colunas, truncamento, valores nulos, conversão de tipos). **Done when**: registros são convertidos para o contrato e valores nulos permanecem nulos.
- [A][MECHANICAL] Implementar descoberta de datasets elegíveis (filtragem dos 4x4 IDs conhecidos e dos desconhecidos usando heurística de nomes de coluna). **Done when**: lista de datasets elegíveis obtida e filtrada corretamente.
- [A][MECHANICAL] Implementar mecanismo de paginação estável com estado persistente (arquivo collector_state.json no diretório energy_collector) e suporte a retomada. **Done when**: state file salva e carregado corretamente; varredura pode retomar após interrupção sem reprocessar categorias concluídas.
- [A][MECHANICAL] Implementar tratamento de rate limit (429) com token-bucket compartilhado (~4 req/s), aguarda Retry-After 120s e usa backoff exponencial com teto. **Done when**: API 429 detectada, aguarda Retry-After, repete requisição com sucesso respeitando limites da API pública anônima.
- [A][MECHANICAL] Implementar paralelismo de fetch: 8 threads de fetch por DATASET, fila com backpressure (maxsize=32) e 4 threads escritoras usando pool psycopg_pool (psycopg 3, não psycopg2/asyncpg). **Done when**: threads executam fetch simultaneamente sem deadlock, filas mantêm backpressure e escritas são feitas de forma thread-safe.
- [A][MECHANICAL] Implementar upsert em lote (tamanho padrão 1000 linhas) com ordenação estável de chaves (UUID) para evitar deadlocks e pré-count via WHERE id = ANY(%s::uuid[]). **Done when**: upsert realiza inserções/atualizações em lote e garante idempotência.
- [A][MECHANICAL] Implementar transações curtas: commit por lote e rollback em caso de erro. **Done when**: cada lote é commitado individualmente e a base de dados permanece consistente.
- [A][MECHANICAL] Implementar logging detalhado e geração de relatório final (totais por categoria, inseridos/atualizados/descartados). **Done when**: relatório exibido ao final da execução com métricas corretas.
- [A][MECHANICAL] Implementar testes unitários para modelos e normalização (pytest). **Done when**: todos os testes passam e cobertura mínima 80%.
- [A][MECHANICAL] Adaptar código antigo do git HEAD (collector/models.py, etc.) para usar env keys reais, pool de conexões psycopg_pool e batch upsert. **Done when**: código antigo integrado, usando env real, pool psycopg_pool e batch upsert, sem alterar lógica de negócio.
- [A][MECHANICAL] Implementar suporte a retomada após interrupção (carregar state.json no diretório energy_collector e continuar fetch). **Done when**: após interrupção, retomada continua do ponto correto sem reprocessar categorias concluídas.

## Shared
- [S][REVIEW] Validar comportamento final contra Supabase (SELECT count(*) FROM product > 0, verificar campos name, brand, category, avg_power_w, annual_energy_kwh). **Done when**: teste de validação executa sem falha e dados conferem.
- [S][REVIEW] Verificar idempotência (duas execuções consecutivas sem duplicação). **Done when**: segunda execução não cria novas linhas para registros já existentes; apenas atualiza campos modificados.
- [S][REVIEW] Medir tempo total da execução completa (SC-003 < 60 min). **Done when**: cronômetro registra < 60 minutos para varredura completa em máquina de referência.
- [S][REVIEW] Realizar smoke test contra Supabase (categoria refrigerators, limit 100) e validar idempotência (duas execuções com count estável).

## Blocked

## Decisões
- [H][DECISION] Identidade determinística: uuid5(NAMESPACE_URL, chave) com chave = "ENERGY STAR|{source_id}" (se houver identificador oficial) ou "ENERGY STAR|{brand}|{model}|{category}" (caso contrário), canonicalizada com NFKC, casefold e colapso de whitespace.
- [H][DECISION] Lote de upsert: tamanho padrão 1000 linhas; ordenado por UUID antes de executemany; estatísticas via pré-count com WHERE id = ANY(%s::uuid[]).
- [H][DECISION] Paralelismo: 8 threads de fetch por DATASET, fila com backpressure (maxsize=32) e 4 threads escritoras com pool psycopg_pool (psycopg 3, não psycopg2/asyncpg).

## Completed
- [x] Scaffold de arquivos/stubs criado pelo project-bootstrap