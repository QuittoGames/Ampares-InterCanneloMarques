# Apêndice D — Estado Atual vs. Desejado, Decisões, Divergências e Plano de Evolução

**Spec principal**: [spec.md](spec.md) · **Data**: 2026-10-13 · Estados de evidência conforme legenda da spec.

## D.0 Contexto de auditoria

- Estado auditado: **árvore de trabalho** de 13/10/2026 sobre o commit `c70d48e` (12/10/2026) — há alterações locais extensas não commitadas (`git status`: ~45 arquivos modificados/deletados).
- Baseline de testes executado nesta auditoria: **Java 176 testes / 0 falhas — BUILD SUCCESS** (`./mvnw test` ~15:51); **Python 290 passed**. ⚠ O baseline Java **antecede** a edição de `User.java` às 15:57 (D1): a árvore atual não compila até remover os métodos órfãos — próxima suíte real deve ser re-executada após a correção. [CÓDIGO + javac 13/10/2026]
- Cache `.agents/protocol/docs/codebase-explorer.json` aponta `c70d48e` — **stale** em relação à árvore (atualizar só após estabilizar, Fase G).
- Constituição SpecKit (`.specify/memory/constitution.md`) ainda é **template sem ratificar** —Spec Kit foi inicializado nesta execução (não existia `.specify/` antes).

## D.1 Arquitetura — estado atual vs. desejado

| Tema | Estado atual (FACT salvo indicação) | Estado desejado (ALVO) |
|---|---|---|
| Hub de cálculo | `ConsumeMetricsService` é o hub implementador de `MetricsService`; `ConsumptionCalculator` é a camada primitiva estática (Formula Bank); **nenhum `UnsupportedOperationException` restante** — todos os 8 métodos implementados | Manter hub; absorver/resolver `RegistryCalculator` @Deprecated e métodos LEGADOS (`calculate` null→ZERO; `calculateDailyActiveHours` sem q/sem faixa) — OQ aberto da DECISÃO 001 (sobrevive como primitiva ou é eliminado) |
| Navegação `User` | DECISÃO 003 aplicada pela metade (13/10 15:57): `@OneToMany`/campo/imports **removidos** ✔; métodos órfãos `set/add/removeRegistryUserProduct` (l.45-92) **sobreviveram** → `User.java` não compila (javac) — **D1** | Concluir a 003: remover os 3 métodos órfãos e corrigir callers; listagem via `getProductsRegistrys` do hub (`UserService.findAllProductrs` já delega) |
| Serialização | Entities expostas: `ResponseEntity<Product>`, `List<RegistryUserProduct>`, `ResultDTO.productsList` (records com entidades dentro); risco de ciclo User↔RegistryUserProduct mitigado apenas por LAZY | DTOs de resposta explícitos sem entidades JPA; sem ciclos (FR-026) |
| Erros HTTP | Sem `@ControllerAdvice`/`@ExceptionHandler` — exceções viram 500 genérico; `Optional.empty()` de standby/média vira `ZERO` no controller (`.orElse(BigDecimal.ZERO)`) | `@ControllerAdvice` com status por exceção (400/404/409/503); semântica de vazio explícita por endpoint (FR-027/FR-028 — decisão do DEV) |
| Tarifa | `TariffService` valida vigência de valor **configurado** (default em código, override opcional); `VALID`/`OUTDATED`; exceção se ausente/zerada; **sem** atualização dinâmica | Fase D decide: manter só referência configurada vs. histórico/atualização controlada; rotular sempre "estimativa de referência" |
| Standby | Hub retorna `Optional.empty()`; motor pronto (`standbyDaily/Annual/Cost`); insumo existe em `product_source_observation.standby_power_w` (e datasets externos p/ TVs) | OQ2 decide insumo (observação vs campo canônico); API deixa de converter `empty()`→0 (FR-028) |
| Coletor | INSERT-only completo: `verify_schema` (leitura), 4 INSERTs `DO NOTHING`, sem DDL/UPDATE/DELETE, lotes ordenados anti-deadlock, `users`/`registry_user_product` intocados — divergência histórica do briefing **já resolvida na árvore** | Manter política; definir fluxo futuro controlado de atualização de catálogo (OQ3) |
| Banco único | PostgreSQL local `neondb` compartilhado (Java e coletor via config); `.env` do projeto pai com chaves `DB_USER`/`DB_PASSWORD` — **incompatível com o contrato do coletor** (`DB_HOST`/`DB_USERNAME`/`DB_PASSWORD`/`DATABASE` ou `DB_URL`/`DATABASE_URL`); sem `docker-compose.yml` | `.env` reconciliado (nomes); role restrito INSERT-only (TASK-035); infra Docker decidida pelo DEV (hoje não existe artefato) |
| Schema | Migrações versionadas (004/005/006 + create.sql canônico) + Hibernate `ddl-auto=update` em paralelo (segunda fonte); migração órfã `add_avg_idle_energy_for_hour.sql` | Migrações como única fonte; `ddl-auto` apenas dev ou desativado; remover/arquivar migração órfã com decisão OQ2 |
| Frontend | `app.js` estático consome endpoints; `docs/TODO.md` registra redesign próprio (fora de escopo) | Exibe períodos/rótulos corretos (TASK-025); nunca recalcula fórmulas autoritativas |

