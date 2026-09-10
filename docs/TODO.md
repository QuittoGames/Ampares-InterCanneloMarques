# TODO — Ampares Consumo (Frontend Redesign)

> Projeto: Spring Boot Java + frontend estático em `src/main/resources/static/`.
> Este TODO cobre **somente o redesign do frontend**. Backend **NÃO** deve ser alterado.
> Pesquisa dinâmica PostgreSQL/B-Tree está **fora de escopo** desta fase.

---

## Legenda

- `[H]` Human (decisão/autorização do usuário)
- `[A]` Agent (executável pelo agente)
- `[S]` Shared (compartilhado — revisão/validação)
- `[BLOCKED]` bloqueado por dependência externa
- `[CANCELLED]` cancelado

---

## Phase 0 — Auditoria (DONE)

- [x] [A] Mapear todos os arquivos frontend (HTML, CSS, JS) — feito
- [x] [A] Identificar contratos backend consumidos pelo frontend — feito
- [x] [A] Listar bugs estruturais (IDs, classes, imports) — feito
- [x] [A] Produzir design direction (pass 1 + pass 2) — feito

---

## Phase 1 — Correções estruturais (app está quebrado)

> Antes de redesenhar, **consertar o que está quebrado**.

- [x] [A][HIGH][CRITICAL] Adicionar `id="login-section"` no HTML — sem isso, `app.js:7` recebe `null` e quebra ao esconder o login
- [x] [A][HIGH] Corrigir `body { color: #222 }` (invisível sobre `#232323`) → `#F5F5F5`
- [x] [A][HIGH] Remover `header { margin-bottom: 90% }` (gap absurdo)
- [x] [A][HIGH] Corrigir `.herder h1` (typo) — apagar seletor morto
- [x] [A][HIGH] Corrigir `.content_secition` (typo "secition") — apagar
- [x] [A][HIGH] Remover `section { background: #F3C55B }` — pinta tudo de amarelo
- [x] [A][MED] Remover `h2 { width: 456px }` — quebra responsividade
- [x] [A][MED] Remover `font-family` quebrado (`'Poppins'` está OK, mas trocar para Inter — ver Phase 2)
- [x] [A][HIGH] Auditar todos os `getElementById` em `app.js` contra IDs reais no HTML

**DoD Phase 1:** `app.js` carrega sem erro de console; login → calculator funciona.

---

## Phase 2 — Design system base (style.css)

> Reescrever `style.css` aplicando a paleta e tokens definidos no Pass 1.

- [x] [A][HIGH] Definir `:root` com CSS custom properties (cores, radii, espaçamentos, motion)
- [x] [A][HIGH] Reset mínimo + `body` com bg + tipografia Inter + JetBrains Mono
- [x] [A][HIGH] Componentes utilitários: `.btn`, `.btn-primary`, `.btn-ghost`, `.input`, `.card`, `.pill-input`
- [x] [A][HIGH] Tipografia: classes `.display`, `.mono`, `.eyebrow`, `.muted`
- [x] [A][HIGH] Motion: tokens de duração + easing, respeitando `prefers-reduced-motion`
- [x] [A][HIGH] Responsividade: breakpoints mobile-first (`@media (min-width: 640px)`, `768px`, `1024px`)

**DoD Phase 2:** Style guia aplicável a todas as telas; visualmente alinhado com `reference_2.png`.

---

## Phase 3 — Login redesign

> Tela minimalista: só campo de ID + botão. Sem senha, sem email.

- [x] [A][HIGH] HTML semântico: `<main class="auth">`, `<section class="auth__card">`, form
- [x] [A][HIGH] Enter submete o form (já funciona nativamente, mas garantir)
- [x] [A][HIGH] Foco visível no input (outline amarelo `#FFCD1C`)
- [x] [A][MED] Mensagem de erro legível (não técnica)

**DoD Phase 3:** Login funciona com Enter; cookie é setado pelo backend; redireciona para calculator.

---

## Phase 4 — Calculator flow

> Fluxo: **pesquisa → seleção → configuração → cálculo → resultado**

### 4.1 Pesquisa
- [x] [A][HIGH] Search bar pill no topo da calculator
- [x] [A][HIGH] Filtragem client-side (input → filtra lista)
- [x] [A][HIGH] Estado vazio: "Digite para buscar produtos"
- [x] [A][MED] Loading state durante fetch inicial

### 4.2 Seleção de produto
- [x] [A][HIGH] Lista de produtos com nome + potência + seta
- [x] [A][HIGH] Hover/focus destaca linha (border-left amarelo)
- [x] [A][HIGH] Click seleciona e mostra card de configuração
- [x] [A][HIGH] "X" para limpar seleção

