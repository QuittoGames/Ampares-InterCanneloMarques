# Feature Specification: Energy Star Scraper (povoamento do catálogo de produtos)

**Feature Branch**: `001-energy-star-scraper`
**Created**: 2026-08-24
**Status**: Draft
**Input**: User description: "Criar um web scraper Python que varre todos os produtos da API pública ENERGY STAR (Socrata, https://data.energystar.gov, acesso anônimo) e povoa o banco PostgreSQL (Supabase) usado pelo servidor Java Spring, na tabela `product` (id UUID gerado na inserção, name, brand, category, avg_power_w NUMERIC, annual_energy_kwh NUMERIC). O modelo de dados inclui a tabela intermediária `userproduct` (M:N User↔Product), mas o código Java não a utiliza — o scraper não deve tocá-la. Arquitetura modular simples (Services, Models, Database), Python 3.14+, pip global, leitura de credenciais do `.env` em `D:\Projects\Java\Ampares-InterCanneloMarques\.env` (DB_HOST, DB_USERNAME, DB_PASSWORD, DB_PORT, DATABASE, DB_SSLMODE). Multithreading para máxima velocidade (Xeon E5-2650v3, 10 núcleos físicos, Windows), com concorrência/async onde evitar deadlocks nos inserts."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Povoar o catálogo de produtos (Priority: P1)

O desenvolvedor executa o coletor na máquina local para encher a tabela `product` do banco do projeto com todos os produtos certificados ENERGY STAR disponíveis publicamente, sem intervenção manual por categoria e sem credenciais da API (consumidor anônimo).

**Why this priority**: Sem catálogo populado, a aplicação Java não tem dados de produtos para funcionar. É a razão de existir da feature.

**Independent Test**: Executar o coletor com banco vazio e verificar que a tabela `product` termina populada com dezenas de milhares de registros válidos e que o relatório final informa totais (recebidos/inseridos/atualizados/descartados).

**Acceptance Scenarios**:

1. **Given** o banco com a tabela `product` vazia, **When** o coletor executa uma varredura completa, **Then** todos os datasets elegíveis do catálogo ENERGY STAR são percorridos e os registros válidos aparecem em `product` com `name`, `brand`, `model`, `category` preenchidos e métricas de energia quando a fonte as fornece.
2. **Given** fontes de dados públicas e heterogêneas (datasets com esquemas diferentes), **When** um registro não tem identificação mínima (sem ID estável nem marca+modelo+categoria), **Then** ele é descartado com registro em log, sem abortar a varredura.
3. **Given** o banco do projeto Java (Supabase), **When** o coletor grava, **Then** os dados ficam imediatamente legíveis pela aplicação Java na mesma tabela `product` (mesma tipagem e nomes de coluna).

---

### User Story 2 — Reexecução segura e idempotente (Priority: P2)

O desenvolvedor reexecuta o coletor (diariamente/semanalmente) para atualizar o catálogo. Nenhuma linha é duplicada: produtos já conhecidos são atualizados; novos são inseridos.

**Why this priority**: O catálogo ENERGY STAR é atualizado diariamente pela EPA; o povoamento não pode ser operação destrutiva nem duplicadora.

**Independent Test**: Executar o coletor duas vezes seguidas e verificar que a segunda execução reporta apenas atualizações (ou zero alterações) e que a contagem total de linhas não aumenta indevidamente.

**Acceptance Scenarios**:

1. **Given** um catálogo já populado, **When** o coletor reexecuta, **Then** o número de linhas permanece estável e produtos alterados na fonte têm seus valores atualizados.
2. **Given** um produto presente na fonte em duplicidade natural (abas/versões), **When** normalizado, **Then** gera sempre a mesma identidade determinística e colapsa em uma única linha.

---

### User Story 3 — Retomada após interrupção e operação reversível (Priority: P3)

O desenvolvedor interrompe uma varredura longa (queda de rede, limite de requisições) e consegue retomar sem perder o progresso nem corromper o banco.