## D.2 Registro de decisões (DECIDIDO)

| ID | Decisão | Efeito na spec |
|---|---|---|
| 001 | Hub unificado no `ConsumeMetricsService`; `ConsumptionCalculator`/`RegistryCalculator` alvo de absorção; tarifa permanece componente separado | FR-013; Apêndice B |
| 002 | Escopo DEV×agentes (DEV dono do ecossistema Metrics; suite baseline 86 testes em 13/10/2026 — hoje 176) | Governança das fases |
| 003 | `User` sem coleção; lista via `getProductsRegistry` do hub | FR-026; Divergência D1 |
| 004 | Contrato null/empty/throw: nunca null; listas vazias válidas; `Optional.empty()` vs exceção de domínio; streams; static puro; standby nunca usa potência ativa; `annualEnergyKwh` nunca ×365; unidades diário= kWh/dia, anual=kWh/ano, standby=**valor anual**; `avg` com curinga (limitação conhecida) | FR-014/015/017/019; Apêndice B |
| 005 | `HoursProvider` removido; `HourService` com `Hday = Hactive + Hstandby`; null≠0; >24h = inconsistência | FR-016 (nota: decisão citava `interfaces/HoursService` + `HoursServiceImpl`; implementação real = `Services/Metrics/HourService.java` como `@Service` concreto — divergência cosmética registrada) |
| 006 | Hub exclui registros inconsistentes dos 4 agregados via `hasComputableActiveInputs`; inconsistente nunca vira ZERO nem derruba os demais; sem válidos → `Optional.empty()` → 404; `productsList` mantém tudo | FR-017; Story 2 |
| D3 (predecessora) | Tarifa com defaults em código + override opcional (evita editar `application.properties` em uso pelo DEV) | FR-021 |

## D.3 Divergências briefing (snapshot antigo) ↔ código atual — resoluções verificadas

