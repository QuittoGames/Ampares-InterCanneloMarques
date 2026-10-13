# Requirements Quality Checklist: Sistema Ampares (001-ampares-system-spec)

**Purpose**: Validar a qualidade, clareza e completude dos REQUISITOS escritos em spec.md — "unit tests for English". Não valida implementação.
**Created**: 2026-10-13
**Feature**: [spec.md](../spec.md) (+ apêndices A–D)

**Note**: Checklist gerado conforme o mecanismo `/speckit.checklist` (template `.specify/templates/checklist-template.md`, CLI SpecKit 1.1.3).
**Review Ownership**: artefato de revisão mantido pelo revisor — `[x]` significa que o critério de qualidade de requisitos foi revisado e satisfeito; não significa implementação concluída.
**Marker Semantics**: `[x]` = revisado e satisfeito para qualidade de requisitos. `/speckit.implement` lê o estado dos checkboxes como gate e não deve alterar marcadores.

## Completeness — catálogo e contratos

- [ ] CHK001 O contrato canônico do `Product` está definido campo a campo (nome, tipo, unidade, nullability) com fonte de verdade identificada? (spec FR-001; Apêndice A.2)
- [ ] CHK002 Cada campo não-canônico tem destino explícito (observação de fonte) e proibição de vazamento para `product`? (FR-002)
- [ ] CHK003 A matriz de convergência Java↔Python↔SQL↔diagrama cobre todos os campos e marca divergências pendentes? (Apêndice A.4/A.5)
- [ ] CHK004 Cada endpoint listado tem método, rota, corpo de entrada e semântica de resposta/erro definidos? (FR-025; Apêndice A.6)
- [ ] CHK005 O comportamento de todos os campos opcionais (`hoursStandby`, `subcategory`, tensão, standby) está definido quando ausentes?

## Completeness — cálculo e tarifas

- [ ] CHK006 Cada fórmula do Formula Bank define equação, variáveis, unidade de entrada/saída, hipóteses e método implementador? (Apêndice B F1–F9)
- [ ] CHK007 As convenções numéricas (365 dias, mês médio ano/12, DECIMAL128, HALF_UP 2 casas, escalas 4/6) estão declaradas e são consistentes entre spec e código? (Apêndice B; FR-014/020)
- [ ] CHK008 A separação consumo personalizado × referência da fonte está especificada com proibição de mistura/anualização dupla? (F4; SC-005)
- [ ] CHK009 O resultado de standby é definido para cada estado de dado (presente, ausente, inválido) e a semântica API (empty vs ZERO) tem decisão registrada ou pendência formal? (FR-024/FR-028; OQ2)
- [ ] CHK010 A semântica de `publishedValuePerMwh` (TUSD+TE, exclusões) está documentada com fonte e data, e o que falta (validUntil) está marcado como hipótese? (FR-021/022; Apêndice C.1.2)

## Completeness — ingestão e banco

- [ ] CHK011 A política de escrita do coletor está definida tabela a tabela (autorizadas vs proibidas) com comportamento de conflito explícito? (FR-009/FR-010; Apêndice A.2)
- [ ] CHK012 O comportamento "conflito não atualiza" tem consequência documentada (catálogo pode ficar desatualizado) e caminho futuro sem introduzir UPDATE? (OQ3)
- [ ] CHK013 A configuração de ambiente tem precedência, nomes de variáveis e incompatibilidade atual documentada sem expor credenciais? (FR-008/FR-032; Apêndice A.5 D5)
- [ ] CHK014 Idempotência e integridade referencial têm critérios verificáveis (UUIDs determinísticos, UNIQUE, re-coleta)? (FR-011; SC-003)

## Clarity / Ambiguity

- [ ] CHK015 Todo estado de evidência ([CÓDIGO]/[FONTE]/[DECISÃO]/[ALVO]/[HIPÓTESE]/[PENDÊNCIA]) está aplicado às afirmações substantivas, sem inferência apresentada como fato? (Legenda da spec)
- [ ] CHK016 Os 3 [NEEDS CLARIFICATION] são as únicas questões abertas e cada uma lista impacto e alternativas? (OQ1–OQ3)
- [ ] CHK017 Termos ambíguos do briefing ("energia por hora em standby", "média do usuário") foram resolvidos em unidades inequívocas (W vs kWh/ano; média por registro vs por unidade)? (Apêndices A/B)
- [ ] CHK018 As divergências briefing↔código estão marcadas como resolvidas/pendentes com evidência, sem tratar snapshot antigo como verdade? (Apêndice D.3)

## Consistency

- [ ] CHK019 As unidades dos endpoints (kWh/dia, kWh/ano, R$/dia, R$/ano, valor anual de standby) são consistentes entre interface `MetricsService`, hub, controllers e ResultDTO? (Apêndice B.10; FR-025)
- [ ] CHK020 O contrato null/empty (DECISÃO 004) é consistente entre serviço (Optional.empty) e controllers (hoje `.orElse(ZERO)`) — e a divergência está registrada com estado alvo pendente? (FR-028)
- [ ] CHK021 As faixas de validação (horas [0,24], quantidade ≥1, potência >0) são idênticas em DTO, serviço, motor e HourService? (FR-015/016/029)

## Coverage — cenários e casos-limite

- [ ] CHK022 Cada critério de aceitação (SC-001…SC-012) é mensurável e verificável sem ambiguidade?
- [ ] CHK023 Os casos-limite do briefing (§15: derivadas, 200W×5h×2, não-anualização, ×12 mensal, quantidade vs soma, médias, nulos, standby, tarifa, vigência, OQ1, lista vazia, FK/duplicidade, conflito coletor, INMETRO ausente, tensão, idempotência) estão todos mapeados em requisitos/testes? (B.11)
- [ ] CHK024 Cenários de usuário (Stories 1–6) são independentemente testáveis com Given/When/Then?

## Edge cases e segurança

- [ ] CHK025 Comportamento definido quando: fonte externa indisponível (429), banco sem migrations, tarifa nula/zerada, vigência incoerente, horas >24 legadas, produto sem potência? (Edge Cases da spec; Apêndice D.4)
- [ ] CHK026 Requisitos não-funcionais de segurança (sem segredos em logs/spec, role restrito, sem DDL em produção, testes offline) estão presentes e verificáveis? (FR-009/032/033; SC-003)

## Traceability

- [ ] CHK027 Os 12 requisitos mínimos do briefing (§14) estão rastreáveis para FRs/SCs (tabela D.6) e as fases A–G cobrem o plano de evolução com critérios de conclusão? (Apêndice D.5)
- [ ] CHK028 Toda afirmação sobre código aponta arquivo/classe/método e toda afirmação externa aponta URL + organização + data de consulta? (Apêndices B/C)

## Notes

- Itens pendentes de revisão devem permanecer `[ ]` até avaliação do revisor (DEV ou reviewer designado).
- Este checklist é insumo direto para `/speckit.clarify` (resolver OQ1–OQ3 antes de `/speckit.plan`).
