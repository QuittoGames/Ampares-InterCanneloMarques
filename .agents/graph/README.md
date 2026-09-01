# Task Graph — `Ampares-InterCanneloMarques`

Persistent state for multi-agent orchestration. **Source of truth** for in-flight work.

## Structure

```
.agents/graph/
├── graph.json          # metadados do grafo (project, policies, groups)
├── tasks.json          # FONTE DE VERDADE das tasks (estado materializado)
├── decisions.json      # ADRs (decisões arquiteturais)
├── events.jsonl        # log append-only de eventos
├── evidence/           # evidências grandes (por task)
└── runs/               # metadados de execução
```

## Groups

### DOC (`docs/`)
- **Purpose:** Maintain `docs/doc.md` as professional, complete documentation.
- **Allowed:** `docs/`
- **Forbidden:** `src/`, `migrations/`, `pom.xml`, `.env`

### SWG (`swagger`)
- **Purpose:** Add Swagger UI to Spring Boot without affecting business logic.
- **Allowed:** `pom.xml`, `src/main/java/**/config/`, `src/main/resources/application.properties`, `src/main/java/**/Controllers/` (annotations only)
- **Forbidden:** `.env`, `docs/`, `migrations/`, `src/test/`

## Tasks overview

See `tasks.json`.

| Group | Task ID | Status | Priority | Description |
|-------|---------|--------|----------|-------------|
| DOC | TASK-DOC-001 | completed | high | Analisar código base |
| DOC | TASK-DOC-002 | ready | high | Definir estrutura doc.md |
| DOC | TASK-DOC-003 | ready | medium | Documentar Models |
| DOC | TASK-DOC-004 | ready | medium | Documentar Repositories |
| DOC | TASK-DOC-005 | ready | medium | Documentar Services |
| DOC | TASK-DOC-006 | ready | medium | Documentar Controllers |
| DOC | TASK-DOC-007 | ready | medium | Documentar DTOs/Exceptions |
| DOC | TASK-DOC-008 | ready | low | Documentar fórmulas |
| DOC | TASK-DOC-009 | ready | low | Documentar schema |
| SWG | TASK-SWG-001 | ready | high | Adicionar dep springdoc |
| SWG | TASK-SWG-002 | ready | high | Criar OpenApiConfig |
| SWG | TASK-SWG-003 | ready | medium | Anotações nos Controllers |
| SWG | TASK-SWG-004 | ready | medium | application.properties |
| SWG | TASK-SWG-005 | ready | high | Validar mvn compile |
| SWG | TASK-SWG-006 | ready | high | Garantir .env intacto |

## Decisions

See `decisions.json`.

- **ADR-001:** Orquestração em 2 grupos paralelos (DOC e SWG).
- **ADR-002:** Divisão de escopo por paths (allowed/forbidden).
- **ADR-003:** `springdoc-openapi-starter-webmvc-ui` para Swagger.

## Validation

```bash
python .agents/skills/graph-engineering/scripts/graph_validate.py .agents/graph
```

Exit 0 = no errors.

## Workflow

1. Workers read `tasks.json` to find `ready` tasks with no blocking dependencies.
2. Update status to `running` (in-memory; persist on completion).
3. On completion: add evidence, update status, append event.
4. On failure: register hypothesis, possibly create recovery task.
