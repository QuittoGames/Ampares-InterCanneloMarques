# TODO

## Human

- [ ] [H][HIGH] TASK-001: Install psycopg[binary] and update requirements.txt.

- [ ] [H][HIGH] TASK-006: Review a separação Service/Integração x Normalizer. Validar se o `SocrataService` atende ao contrato desejado e decidir se o `CollectionService` deve migrar de `SocrataClient` direto para `SocrataService`.

- [ ] [H][HIGH] TASK-007: Decidir destino dos campos DERIVED (equivalent_hours_year, estimated_cost, etc.). Hoje NÃO há coluna no banco nem campo na JPA — precisam de decisão antes de persistir (o `NormalizedProduct` os mantém só em memória/rastreabilidade).

- [ ] [H][HIGH] TASK-008: Confirmar correção do bug `bghd-e2wd`: campo `annual_energy_use_kwh_yr` → `annual_energy_use_kwh_year` (coluna real da API, validada por consulta real). Isso muda o valor persistido de clothes_washers (antes None, agora o valor real).

- [ ] [H][HIGH] TASK-033: (DEV) Revisão final da auditoria energética, aprovação dos resultados e autorização de commit — não fazer commit/push sem solicitação. Depends on: TASK-032.

- [x] [H][HIGH] TASK-001: Install psycopg[binary] and update requirements.txt. **(Feito 13/10/2026: psycopg 3.3.6 + psycopg-pool 3.3.3 instalados via `pip install --user`; requirements.txt já listava ambos.)**
  Depends on: TASK-032.

- [x] [H][HIGH] TASK-034: (DEV) Aplicar migrations 005 (contrato canônico + proveniência na observação) e 006 (energy_label_class com A+++ + aggregate_reference) — e o `create.sql` atualizado — no banco real, COM backup e plano de recuperação, antes de habilitar import ao vivo. O coletor é INSERT-ONLY e não executa DDL: sem as migrations, `verify_schema()` falha rápido. **Done when**: migrations aplicadas em banco real e `verify_schema` passa. **(Feito 13/10/2026 sob autorização do DEV: backup `backups/neondb_backup_20261013_162001.dump` (pg_dump -Fc, verificado com pg_restore -l); 005 e 006 aplicadas com `psql -1 -v ON_ERROR_STOP=1`; 006 inclui upgrade idempotente do CHECK ENCE para A+++; dados existentes preservados 251/143/21; `verify_schema` OK.)**
  Depends on: TASK-032.

- [x] [H][HIGH] TASK-035: (DEV) Criar role restrito no Postgres (INSERT em product/product_source_observation/energy_label_class/aggregate_reference + SELECT para pre-count de duplicatas) e usar no `.env` do coletor, substituindo o superusuário `postgres`. **Done when**: coletor conecta e grava com o role restrito. **(Feito 13/10/2026 sob autorização do DEV: role `ampares_collector` LOGIN (senha aleatória), GRANT USAGE no schema public + SELECT,INSERT nas 4 tabelas — UPDATE/DELETE comprovadamente NEGADOS; `.env` recebeu `DB_URL` do role (chaves do Spring preservadas; backup em `.env.bak_20261013`).)**
  Depends on: TASK-034.

- [x] [H][MEDIUM] TASK-036: (DEV) Decidir cadência de atualização da tabela PBE (XLSX versionado pelo INMETRO; versão verificada 12/11/2021) e se novas categorias (condicionadores etc.) entram — mesmo padrão de página `inmetro.gov.br/CONSUMIDOR/pbe/*.asp` com parser por categoria. **Done when**: cadência documentada e escopo de categorias decidido. **(Feito 13/10/2026: decisão registrada em `.agents/decisions/decision_008.json` — cadência manual sob demanda com checagem da nota de versão do XLSX; só refrigeradores ativos; novas categorias = tasks futuras com parser próprio.)**
  Depends on: none.

- [x] [H][MEDIUM] TASK-037: (DEV) Autorizar e executar o primeiro import real (`python data_collector.py --source inmetro --all`), revisando o preview de contagens (recebidos/inseridos/duplicatas/descartados) e auditando observações com tensão declarada antes de liberar para o app. **Done when**: import real executado, contagens auditadas e dados visíveis no app com proveniência. **(Feito 13/10/2026: 1ª execução 542 recebidos / 2 inseridos / 1 duplicata / 0 descartados; 2ª execução 0 inseridos / 3 duplicatas — idempotência real provada; banco: 253 product, 685 observações (266 @127 V + 276 @220 V), 3 ENCE; achado: linha canônica Geladeira legada (id b03224d6) com avg_power_w=150 genérico da era antia de média e annual=NULL — correção proposta em TASK-038.)**
  Depends on: TASK-034, TASK-035.