**Why this priority**: Varredura anonimizada está sujeita a rate limits e falhas; sem retomada, cada falha obriga recomeçar do zero.

**Independent Test**: Interromper uma execução no meio e retomar; verificar que a varredura continua sem reprocessar categorias concluídas e que o banco nunca fica com transações parciais.

**Acceptance Scenarios**:

1. **Given** uma execução interrompida, **When** retomada, **Then** o trabalho continua dos pontos pendentes e o estado final é equivalente a uma execução contínua.
2. **Given** uma falha de escrita em um lote, **When** o erro ocorre, **Then** apenas aquele lote é desfeito/logado e as demais categorias seguem.

### Edge Cases

- Dataset do catálogo que não é produto certificado (metadados/índices) → ignorado automaticamente.
- Dataset sem campos de energia/potência → registros gravados com métricas nulas (nunca valores inventados).
- Limite de requisições da API (HTTP 429) → recuo exponencial e espera indicada pelo servidor; varredura não aborta.
- Credenciais/ausência de `.env` legível → falha rápida com mensagem clara, antes de qualquer escrita.
- Campos de texto maiores que os limites da tabela (ex.: nome > 150 caracteres) → truncamento/log, nunca erro de banco.
- Concorrência de escrita → nenhum deadlock observável em execução completa (transações curtas, lotes isolados, ordenação estável de chaves dentro do lote).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema DEVE descobrir automaticamente os datasets de produtos certificados disponíveis no catálogo público ENERGY STAR, sem exigir cadastro, conta ou token da API.
- **FR-002**: O sistema DEVE percorrer cada dataset elegível de forma completa e determinística (paginação estável), até esgotar seus registros.
- **FR-003**: O sistema DEVE normalizar cada registro bruto para o contrato do produto: `name`, `brand`, `model`, `category`, `avg_power_w`, `annual_energy_kwh`; campos ausentes na fonte ficam nulos.
- **FR-004**: O sistema DEVE gerar a identidade `id` do produto no momento da inserção, de forma determinística a partir de chave estável do registro (identificador oficial do modelo ou combinação marca+modelo+categoria), garantindo idempotência entre execuções.
- **FR-005**: O sistema DEVE persistir por escrita idempotente: registro novo insere, registro existente atualiza; nunca duplica.
- **FR-006**: O sistema DEVE garantir a existência da estrutura de destino compatível com o contrato do banco do projeto (tabela `product`: `id` UUID PK, `name` VARCHAR(150), `brand`/`model`/`category` VARCHAR(255), `avg_power_w`/`annual_energy_kwh` NUMERIC), sem alterar outras tabelas.
- **FR-007**: O sistema DEVE executar coleta e gravação com paralelismo real (múltiplas threads) explorando os 10 núcleos da máquina, com escrita segura contra deadlocks.
- **FR-008**: O sistema DEVE ler as credenciais exclusivamente do arquivo de ambiente do projeto servidor (`DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `DB_PORT`, `DATABASE`, `DB_SSLMODE`), sem segredos no código, e exigir conexão criptografada quando o ambiente pedir.
- **FR-009**: O sistema DEVE tolerar falhas transitórias da fonte (rede, HTTP 429, 5xx) com nova tentativa automática e recuo progressivo, e registrar falhas definitivas sem interromper o restante da varredura.
- **FR-010**: O sistema NÃO DEVE escrever em `userproduct` nem em `users`; o escopo de escrita é exclusivamente a tabela `product`.
- **FR-011**: O sistema DEVE emitir relatório final com totais por categoria (recebidos, inseridos, atualizados, descartados) e log auditável.
- **FR-012**: O sistema DEVE completar a varredura sem intervenção manual por dataset: conhecidos usam mapeamento verificado de campos; novos/desconhecidos usam extração genérica por heurística de nomes de coluna.

### Key Entities

- **Product** (destino, espelha o banco e o diagrama `docs/arquiteture.drawio`): `id` UUID gerado na inserção; `name` (composto marca+modelo quando a fonte separa); `brand`; `model`; `category` (categoria lógica do dataset de origem); `avg_power_w` NUMERIC (potência média em watts, somente quando a fonte a fornece); `annual_energy_kwh` NUMERIC (consumo anual, somente quando a fonte o fornece).
- **Dataset de origem** (fonte, somente leitura): conjunto de dados público Socrata/ENERGY STAR identificado por código 4x4, com dezenas de colunas heterogêneas por categoria de produto; o sistema mapeia apenas as colunas relevantes ao contrato do Product.
- **UserProduct** (fora de escopo): tabela intermediária M:N (`user_id`, `product_id`, `quantity`, `avg_active_hours`, `hours_standby`) que representa o USO de produtos por usuário — preenchida pela aplicação Java, nunca pelo coletor.

## Success Criteria *(mandatory)*

- **SC-001**: Uma execução completa cobre 100% dos datasets elegíveis descobertos no catálogo (≥ 45.000 modelos de produtos certificados persistidos, ordem de grandeza do catálogo ENERGY STAR atual).
- **SC-002**: Reexecução imediata após varredura completa resulta em 0 linhas duplicadas (somente atualizações/no-ops).
- **SC-003**: A varredura completa com paralelismo conclui em menos de 60 minutos na máquina de referência, sem intervenção manual, e é mensuravelmente mais rápida que a execução sequencial.
- **SC-004**: Nenhuma linha persistida viola as regras de domínio: identificação estável presente, sem métricas negativas, sem texto excedendo os limites do contrato.
- **SC-005**: A aplicação Java consegue ler os dados gravados sem nenhuma adaptação de schema (mesma tabela, mesmos tipos e nomes de coluna).
- **SC-006**: Falhas transitórias de rede/limite de API não abortam a varredura: retomada ou nova execução convergem para o mesmo estado final.

## Assumptions

- **A1 — Escopo "todos os produtos"**: significa todos os datasets do catálogo público ENERGY STAR (~53 atualmente) que representem produtos certificados com identificação de marca/modelo. Metadatasets (ex.: índice de modelos, tabela de UPCs) são ignorados.
- **A2 — `avg_power_w` sem conversão inventada**: quando a fonte fornece apenas consumo anual (kWh), a potência média fica nula em vez de ser estimada. Esta é a decisão documentada do projeto (coletor anterior): nunca converter métricas entre si por heurística. Pode ser revista no futuro (kWh/ano ÷ 8,76 = W médio é matematicamente válido, mas muda a semântica do campo).
- **A3 — `userproduct`**: existe no modelo (drawio) e como entidade Java, mas nenhum caminho de acesso a dados do Java a usa; o coletor não a popula.
- **A4 — Idempotência por identidade determinística**: o `id` é derivado da chave estável do registro; consequência aceita: se a fonte mudar o identificador oficial de um mesmo modelo, uma nova linha pode surgir (considerado produto novo).
- **A5 — Consumidor anônimo**: a API pública aceita acesso sem token com limites de taxa; o coletor respeita `Retry-After` e recuo exponencial. Token opcional (`SOCRATA_APP_TOKEN`) apenas eleva o teto de requisições.
- **A6 — `.env` legado**: o arquivo do servidor usa `DB_USERNAME`/`DATABASE` (o Java espera `DB_USER`/`DB_NAME` — divergência conhecida do projeto); o coletor lê os nomes realmente presentes no `.env` informado, tolera espaços residuais após `=` e trata `DB_SSLMODE=true` como exigência de conexão criptografada.
- **A7 — Ambiente**: Windows, Python 3.14+, instalação de dependências via pip global; máquina com 10 núcleos físicos justifica paralelismo agressivo com lotes grandes de escrita.

## Out of Scope

- Povoar `users` ou `userproduct`.
- API REST, interface visual ou agendamento (cron/Task Scheduler) — o coletor é um executável manual/CLI.
- Coleta de outras fontes além do catálogo público ENERGY STAR.
- Correções no servidor Java (ex.: repository com derivadas inválidas, divergência de nomes do `.env`) — apenas reportadas, não alteradas.