| Tema do briefing | Snapshot do briefing | Estado real (13/10/2026) |
|---|---|---|
| `database.py` com `ensure_table()`/DDL/`DO UPDATE` | Contradizia o alvo INSERT-only | **RESOLVIDO**: sem DDL (`verify_schema` só lê), 4× `ON CONFLICT DO NOTHING`, sem UPDATE/DELETE [CÓDIGO `database.py`] |
| `migrations/create.sql` sem `subcategory` | Faltava campo | **RESOLVIDO**: 8 colunas canônicas + observação com proveniência [CÓDIGO] |
| Drawio com `avg_idle_energy_for_hour` ambíguo | Campo/semântica pouco claros | **RESOLVIDO**: campo removido do diagrama; standby está na observação com nome inequívoco `standby_power_w` (W) [CÓDIGO] |
| `Product.java` sem `subcategory` | — | **RESOLVIDO**: `subcategory` presente [CÓDIGO `Product.java:24`] |
| Métodos de métricas com `UnsupportedOperationException` | Pelo menos 7 pendentes | **RESOLVIDO**: todos implementados e testados (20 testes no hub) |
| `removeRegistryUserProduct` mistura UUID/índice; `addRegistryUserProduct` NPE | Defeitos potenciais | **OBSOLETO pela DECISÃO 003**: `@OneToMany`/campo removidos em 13/10 (métodos órfãos restantes quebram compilação — D1); a navegação de listagem correta é o hub |
| Horas de standby derivadas `24 − ativo` | Contradizia a spec do registro | **RESOLVIDO no fluxo ativo**: `RegistryUserService`/conversor nunca derivam; `RegistryCalculator.computeHoursStandbyPerDay` (derivação) sobrevive **apenas** na classe @Deprecated |
| Fonte única Enel | Enel Rio (1061,10) vs Enel SP (789,38) | **MIGRADO** para Enel SP, verificado na fonte [FONTE]; OQ1 pendente de aceite formal |

## D.4 Pendências e riscos (não bloqueiam a spec; alimentam o plano)

1. **Risco — serialização de entidades** (ciclo User↔RegistryUserProduct) em produção: mitiga-se com DTOs (FR-026). Severidade: alta se LAZY falhar em contexto não-transacional (`LazyInitializationException` — documentado no javadoc de `User`).
2. **Risco — 500 genérico** em falhas de domínio (sem `@ControllerAdvice`): UX quebrada no front (TASK-019/026).
3. **Risco — semântica ZERO vs indisponível** nos endpoints de standby/média (FR-028): número aparentemente calculado.
4. **Risco — `.env` incompatível** com o coletor (D5) + role de banco ainda superusuário (TASK-035).
5. **Risco — dados legados inconsistentes** (316,12 h/dia) visíveis em `productsList` (por decisão 006) e limpeza pendente (TASK-029).
6. **Fluxo legado quebrado por contrato**: `UserService.addProduct` chama `createRegistry(..., null, null)` → hoje lança `InvalidRegistryException` (avgActiveHours obrigatório) — o caminho antigo de `addProduct` não pode registrar sem horas; `removeProduct` obtém o registro mas **não deleta** (no-op). Registrar para a Fase C. [CÓDIGO `UserService.java:40-71`]
7. **Precisão Python**: `_to_decimal` passa por `float` intermediário (aceitável para dado de fonte; reavaliar se surgirem valores > 2^53 ou extremos). [CÓDIGO `normalization.py:179-194`]
8. **`UserService.create()`** cria usuário "test <uuid>" — helper de teste dentro do serviço de produção (higiene de código, Fase C). [CÓDIGO `UserService.java:106-113`]
9. **Compilação quebrada (D1)**: métodos órfãos de `User.java` referenciam campo/import removidos às 15:57 — qualquer `./mvnw test`/`compile` real falha até a remoção dos 3 métodos (correção trivial, Fase C; não executar nesta etapa de spec). [CÓDIGO: javac 13/10/2026]

## D.5 Plano de evolução (fases — registrar na spec; NÃO implementar agora)

### Fase A — Auditoria e contrato (base executada nesta spec; restante: aplicar)
- Reconciliado nesta spec: `Product.java` ↔ DDL Python ↔ `create.sql` ↔ drawio (matriz A.4); decisões 001–006 localizadas; rotas/DTOs/testes auditados; estado Git registrado.
- **Restante**: aplicar migrações 004–006 + `create.sql` no banco real **com backup e plano de recuperação** (TASK-034); reconciliar DDL legado vs dados existentes (TASK-018); decidir destino da migração órfã (OQ2).
- Critério de conclusão: schema real = canônico; `verify_schema` passa; auditoria READ-ONLY entregue.