- [ ] [H][MEDIUM] TASK-038: (DEV) Corrigir a linha canônica legada "Geladeira" (id `b03224d6-390e-55a5-9ea8-93d8f62bc65c`) criada pela regra ANTIGA de média (carrega `avg_power_w=150` genérico WattSimple e `annual_energy_kwh=NULL`, apesar de 361 observações INMETRO elegíveis anexadas). Correção proposta (executar somente com autorização):
  ```sql
  UPDATE product
  SET avg_power_w = NULL,  -- PBE não declara potência; genérico não pode restar no canônico
      annual_energy_kwh = (SELECT round(avg(o.annual_energy_kwh), 2)
                           FROM product_source_observation o
                           WHERE o.canonical_product_id = product.id
                             AND o.source = 'INMETRO'
                             AND o.annual_energy_kwh IS NOT NULL)
  WHERE id = 'b03224d6-390e-55a5-9ea8-93d8f62bc65c';
  ```
  **Done when**: linha canônica reflete só especificações brasileiras elegíveis (power NULL, annual = média INMETRO) OU decisão explícita de manter.
  Depends on: TASK-037.

- [x] [H][HIGH] TASK-044: (DEV) Decidir e provisionar o ambiente de banco do Spring Boot. FALHA: startup de `InterdisciplinarApplication` aborta com `BeanCreationException 'entityManagerFactory'` → `Unable to open JDBC Connection` → `Connection refused` em `localhost:5432` (netstat sem LISTEN na porta; sem serviço Postgres no Windows; Docker/podman/psql/pg_ctl ausentes no Windows e nas distros WSL paradas). `spring.datasource.url` aponta para `localhost:5432/neondb` (ddl-auto=update); as credenciais `DB_USER`/`DB_PASSWORD` existem no `.env`. O ConditionEvaluationReport longo no log é só `debug=true` (application.properties:18) — não é o problema. Opções: (A) Postgres local via `scripts/setup_postgres_docker.sh` — requer instalar/habilitar Docker Desktop (hoje ausente); (B) Postgres nativo do Windows na porta 5432 com database `neondb` (dados das migrations 005/006 aplicadas em 13/10/2026 — TASK-034/037 — não estão neste host; considerar restaurar backup `backups/neondb_backup_20261013_162001.dump` ou reimportar via coletor); (C) apontar a URL JDBC para o Neon cloud — provavelmente inadequado: o único role disponível é `ampares_collector` (INSERT-only em 4 tabelas, TASK-035) e `ddl-auto=update` exige DDL; mudar a URL afeta contrato de configuração. NÃO alterar `application.properties`/`.env` sem decisão explícita. **(RESOLVIDO 15/10/2026 — opção A aprovada pelo DEV: Docker Desktop reinstalado (engine 29.2.1); `setup_postgres_docker.sh` executado (Caminho B, container `neondb-local`, postgres:18, volume `neondb_local_data`) — 4 tabelas do coletor ausentes no repo (DDL só existia no dump perdido, WARN esperado); como o banco Neon cloud ainda estava vivo com dados, fez-se `pg_dump` dele (`backups/neon_db_backup_20261015_174603.dump`, 40KB) e `pg_restore` limpo (DROP SCHEMA public CASCADE + restore): 10 tabelas, product=251, obs=143, users=5, rup=16. App sobe e responde HTTP 200 em /swagger-ui.html e /v3/api-docs.)**
  **(Recoleta executada 15/10/2026 sob autorização do DEV: `energy_collector/.env` criado com `DB_URL` local (`sslmode=disable`, senha percent-encoded — `.env` raiz usa CRLF, `Substring` ingênuo incluía `\\r` e quebrava auth); migrations 005+006 aplicadas no banco local (dump do Neon não as tinha — coluna `is_generic` inexistente derrubava a gravação); `python data_collector.py --source inmetro --all` → 542 recebidos / 0 inseridos / 3 duplicatas / status ok (idempotência reprovada); contagens finais: product=253, obs=685 (542 INMETRO), ence=3 — iguais ao estado pré-perda. products_sem_obs=231 esperado: products legados do pipeline Socrata sem observações de proveniência.)**
  Done when: opção decidida e registrada, com Postgres acessível em `localhost:5432/neondb` (ou config decidida e aplicada) e credenciais conferentes às chaves do `.env`.

- [ ] [H][MEDIUM] TASK-046: (DEV, opcional) Decidir se implementa melhoria de diagnóstico quando o banco está inacessível (ex.: fail-fast com mensagem clara indicando host/porta/banco esperados e como subir o Postgres, em vez do stack trace bruto do Hikari no startup). Envolve mudança de comportamento de inicialização — decisão do DEV; se aprovada, criar task [A] de implementação com escopo delimitado. Registrado a partir do incidente da TASK-044.
  Done when: decisão registrada (implementar ou rejeitar, com motivo).

## Agent

