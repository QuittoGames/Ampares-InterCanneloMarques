# Specification Quality Checklist: Sistema Ampares — Catálogo Energético, Motor de Cálculo e Ingestão Multi-Fonte

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-13
**Feature**: [spec.md](../spec.md) (+ Apêndices A–D)
**Lifecycle**: checklist builtin mantido por `/speckit.specify` e `/speckit.clarify` (SpecKit 1.1.3, CLI instalado no repositório). Checklist customizado de domínio separado: [requirements-quality.md](requirements-quality.md).

**Review Ownership**: `[x]` somente quando o revisor determinar que o critério de qualidade está satisfeito; não significa implementação concluída. Itens intencionalmente gerados sem marcação.

## Content Quality

- [ ] No implementation details (languages, frameworks, APIs)
- [ ] Focused on user value and business needs
- [ ] Written for non-technical stakeholders
- [ ] All mandatory sections completed

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain
- [ ] Requirements are testable and unambiguous
- [ ] Success criteria are measurable
- [ ] Success criteria are technology-agnostic (no implementation details)
- [ ] All acceptance scenarios are defined
- [ ] Edge cases are identified
- [ ] Scope is clearly bounded
- [ ] Dependencies and assumptions identified

## Feature Readiness

- [ ] All functional requirements have clear acceptance criteria
- [ ] User scenarios cover primary flows
- [ ] Feature meets measurable outcomes defined in Success Criteria
- [ ] No implementation details leak into specification

## Notes

- **Ressalva deliberada (item "No implementation details")**: o briefing do DEV (§1, §18) exige explicitamente uma **especificação de sistema com auditoria de código rastreável** — cada afirmação sobre o estado atual deve apontar arquivo/classe/método (rótulos [CÓDIGO]/[FONTE]/[DECISÃO]/[ALVO]). A presença de referências técnicas é requisito do pedido, não vazamento acidental; o revisor decide se o balanceamento requisitos↔evidência está adequado.
- **Ressalva (item "No [NEEDS CLARIFICATION] markers remain")**: a spec usa a seção "Open Questions" com **limite de três** (OQ1–OQ3), conforme exigido pelo briefing (§16) — cada OQ lista impacto e alternativas. São pendências deliberadas de decisão do DEV, não ambiguidades não tratadas.
- Itens incompletos exigem atualização da spec antes de `/speckit.clarify` ou `/speckit.plan`.
- Baseline de auditoria: árvore de trabalho de 13/10/2026 (pós-15:57 para `User.java`); D1 (compilação quebrada por métodos órfãos) é fato de código pendente de correção em Fase C, não falha da spec.