### Fase B — Integridade dos cálculos
- Fonte de verdade única por fórmula (Apêndice B); separação personalizado/referência (já no código); OQ1 fechado com aceite do DEV; unidades/escala/rounding nos testes.
- Critério: cenários F1–F9 verdes com unidades verificadas; nenhum ×365 duplicado (teste dedicado).

### Fase C — Modelo JPA e serviços
- Completar DECISÃO 003 (remoção do `@OneToMany`/campo já feita em 13/10; remover os 3 métodos órfãos que quebram a compilação e corrigir callers); centralizar consulta no repositório; resolver fluxo legado `addProduct`/`removeProduct`; DTOs de resposta sem entidades/ciclos; `@ControllerAdvice` com mapa de status; semântica de vazio por endpoint (FR-028); absorção final do `RegistryCalculator` (OQ da DECISÃO 001); higiene (`UserService.create()` de teste).
- Critério: suíte verde; sem serialização de entidade nos contratos HTTP; erros mapeados.

### Fase D — Tarifas
- Documentar status/validade e semântica TUSD+TE (feito — Apêndice C); região/classe/modalidade corretas; decidir referência configurada vs histórico/atualização dinâmica (não existe hoje).
- Critério: todo custo carrega metadados; `OUTDATED` nunca exibido como vigente; decisão de evolução registrada.

### Fase E — Coletor e persistência
- Impedir DDL (já feito — manter com testes); política INSERT-only aprovada (OQ3); tabelas autorizadas listadas; caminho futuro de atualização documentado; role restrito + `.env` reconciliado (TASK-035); SSL conforme TASK-002.
- Critério: coletor grava com role mínimo; repetição idempotente; nenhum toque em `users`/`registry_user_product` (teste).

### Fase F — Fonte brasileira
- INMETRO: manter XLSX oficial como transporte (verificado); decidir cadência de versão (TASK-036) e novas categorias; WattSimple: tratar como benchmark genérico com fallback para indisponibilidade (429 observado); ENERGY STAR: confirmar campos a cada ingestão.
- Critério: import real auditado (TASK-037) com contagens recebidos/inseridos/duplicatas/descartados; nenhuma fonte genérica/estrangeira marcada como brasileira.

### Fase G — Consistência e documentação
- Atualizar drawio/docs após decisões; rodar suítes; após estabilizar, atualizar `.agents/protocol/docs/codebase-explorer.json` via mecanismo real (`persist_artifact.py` — **confirmar existência do script antes de usar**; não localizado nesta execução) validando JSON e sem segredos.
- Critério: cache descreve o estado pós-mudança (commit novo); documentação das fontes sem Supabase obsoleto (D7).

## D.6 Traçabilidade briefing → spec

| Requisito do briefing (§14) | Cobertura |
|---|---|
| 1. Catálogo canônico consistente | FR-001…FR-005; SC-001; Apêndice A |
| 2. Procedência | FR-002/003; SC-002; Apêndice C |
| 3. Normalização segura | FR-006/007/011; SC-003; B.11 |
| 4. Banco único autoritativo | FR-008…FR-010; SC-003; D.1 |
| 5. Cálculo dimensionalmente correto | FR-014; SC-004/005; Apêndice B |
| 6. Precisão decimal | FR-020; SC-006 |
| 7. Standby correto | FR-024 (Story 5); SC-007; OQ2 |
| 8. Tarifa rastreável | FR-021…FR-024; SC-008/011; Apêndice C |
| 9. API consistente | FR-025…FR-031; SC-009 |
| 10. Ranking e agregação | FR-017…FR-019; SC-010 |
| 11. Teste reproduzível (OQ1) | B.12; SC-011; SC-012 |
| 12. Docs sincronizados | FR-036; Fase G; D.3 |