- [ ] [A][MECHANICAL] TASK-002: Configure SSL connection in collector/database.py (ensure sslmode=require).

- [ ] [A][MECHANICAL] TASK-004: Verify collector import, connection to Supabase, and unit tests pass.

- [ ] [A][MECHANICAL] TASK-005: (Optional) Validate db/migrations/create.sql and 0001 against Supabase.

- [ ] [A][DATABASE] TASK-018: Auditoria READ-ONLY do banco local (Postgres localhost/neondb): identificar qual pipeline populou a tabela `product` (modelo específico do pipeline legado vs linha CANONICAL de média do multi_source), contagens por origem/fonte, nulos em avg_power_w/annual_energy_kwh, duplicatas, cobertura de product_source_observation, presença da coluna subcategory. Entregar análise de registros afetados antes de qualquer escrita. Não revelar credenciais.
  Done when: relatório com contagens reais e comandos usados; nenhuma escrita executada.

- [ ] [A][BUG] TASK-019: Diagnosticar o erro de produção no registry de produto (front + back). Candidatos do codebase-explorer: (A) login auto-register cria usuário com OUTRO ID e o front guarda o digitado → 500 em POST /registryUserProducts; (B) ausência de @ControllerAdvice → 400/500 sem mensagem legível no app.js; (C) UUID manual inválido → 400 sem dizer o campo; (D) numberFromForm → NaN → null; (E) coluna subcategory dependente de Hibernate/dump (ddl-auto=update) vs create.sql. Ver logs/reprodução disponíveis.
  Done when: causa raiz confirmada com evidência (log ou reprodução) e escopo de correção definido; se não for confirmável aqui, ranking justificado + exatamente o que o DEV precisa fornecer (status/body HTTP real).

- [ ] [A][RESEARCH] TASK-020: Avaliar o adaptador INMETRO/PBE: cobertura real de categorias, campos disponíveis (kWh/mês, tensão quando existir), disponibilidade da fonte; delimitar o que é verificável vs genérico. Priorizar tabela oficial INMETRO/PBE e informações dos fabricantes; registrar limitações.
  Done when: relatório de cobertura e limitações documentado, sem inventar dados; conclusão utilizável para TASK-021.

- [ ] [A][DECISION] TASK-021: Gerar proposta técnica em .agents/specs/ para aprovação do DEV: (1) contrato de cálculo diário/anual/já-declarado — convenção 365 dias explícita, unidades, semântica de horas ativas/standby, quantities contadas uma vez, entrada ausente/inválida nunca gera estimativa silenciosa; (2) evolução compatível do modelo de dados para características elétricas (tensão: monovolt/bivolt/faixa declarada/desconhecida + proveniência por fonte/modelo/unidade/período, sem atribuir tensão universal nem converter 220→127); (3) opções de configuração de tarifa R$/kWh (DEFAULT_TARIFF_PER_KWH=None preservado; sem tarifa nacional inventada). Separar FACT/PROPOSAL/UNKNOWN.
  Done when: spec com critérios de aceitação verificáveis, pronta para TASK-022/TASK-023.

- [ ] [A][BACKEND] TASK-024: Corrigir o contrato diário→anual no Java: ConsumptionCalculator (fator de dias quando o input é horas/dia), ConsumeMetricsService (calculateTotalEnergyByUser/calculateAverageEnergyByUser/standby com período coerente — hoje soma valor diário em variável "consumeInYear"), MetricsController (documentação dos endpoints com período correto), sem anualização dupla de energia já declarada anual. BigDecimal em todo cálculo. Respeitar quitto-java-style.
  Depends on: TASK-022.
  Done when: cenários §7 de consumo diário/anual passam (1000W/4h/1 → 4 kWh/dia, 1460 kWh/ano; 100W/5h/2 → 1 e 365); contrato dos endpoints explícito; sem regressão.

- [ ] [A][FRONTEND] TASK-025: Atualizar app.js para exibir o período correto (diário vs anual) conforme contrato aprovado — hoje rotula "Consumo total anual"/"Média anual em standby" sobre valores diários.
  Depends on: TASK-024.
  Done when: UI exibe kWh/dia e kWh/ano com o rótulo correto; cenários §7 verificados na interface.

- [ ] [A][BUG] TASK-026: Implementar a correção do erro de registry confirmado em TASK-019 (inclui @ControllerAdvice com status/mensagem adequados, guarda de UUID/formulário e correção do fluxo de login/ID conforme o diagnóstico — sem mudar comportamento não confirmado).
  Depends on: TASK-019.
  Done when: fluxo de registro de produto funciona de ponta a ponta; 400/500 exibem mensagem útil no front; testes de controller passam.

