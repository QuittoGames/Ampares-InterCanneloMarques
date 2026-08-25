# TODO

## Human

- [ ] [H][HIGH] TASK-001: Install psycopg[binary] and update requirements.txt.

- [ ] [H][HIGH] TASK-006: Review a separação Service/Integração x Normalizer. Validar se o `SocrataService` atende ao contrato desejado e decidir se o `CollectionService` deve migrar de `SocrataClient` direto para `SocrataService`.

- [ ] [H][HIGH] TASK-007: Decidir destino dos campos DERIVED (equivalent_hours_year, estimated_cost, etc.). Hoje NÃO há coluna no banco nem campo na JPA — precisam de decisão antes de persistir (o `NormalizedProduct` os mantém só em memória/rastreabilidade).

- [ ] [H][HIGH] TASK-008: Confirmar correção do bug `bghd-e2wd`: campo `annual_energy_use_kwh_yr` → `annual_energy_use_kwh_year` (coluna real da API, validada por consulta real). Isso muda o valor persistido de clothes_washers (antes None, agora o valor real).

## Agent

- [ ] [A][MECHANICAL] TASK-002: Configure SSL connection in collector/database.py (ensure sslmode=require).

- [ ] [A][MECHANICAL] TASK-004: Verify collector import, connection to Supabase, and unit tests pass.

- [ ] [A][MECHANICAL] TASK-005: (Optional) Validate db/migrations/create.sql and 0001 against Supabase.

## Shared

- [ ] [S][REVIEW] TASK-004: Review verification results and ensure no regressions.

- [ ] [S][REVIEW] TASK-009: Revisar testes de normalização/service (cobertura de casos de borda) e validar não-regressão do pipeline real contra a API.

## Blocked

- [ ] [H][BLOCKED] TASK-001: Ensure psycopg[binary] is installed before configuring DB connection.

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