### 4.3 Configuração
- [x] [A][HIGH] Card mostra: nome do produto + potência média
- [x] [A][HIGH] Stepper de quantidade (`− N +`, min 1)
- [x] [A][HIGH] Stepper de horas (`− N h +`, min 0, step 0.5)
- [x] [A][HIGH] Botão "Calcular consumo" (pill, amarelo)
- [x] [A][HIGH] Enter no stepper também calcula

### 4.4 Resultado
- [x] [A][HIGH] Card destaque: "1,56 kWh" (display 56px) + "hoje" abaixo
- [x] [A][HIGH] Animação de entrada sutil (fade + slide 8px, 200ms)
- [x] [A][MED] Loading state: "Calculando..." durante requisições

### 4.5 Detalhamento
- [x] [A][HIGH] Lista de produtos do consumo com barra de proporção
- [x] [A][HIGH] Card "Maior consumo" com % do total
- [x] [A][MED] Caso edge: 1 produto só, 0 produtos (empty state), erro de rede

**DoD Phase 4:** Fluxo completo funciona end-to-end; visual limpo; sem poluição.

---

## Phase 5 — JavaScript refactor

> Adaptar `app.js` para o novo fluxo mantendo os endpoints.

- [x] [A][HIGH] Corrigir referência nula de `loginSection` (adicionar fallback)
- [x] [A][HIGH] Mover `getElementById` para dentro de `init()` (não no topo do módulo)
- [x] [A][HIGH] Estado reativo simples: `{ userId, products, selectedProduct, quantity, hours, result }`
- [x] [A][HIGH] `renderProducts(query)` — filtra e renderiza lista
- [x] [A][HIGH] `renderSelectedCard()` — mostra produto selecionado + steppers
- [x] [A][HIGH] `bindSteppers()` — `+`/`−` ajustam estado, atualizam display
- [x] [A][HIGH] `calculateAndRender()` — POST `/registryUserProducts` + 5 métricas + render visual
- [x] [A][MED] `formatKWh(value)` — `BigDecimal` → string formatada `1,56 kWh`
- [x] [A][MED] `renderResultCard(kwh)` — destaque principal
- [x] [A][MED] `renderBreakdown(perProduct)` — lista com barras
- [x] [A][MED] `renderTopConsumer(product, percent)` — card de maior consumo
- [x] [A][HIGH] Tratar 401/403/500 com mensagem amigável

**DoD Phase 5:** JS limpo, sem console errors; funções pequenas e nomeadas; estado centralizado.

---

## Phase 6 — Polish

- [x] [A][MED] Acessibilidade: aria-labels nos steppers, `aria-live` no resultado, foco visível em tudo
- [x] [A][MED] `prefers-reduced-motion: reduce` desativa transições
- [x] [A][LOW] Scroll interno em vez de scroll global
- [x] [A][LOW] Empty states como call-to-action (não ilustração)

**DoD Phase 6:** Acessibilidade básica respeitada; reduced-motion funciona.

---

## Phase 7 — Validação final

- [x] [A][HIGH] Console limpo: 0 errors, 0 warnings não explicados
- [x] [A][HIGH] IDs únicos em todo HTML (grep `id="`)
- [x] [A][HIGH] Classes referenciadas no CSS existem no HTML (grep cruzado)
- [x] [A][HIGH] Seletores `getElementById` em JS batem com IDs no HTML
- [x] [A][HIGH] Imports: `<link>` e `<script>` apontam para caminhos corretos
- [x] [A][HIGH] Backend não foi tocado (`git diff --stat HEAD~0`)
- [x] [A][HIGH] Testar fluxo: login → search → select → stepper → calculate → resultado → logout
- [x] [A][HIGH] Testar responsividade em 3 larguras (375px, 768px, 1280px)
- [x] [A][HIGH] Visual alinhado com `reference_2.png` (login) e brief (calculator)

**DoD Phase 7:** Tudo verificado; nada quebrado; nada faltando.

---

## Bloqueios

_Nenhum no momento._

## Backlog (fora de escopo agora)

- [ ] [H][DEFERRED] Busca dinâmica PostgreSQL com índice B-Tree / query nativa
- [ ] [H][DEFERRED] Filtros por categoria (`category`, `subcategory`) na UI
- [ ] [H][DEFERRED] Histórico de consumo (gráfico de evolução temporal)
- [ ] [H][DEFERRED] Estimativa de custo em R$ (depende de input de tarifa)
- [ ] [H][DEFERRED] Modo claro (light theme) — não pedido, manter só dark

---

## Notas de governança

- **Não tocar backend:** endpoints, services, repositories ficam intactos.
- **Não criar novos arquivos** sem justificativa (este projeto é pequeno, manter `index.html` + `app.js` + `style.css`).
- **Não instalar dependências JS** — vanilla JS, sem build step.
- **Comentários JSDoc** podem ser usados para clareza, mas não exagerar.