- [ ] [A][BACKEND] TASK-027: Implementar o custo anual estimado (R$) no fluxo de custo existente: consumo anual × tarifa, BigDecimal (Java) e Decimal (Python), tarifa de configuração explícita ou parâmetro do usuário, tarifa ausente/inválida → resultado explicitamente ausente (nunca conta aparentemente válida), sem ×365 sobre energia já anual, sem aplicar tarifa duas vezes; diferenciar energia estimada da conta completa da concessionária (sem impostos/bandeiras/encargos). Inspecionar compute_estimated_cost e DEFAULT_TARIFF_PER_KWH no coletor.
  Depends on: TASK-023, TASK-024.
  Done when: 1460 kWh × R$ 0,90 = R$ 1314,00 passa; tarifa None não gera custo; tarifa não aplicada em dobro.

- [ ] [A][DATABASE] TASK-028: Migração SQL versionada e idempotente para a evolução aprovada em TASK-022 (campos elétricos/proveniência e separação entre especificação verificada de modelo, referência genérica e estatística agregada), compatível com dados existentes, preservando IDs, relacionamentos e observações de origem; com plano de recuperação. Nunca apagar/recriar tabelas.
  Depends on: TASK-022, TASK-018.
  Done when: migração aplicada em ambiente de teste, rollback validado, dados preservados, instruções de execução registradas.

- [ ] [A][TEST] TASK-030: Criar testes de regressão §7 (Java + Python): consumo diário/anual (cenários exatos 1000W/4h/1 e 100W/5h/2; quantidade; horas zero; campos ausentes/inválidos; ativo vs standby; consumo anual já declarado sem anualização dupla); custo anual (1460 × 0,90 → 1314,00; tarifa ausente/inválida; diário não vira anual; tarifa nunca em dobro); fontes/tensão (tensão comprovada; bivolt/múltiplas tensões; desconhecida; americano sem equivalência; referência genérica; fontes não comparáveis; consumo mensal → anual exatamente uma vez; reimportação idempotente sem duplicação).
  Depends on: TASK-022.
  Done when: suíte nova verde e testes existentes preservados.

- [ ] [A][TEST] TASK-031: Executar as suítes completas e registrar resultados reais (nunca presumir): `./mvnw test` (Postgres local ativo) e `cd energy_collector && python -m pytest tests/ -q`.
  Depends on: TASK-024, TASK-026, TASK-027, TASK-028, TASK-030.
  Done when: resultados (passed/failed/blocked) registrados por comando, incluindo falhas e comandos que não puderam rodar.

- [x] [A][BUG] [FRONTEND] TASK-039: (frontend-feira) Remover o código morto de busca em `src/main/resources/static/app.js` — BUG que quebra o script inteiro: `productSearch = document.getElementById('product-search')` retorna null (elemento foi removido do HTML) e `productSearch.addEventListener('input', ...)` lança TypeError, impedindo o registro dos handlers de login e do restore de sessão. Remover: `SEARCH_DEBOUNCE_MS`, `searchDebounceTimer`, `searchRequestSeq`, `productSearch` + seu addEventListener, `handleSearchInput`, `searchProducts`, `filterProductsLocally`. PRESERVAR: `state.products`, `normalizeProducts`, `loadProducts`, `renderProducts` (este último continua consumindo `state.products`). Escopo: SOMENTE `app.js`. **(Feito 13/10/2026: código morto de busca removido do app.js; `node --check` exit=0; grep de regressão zero ocorrências; preservados state.products/normalizeProducts/loadProducts/renderProducts.)**
  Done when:
  - `node --check src/main/resources/static/app.js` retorna exit 0 (se node indisponível, registrar `not_available` — não presumir).
  - Grep por `productSearch|SEARCH_DEBOUNCE|searchDebounceTimer|searchRequestSeq|handleSearchInput|searchProducts|filterProductsLocally|product-search` no `app.js` retorna ZERO ocorrências.
  - `state.products`, `normalizeProducts`, `loadProducts` e `renderProducts` presentes e íntegros.
  - Carregamento do script não lança mais TypeError (handlers de login/restore registram).
  - Nenhum arquivo fora de `app.js` alterado por esta task.
  Depends on: none.

- [x] [A][FRONTEND] TASK-040: (frontend-feira) Fluxo de login para feira em `index.html` + `app.js` + `style.css`. Decisões do DEV já tomadas — implementar exatamente: **(Feito 13/10/2026: input #user-id oculto por padrão (hidden sem required); logo do card virou button#auth-id-toggle com aria-expanded/controls + foco automático + Esc; CTA único "Começar agora" com 3 ramos (revelado+preenchido / revelado+vazio+validação / oculto→ID aleatório crypto); #generate-id-button, handleGenerateId e .auth__button--secondary removidos; copy de sessão expirada atualizada.)**
  (a) Esconder o input manual de ID (`#user-id`): o visitante vê SÓ o CTA principal. O input fica num container com atributo `hidden` por padrão; como `.auth__id-row` usa `display: flex`, é necessária regra CSS explícita (ex.: `.auth__id-row[hidden] { display: none; }`) — o `hidden` nativo não vence `display: flex`.
  (b) Logo do card de login (`.auth__brand`) vira `<button type="button">` com `aria-expanded` e `aria-controls` apontando ao container do input; clique alterna (revela/oculta); ao revelar, foco automático no `#user-id`; Esc oculta e devolve foco ao botão-toggle. Estilo do botão-toggle coerente com a identidade existente (dark #232323 + âmbar #FFB812 — NÃO trocar paleta); `:focus-visible` já coberto pelo reset global.
  (c) CTA do login renomeado para **"Começar agora"** (hoje "Continuar"). Comportamento do submit: se o input estiver revelado E preenchido → loga com o ID digitado; se o input estiver revelado E VAZIO → exibir mensagem de validação no JS e NÃO submeter (interpretação que reconcilia "senão gera ID" com "validação vira mensagem quando revelado e vazio" — mensagem sem bloqueio seria incoerente); se o input estiver oculto (com ou sem valor residual) → gera ID aleatório (faixa 1.000.000–9.999.999, `crypto.getRandomValues`) e loga. Remover o atributo `required` do `#user-id` (senão a validação nativa bloqueia o submit com campo oculto).
  (d) Remover `#generate-id-button` ("Gerar ID") do HTML e `handleGenerateId` do JS — coerente com "visitante vê SÓ o CTA principal"; `generateRandomUserId` é REUTILIZADO pelo submit (manter). Remover junto o bloco CSS `.auth__button--secondary` (fica órfão EXCLUSIVAMENTE por causa desta mudança — não é limpeza de classe legada pré-existente).
  (e) Mensagem de erro de restore: 'Sessão expirada. Gere um ID ou digite o seu.' → 'Sessão expirada. Toque em Começar agora.'
  Escopo: SOMENTE os 3 arquivos em `src/main/resources/static/`; worktree já contém refactor não-commitado do DEV — NÃO descartar/alterar nada fora do escopo.
  Done when:
  - Input `#user-id` oculto por padrão; o login mostra somente o CTA "Começar agora" (sem input, sem botão "Gerar ID").
  - Toggle da logo com `aria-expanded`/`aria-controls` corretos; revela com foco no input; Esc oculta e devolve foco.
  - Submit conforme (c): revelado+preenchido → ID digitado; revelado+vazio → mensagem de validação sem submit; oculto → ID aleatório gerado (1.000.000–9.999.999 via `crypto.getRandomValues`) e login executado.
  - `required` removido do `#user-id`; nenhuma validação nativa bloqueia submit com campo oculto.
  - Mensagem de sessão expirada atualizada conforme (e).
  - `#generate-id-button`, `handleGenerateId` e `.auth__button--secondary` removidos; `generateRandomUserId` preservado e usado pelo submit.
  - CSS: container oculto some de fato (`display: none`); nenhuma cor nova introduzida (paleta âmbar/dark intacta).
  - `node --check src/main/resources/static/app.js` retorna exit 0.
  Depends on: TASK-039.

- [x] [A][FRONTEND] [ACCESSIBILITY] TASK-041: (frontend-feira) Copy e contraste — ajustes de texto/acessibilidade SEM mudar comportamento: (1) subtitle do login: "Entre com seu ID ou gere um novo para acompanhar seu consumo de energia" → **"Veja quanto seus aparelhos consomem de energia."** (sem menção a ID/gere); (2) contraste: `.auth__subtitle` em `style.css` passa de `var(--text-muted)` (#8A8A8A, 3.8:1) para `var(--text-soft)` (#BFBFBF) — mínimo WCAG 4.5:1 sobre #303030; (3) remover o `placeholder="Deixe vazio para calcular"` do `#hours-standby` em `index.html` (o badge "opcional" `.config__hint` já existe); (4) header do app: label "usuário" → **"ID"** (prefixo "ID" antes do número em `#current-user-id`). Escopo: `index.html` + `style.css` (nenhuma mudança em `app.js`). **(Feito 13/10/2026: subtitle "Veja quanto seus aparelhos consomem de energia."; .auth__subtitle/.message/.results__empty → --text-soft (detector Impeccable: low-contrast 2→0); placeholder #hours-standby removido; header "usuário"→"ID".)**
  Done when:
  - Subtitle do login exibe a nova copy, sem menção a ID/gere.
  - `.auth__subtitle` usa `var(--text-soft)`; grep confirma `--text-muted` ausente nessa regra.
  - `#hours-standby` sem `placeholder`; badge "opcional" permanece.
  - Header exibe "ID" como label do número (ex.: `ID 1234567`).
  - Nenhuma cor/paleta nova; `node --check` do `app.js` permanece verde (sem toque no JS).
  Depends on: TASK-040.

- [x] [A][FRONTEND] [TEST] TASK-042: (frontend-feira) Validação técnica final do trabalho das TASK-039/040/041. Executar e REGISTRAR resultados reais (nunca presumir): (1) `node --check src/main/resources/static/app.js` (exit 0 ou `not_available` documentado); (2) greps de regressão: zero ocorrências de `product-search`/símbolos mortos de busca, `generate-id-button`, `handleGenerateId`, `.auth__button--secondary` nos 3 arquivos estáticos; (3) executar o detector do Impeccable: `/home/quitto/.config/opencode/skills/impeccable/scripts/impeccable detect --json` e registrar o resultado; (4) revisar `git diff -- src/main/resources/static/` apontando que SOMENTE os 3 arquivos do escopo receberam estas mudanças (o worktree já estava sujo com refactor do DEV — não é culpa deste trabalho; NÃO usar `git checkout`/`restore`/`clean` em nada). **(Feito 13/10/2026: node --check passed (exit 0); greps de regressão passed (zero); git diff restrito aos 3 arquivos; `impeccable detect` executado — 2 low-contrast corrigidos, 4 restantes = identidade visual/legado F-01 (não tratados por autoridade); smoke de navegador = not_run → TASK-043.)**
  Done when:
  - Todos os comandos executados com resultado registrado (passed/failed/not_available) — nada presumido.
  - Greps zerados nos 3 arquivos.
  - Saída do detector Impeccable registrada no relatório de retorno ao DEV.
  - Diff dos 3 arquivos revisado: só mudanças do escopo, paleta âmbar/dark intacta, nenhum arquivo fora de `src/main/resources/static/` tocado por este trabalho.
  Depends on: TASK-040, TASK-041.

- [x] [A][MECHANICAL] TASK-045: Verificação pós-provisionamento do ambiente de banco da TASK-044 (reexecutável, sem alterar código). Executar e REGISTRAR resultados reais por comando (passed/failed/not_available — nada presumido): (1) porta 5432 ativa (`netstat -ano | findstr :5432` com LISTEN) e processo dono identificado; (2) subir o app (`./mvnw spring-boot:run` ou run da `InterdisciplinarApplication`) e confirmar que o bean `entityManagerFactory` sobe SEM `BeanCreationException`/`Connection refused` (grep no log por "Tomcat started" e ausência de PSQLException de startup); (3) validar que `ddl-auto=update` completa sem erro de DDL; (4) smoke mínimo: endpoint raiz/health responde 200. Se falhar, registrar causa sem 'consertar' ambiente (voltar à TASK-044). NÃO alterar `application.properties`, `.env` ou código — qualquer mudança de config é escopo do DEV. **(Feito 15/10/2026: (1) PASSSED — porta 5432 LISTEN (container neondb-local); (2) PASSED — app do DEV no ar em 8081 + tentativa via mvnw confirmou único erro restante = PortInUse (entityManagerFactory criada sem PSQLException — o bind da porta vem depois do EMF); (3) PASSED — ddl-auto=update sem erro no startup; (4) PASSED — /swagger-ui.html HTTP 200 e /v3/api-docs HTTP 200 (40445 bytes).)**
  Depends on: TASK-044.
  Done when: todos os 4 passos executados com resultado registrado; app sobe com EntityManagerFactory criada e log de evidência anexado ao retorno.

- [x] [A][FRONTEND] TASK-047: (frontend-feira) Portar a estrutura de `test.html` para `index.html` COM as restrições de produção: **(Feito 15/10/2026 via code-implementer: hr + .result_btn (#calculate-button fora de section.result) + .results-box com os dois section.result; #front-loader (SVG Uiverse BEM-scoped, hidden, role=status) antes dos scripts; defer em /units.js → /app.js; validação: greps de escopo OK, hierarquia confirmada por leitura.)** NÃO copiar o banner "Modo teste (mock)"; NÃO adicionar `mock-api.js`; manter caminhos absolutos (`/style.css`, `/units.js`, `/app.js`) com `defer` preservando a ordem units.js → app.js. Após `</main>`: `<hr style="width: 80%;">`, `<div class="result_btn">` envolvendo `#calculate-button` (movido para FORA de `section.result`), `<div class="results-box">` envolvendo os dois `<section class="result">`. Adicionar overlay `#front-loader` (Circuit Board Loader do Uiverse, HTML SVG fornecido na spec) no body antes dos scripts.
  Done when: HTML de `index.html` bate estruturalmente com `test.html` (menos as restrições de produção); IDs `#user-products`/`#results`/`#calculate-button` preservados; `#front-loader` presente e oculto por padrão.

- [x] [A][FRONTEND] TASK-048: CSS do loader + animação de entrada dos resultados em `style.css`: **(Feito 15/10/2026: bloco .front-loader (overlay fixed z-100, card com tokens, traces scoped, keyframe frontLoaderFlow) + resultsItemEnter com --enter-delay; anexado após o prefers-reduced-motion global, que permanece intacto; grep confirmou zero classes genéricas do Uiverse no escopo global.)** overlay `#front-loader` (fixed, centralizado, `--bg-overlay`, z-index > 10, fade com `--duration`/`--ease-out`, escondido via `[hidden]`); CSS do Circuit Board Loader 100% escopado sob `#front-loader` (`.loader`, `.trace-bg`, `.trace-flow` com dasharray 40/400, dashoffset 438 e `@keyframes flow` 3s, classes de cor `--yellow/--blue/--green/--purple/--red` com cores originais do Uiverse); keyframes de entrada escalonada para `.results__item`/`.results__empty` (fade + translateY curto, delay via `--enter-delay`). Respeitar o `prefers-reduced-motion` global.
  Done when: nenhuma classe genérica (`.loader`, `.yellow` etc.) vaza no escopo global; tokens do design system usados onde couber; animação de stagger funcional com `--enter-delay`.

- [x] [A][FRONTEND] TASK-049: `createTimerForFront()` no `app.js`: **(Feito 15/10/2026: FRONT_MIN_WAIT_MS=1400, delay/showFrontLoader/hideFrontLoader, createTimerForFront com Promise.all + hide no finally; calculateResults usa a função preservando 'Calculando...', 404 e mensagens; stagger --enter-delay (60ms×índice) via metricRow(rowIndex)/renderUserProducts/showTextResult; node --check exit 0. Nota: sleep(1000) pré-existente removido do fluxo — função sleep() em app.js:55 ficou sem uso, DEV decidir remoção.)** constante `FRONT_MIN_WAIT_MS = 1400`; `delay(ms)`; refs/`showFrontLoader`/`hideFrontLoader` (hidden + classe `is-visible` com transição curta e guarda); `createTimerForFront(fetchTask, minMs)` = show → `Promise.all([fetchTask(), delay(minMs)])` → hide em `finally` → retorna dados. `calculateResults()` usa a função (POST `/api/metrics/users/calculate`), preservando `showTextResult('Calculando...')`, 404 e mensagens de erro. Stagger: setar `--enter-delay` (60ms × índice) em `metricRow` (recebendo index), `renderUserProducts` e `showTextResult`.
  Done when: `node --check src/main/resources/static/app.js` exit 0; loader some mesmo em erro; comportamento de mensagens/erros idêntico ao atual; `handleRegistrySubmit` herda o loader via `calculateResults`.

- [ ] [S][REVIEW] TASK-050: Smoke test manual no navegador pelo DEV após TASK-047..049: (1) layout com botão "Calcular resultado" em `.result_btn` acima de `.results-box` com os dois cards lado a lado; (2) clicar em Calcular → overlay com chip animado aparece; (3) loader some ao terminar o tempo/back e os itens de resultado aparecem com entrada escalonada; (4) registrar produto → mesmo fluxo; (5) modo sem backend/mock preservado em `test.html` (não afetado); (6) paleta âmbar/dark intacta.
  Done when: checklist (1)–(5) verificado com evidência; divergências reportadas antes de ajustes.

## Shared

- [ ] [S][REVIEW] TASK-004: Review verification results and ensure no regressions.

- [ ] [S][REVIEW] TASK-009: Revisar testes de normalização/service (cobertura de casos de borda) e validar não-regressão do pipeline real contra a API.

- [ ] [S][DATABASE] TASK-029: Normalização/correção dos dados existentes no banco a partir da auditoria TASK-018 e do plano aprovado: executar PRIMEIRO em modo simulação com contagem de registros afetados, backup/rollback e validação pós-execução; nenhuma atualização destrutiva em massa sem plano validado; preservar IDs, registros e rastreabilidade de origem.
  Depends on: TASK-018, TASK-022.
  Done when: plano aprovado pelo DEV; correção executada com contagens registradas (analisados/corrigidos/preservados/pendentes) ou explicitamente adiada.

- [ ] [S][REVIEW] TASK-032: Validação ponta a ponta: busca de produtos, cadastro de aparelhos, registro de hábitos de uso e endpoints de métricas — valores e períodos corretos na UI; separação entre referências genéricas e modelos reais visível; não-regressão geral.
  Depends on: TASK-031.
  Done when: checklist §8 verificado item a item com evidência.

- [ ] [S][REVIEW] TASK-043: (frontend-feira) Smoke test manual no navegador pelo DEV, validando o fluxo de feira de ponta a ponta após TASK-042: (1) carga limpa mostra SÓ o CTA "Começar agora" no card de login (sem input visível, sem botão "Gerar ID"); (2) clicar no CTA loga com ID aleatório gerado e entra no app; (3) clicar na logo do card revela o input COM FOCO automático (aria-expanded=true); (4) Esc oculta o input e devolve foco à logo; (5) input revelado + ID digitado → loga com esse ID; (6) input revelado + vazio + CTA → mensagem de validação, sem submeter; (7) recarregar com sessão salva → restore automático funciona (bug TASK-039 corrigido); (8) header exibe "ID <número>"; (9) subtitle com nova copy e contraste legível; (10) "sair" volta ao login; (11) identidade visual dark #232323 + âmbar #FFB812 preservada (sem azul, sem troca de paleta). 
  Depends on: TASK-042.
  Done when: checklist (1)–(11) verificado item a item com evidência; divergências reportadas ao DEV antes de qualquer ajuste.

## Blocked

- [ ] [H][BLOCKED] TASK-001: Ensure psycopg[binary] is installed before configuring DB connection.

- [ ] [H][BLOCKED] TASK-022: (DEV) Aprovar o contrato de cálculo (convenção 365 dias, unidades, semântica de standby) e a evolução do esquema elétrico/proveniência propostos em TASK-021. Depends on: TASK-021.

- [ ] [H][BLOCKED] TASK-023: (DEV) Decidir a estratégia de tarifa R$/kWh (configuração explícita × parâmetro do usuário; DEFAULT_TARIFF_PER_KWH=None preservado; sem tarifa nacional fixa inventada) — proposta em TASK-021. Depends on: TASK-021.

## Completed

- [x] [A] TASK-000: (placeholder)

- [x] [A] TASK-010: Criar `collector/services/socrata_service.py` — camada de integração que abstrai URL/dataset/paginação/limites/offset/erros HTTP/retries/parsing/metadados, retornando dados CRUZ da API (fetch/fetch_page/count).

- [x] [A] TASK-011: Refatorar `collector/normalization.py` — normalização segura/determinística: tipos (incl. `"100,5"`), valores vazios, strings, equivalências óbvias de campos de potência/energia. Adicionar `normalize_record()` retornando `NormalizedProduct` (SOURCE + DERIVED). Manter `normalize()` compatível (retorna `Product`).

- [x] [A] TASK-012: Adicionar cálculos derivados em `normalization.py` — `equivalent_hours_year` (1000*E/P), `equivalent_hours_year_day` (H/365), `estimated_daily_energy_kwh` (E/365), `estimated_cost` (E*tarifa). Divisão por zero tratada (None).

- [x] [A] TASK-013: Adicionar `NormalizedProduct` em `collector/models.py` separando SOURCE DATA (raw_*) de DERIVED DATA (equivalent_*/estimated_*), compondo `Product` (contrato de escrita intacto).

- [x] [A] TASK-014: Corrigir bug de mapeamento `bghd-e2wd` em `config.py` (`annual_energy_use_kwh_year`). Adicionar `DEFAULT_TARIFF_PER_KWH` (tarifa explícita, None por padrão).

- [x] [A] TASK-015: Criar `tests/test_normalization.py` (39 testes) — tipos, vazios, strings, campos de energia, derivados, divisão por zero, não-descarte de campo desconhecido.

- [x] [A] TASK-016: Criar `tests/test_socrata_service.py` (14 testes) — resposta válida/vazia, erro HTTP, timeout, paginação múltiplas páginas, dataset inexistente, malformada (mocks).

- [x] [A] TASK-017: Executar pipeline real contra API Socrata (TVs + refrigeradores) — 0 descartados, extração de avg_power_w/annual_energy_kwh preservada.

## Out-of-Scope Findings

Registro de achados fora do escopo atual (frontend-feira, TASK-039..043). NÃO executar sem autorização explícita do DEV; podem virar tasks futuras se o DEV decidir.

- **F-01 — Classes CSS órfãs em `style.css`**: `.stepper` (+ `__btn/__value/__unit`), `.result-hero` (+ `__label/__value/__unit/__period/--enter`), `.breakdown` (+ `__list/__item/__row/__name/__value/__bar/__bar-fill`), `.search` (+ `__icon/__input`), `.products` (+ `__list/__item/__name/__meta/__power/__arrow/__empty/__loading`), `.top-consumer` (+ `__label/__name/__meta/__percent`) não têm uso no `index.html` atual (legado de UIs anteriores). Decisão do DEV: registrar, NÃO remover neste escopo. Sugestão: task futura de limpeza de CSS legado após smoke test confirmar não-regressão visual.
- **F-02 — (observação relacionada) `.app-message` / `.app-message--error`** em `style.css` também estão sem uso no HTML atual (o HTML usa `message`/`auth__message`) — mesma natureza do F-01, mesma recomendação: fora do escopo atual, remover somente com autorização.
- **F-03 — (nota) `.auth__id-row` permanece em uso** após TASK-040 como container do input revelável — NÃO é órfã; ao contrário de `.auth__button--secondary`, que fica órfã por causa direta da TASK-040 e é removida nela.
