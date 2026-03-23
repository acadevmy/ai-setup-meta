---
name: setup
description: Setup agent per innestare il workflow AI-Native in qualsiasi progetto (greenfield o esistente)
user-invocable: true
disable-model-invocation: true
---

# /project:setup

Setup agent per innestare il workflow AI-Native in qualsiasi progetto.
Scarica le risorse da ai-setup-meta e le applica in modo adattivo.

**Uso**: `/project:setup` (senza argomenti)

---

## Configurazione sorgente

```
SOURCE_REPO: acadevmy/ai-setup-meta
SOURCE_BRANCH: main
```

Il fetch dei file avviene tramite `gh api` (GitHub CLI), che gestisce automaticamente
l'autenticazione e funziona anche con repo privati. Il developer deve essere autenticato
con `gh auth login`.

## File da scaricare

| Path nel repo sorgente | Descrizione |
|---|---|
| `templates/dev-setup-template/CONSTITUTION.md` | Regole di governance |
| `templates/dev-setup-template/AGENT.template.md` | Istruzioni agente (template unico con placeholder) |
| `templates/dev-setup-template/.claude/settings.json` | Permessi Claude Code |
| `templates/dev-setup-template/.claude/skills/start-task.md` | Skill start-task |
| `templates/dev-setup-template/.claude/skills/tdd.md` | Skill TDD (backend) |
| `templates/dev-setup-template/.claude/skills/bdd.md` | Skill BDD (frontend) |
| `templates/dev-setup-template/.claude/skills/review.md` | Skill review |
| `templates/dev-setup-template/.claude/skills/sync-task.md` | Skill sync-task |
| `templates/dev-setup-template/.claude/agents/clickup.md` | Agent ClickUp (operazioni task) |
| `templates/dev-setup-template/.claude/agents/review.md` | Agent Review (code review isolata) |
| `templates/dev-setup-template/REGISTRY.md` | Template registro progetto |
| `profiles/web-frontend.md` | Profilo Web Frontend |
| `profiles/backend-node.md` | Profilo Backend Node |
| `profiles/mobile.md` | Profilo Mobile |

---

## Procedura completa

Esegui i passi seguenti **nell'ordine indicato**. Non saltare nessun passo.

### Passo 1 — Rileva la modalita'

Analizza il progetto corrente per determinare la modalita' operativa:

1. **UPDATE** — Se esistono gia' `CONSTITUTION.md` E `.claude/settings.json` nella root del progetto, il setup e' stato gia' eseguito. Chiedi allo sviluppatore: "Il setup e' gia' stato eseguito. Vuoi aggiornare i file dal repository sorgente?" Se risponde no, fermati.

2. **GREENFIELD** — Se NON esiste nessuno di questi file nella root del progetto: `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `pubspec.yaml`, `Cargo.toml`, e non ci sono file sorgente significativi (nessun file `.ts`, `.js`, `.py`, `.go`, `.dart`, `.rs` al di fuori di config). Il progetto e' vuoto o appena inizializzato.

3. **EXISTING** — In tutti gli altri casi. Il progetto ha codice esistente.

Comunica la modalita' rilevata allo sviluppatore prima di procedere.

---

### Passo 2 — Auto-detection stack (solo modalita' EXISTING)

Se la modalita' e' EXISTING, analizza il progetto per rilevare:

#### Linguaggio
- `package.json` presente → **node**
- `pyproject.toml` o `requirements.txt` o `setup.py` presente → **python**
- `go.mod` presente → **go**
- `pubspec.yaml` presente → **flutter**
- `Cargo.toml` presente → **rust**
- Nessuno dei precedenti → **unknown**

Possono coesistere piu' linguaggi (es. node + python).

#### Test runner
Cerca nell'ordine:
1. `package.json` con script `test` → se contiene `vitest` usa `npx vitest`, altrimenti `npm test`
2. `pytest.ini` o `pyproject.toml` con `[tool.pytest]` → `pytest`
3. `go.mod` → `go test ./...`
4. `pubspec.yaml` → `flutter test`
5. `Cargo.toml` → `cargo test`
6. Nessuno trovato → `non rilevato`

#### Linter
Cerca nell'ordine:
1. File `.eslintrc*` o `eslint.config*` o `eslint` in `package.json` → se c'e' script `lint` usa `npm run lint`, altrimenti `npx eslint .`
2. `pyproject.toml` con `[tool.ruff]` → `ruff check .`
3. `.flake8` o `setup.cfg` con `[flake8]` → `flake8`
4. `.golangci.yml` → `golangci-lint run`
5. `analysis_options.yaml` → `dart analyze`
6. `Cargo.toml` → `cargo clippy`
7. Nessuno trovato → `non rilevato`

#### Tool di validazione
1. `package.json` con: `zod` → **Zod**, `joi` → **Joi**, `yup` → **Yup**, `class-validator` → **class-validator**
2. `pyproject.toml` o `requirements.txt` con `pydantic` → **Pydantic**
3. Nessuno trovato → `non rilevato`

#### Frontend rilevato?
- `package.json` contiene `next`, `react`, `@angular/core`, `vue`, `nuxt`, o `svelte` → **si**
- Oppure: esistono file `.tsx`, `.jsx`, o `.vue` in `src/` → **si**
- Altrimenti → **no**

#### Mobile rilevato?
- `pubspec.yaml` presente → **si**
- `package.json` contiene `react-native` o `expo` → **si**
- Altrimenti → **no**

**Mostra il riepilogo della detection allo sviluppatore** in questo formato:
```
Stack rilevato:
  Linguaggi:   node
  Test runner:  npm test
  Linter:       npm run lint
  Validazione:  Zod
  Frontend:     si
  Mobile:       no
```

---

### Passo 2b — Selezione stack (solo modalita' GREENFIELD)

Se la modalita' e' GREENFIELD, chiedi allo sviluppatore di scegliere lo stack:

1. **Web Frontend** — Next.js / Angular / React + ShadCN/UI + Tailwind
2. **Backend Node** — Node.js / NestJS + Prisma + Zod
3. **Mobile** — Flutter / React Native (Expo)
4. **Full-stack** — Frontend + Backend (monorepo)

Se sceglie **Mobile**, chiedi anche:
- **Flutter**
- **React Native (Expo)**

---

### Passo 3 — Scarica le risorse dal repo sorgente

Usa `gh api` per scaricare i file dal repo `acadevmy/ai-setup-meta`. Questo comando gestisce
l'autenticazione automaticamente e funziona con repo privati.

**Prerequisito**: verifica che `gh` sia autenticato con `gh auth status`. Se non lo e', informa
lo sviluppatore di eseguire `gh auth login` e fermati.

**Comando per scaricare un file**:
```bash
gh api repos/acadevmy/ai-setup-meta/contents/<PATH> -H "Accept: application/vnd.github.raw" > <OUTPUT>
```

**IMPORTANTE**: Scrivi i file scaricati **esattamente come ricevuti**, senza modifiche. Non riformattare, non aggiustare, non migliorare. Il contenuto deve essere verbatim.

#### 3.1 — CONSTITUTION.md

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/CONSTITUTION.md -H "Accept: application/vnd.github.raw" > /tmp/CONSTITUTION_SOURCE.md
```

Scarica il file in un percorso temporaneo. Lo adatterai nel passo successivo.

#### 3.2 — AGENT template

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/AGENT.template.md -H "Accept: application/vnd.github.raw" > /tmp/AGENT_TEMPLATE.md
```

Un unico template con placeholder, usato sia per GREENFIELD che per EXISTING.

#### 3.3 — settings.json

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/settings.json -H "Accept: application/vnd.github.raw" > /tmp/claude_settings.json
```

#### 3.4 — Skills

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/skills/start-task.md -H "Accept: application/vnd.github.raw" > /tmp/skill_start-task.md
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/skills/tdd.md -H "Accept: application/vnd.github.raw" > /tmp/skill_tdd.md
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/skills/bdd.md -H "Accept: application/vnd.github.raw" > /tmp/skill_bdd.md
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/skills/review.md -H "Accept: application/vnd.github.raw" > /tmp/skill_review.md
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/skills/sync-task.md -H "Accept: application/vnd.github.raw" > /tmp/skill_sync-task.md
```

#### 3.4b — Agent files

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/agents/clickup.md -H "Accept: application/vnd.github.raw" > /tmp/agent_clickup.md
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/.claude/agents/review.md -H "Accept: application/vnd.github.raw" > /tmp/agent_review.md
```

#### 3.5 — REGISTRY.md

```bash
gh api repos/acadevmy/ai-setup-meta/contents/templates/dev-setup-template/REGISTRY.md -H "Accept: application/vnd.github.raw" > /tmp/REGISTRY.md
```

#### 3.6 — Profilo stack (solo GREENFIELD)

Scarica il profilo selezionato:
- Web Frontend: `gh api repos/acadevmy/ai-setup-meta/contents/profiles/web-frontend.md -H "Accept: application/vnd.github.raw" > /tmp/profile.md`
- Backend Node: `gh api repos/acadevmy/ai-setup-meta/contents/profiles/backend-node.md -H "Accept: application/vnd.github.raw" > /tmp/profile.md`
- Mobile: `gh api repos/acadevmy/ai-setup-meta/contents/profiles/mobile.md -H "Accept: application/vnd.github.raw" > /tmp/profile.md`
- Full-stack: scarica sia `web-frontend.md` che `backend-node.md`

**Verifica che i download siano andati a buon fine**: controlla che i file scaricati non siano vuoti e non contengano errori JSON (es. `{"message":"Not Found"}`). Se un download fallisce, informa lo sviluppatore e fermati.

---

### Passo 4 — Adatta CONSTITUTION.md

Parti dal contenuto scaricato in `/tmp/CONSTITUTION_SOURCE.md`.

#### Per modalita' EXISTING:

1. Se il frontend **non** e' stato rilevato → rimuovi l'intera Sezione VI (da `## VI.` fino a prima di `## VII.` o `## VIII.`)
2. Se il mobile **non** e' stato rilevato → rimuovi l'intera Sezione VII (da `## VII.` fino a prima di `## VIII.`)
3. Se il linguaggio rilevato **non** include `node` → aggiungi questa nota subito dopo la riga `## I. Principi fondamentali`:

```
> **Nota**: Le regole specifiche a TypeScript/Zod si applicano ai progetti TypeScript.
> Per altri linguaggi, applicare il principio equivalente (validazione schema-first
> con lo strumento appropriato del proprio stack, strict typing nativo del linguaggio).
```

#### Per modalita' GREENFIELD:

Copia il file verbatim (nessuna modifica).

#### Per modalita' UPDATE:

Sovrascrivi il CONSTITUTION.md esistente con la versione scaricata, applicando le stesse regole di EXISTING basandoti sulla detection del Passo 2.

**Conflict detection**: Se `CONSTITUTION.md` esiste gia' nel progetto, chiedi allo sviluppatore prima di sovrascrivere.

Scrivi il risultato in `CONSTITUTION.md` nella root del progetto.

---

### Passo 5 — Genera AGENT.md

Leggi il contenuto scaricato da `/tmp/AGENT_TEMPLATE.md` e sostituisci i placeholder.
Il template e' unico per tutte le modalita': cambia solo la fonte dei valori.

#### Valori placeholder per modalita' EXISTING:

- `{{STACK_DESCRIPTION}}` → descrizione compatta dello stack rilevato. Formato: `Stack rilevato: linguaggi[, test: comando_test][, linter: comando_lint][, validazione: tool]`
  - Esempio: `Stack rilevato: **node**, test: npm test, linter: npm run lint, validazione: Zod`
  - Se test/linter/validazione sono `non rilevato`, omettili dalla stringa
  - Aggiungi nota: `> Questo stack e' stato rilevato automaticamente. Se non e' corretto, aggiorna questa sezione manualmente.`
- `{{TEST_COMMAND}}` → il comando test rilevato (es. `npm test`, `pytest`, `non rilevato`)
- `{{LINT_COMMAND}}` → il comando linter rilevato (es. `npm run lint`, `ruff check .`, `non rilevato`)

#### Valori placeholder per modalita' GREENFIELD:

In base allo stack scelto nel Passo 2b:

| Stack | `{{STACK_DESCRIPTION}}` | `{{TEST_COMMAND}}` | `{{LINT_COMMAND}}` |
|---|---|---|---|
| Web Frontend | `**Web Frontend**: Next.js 14+ / Angular 17+ / React 18+, ShadCN/UI, Tailwind CSS, Zod, Jest + Testing Library` | `npm test` | `npm run lint` |
| Backend Node | `**Backend Node**: Node.js 20+, NestJS 10+, Zod + class-validator, Jest + Supertest, Prisma` | `npm test` | `npm run lint` |
| Mobile (Flutter) | `**Mobile**: Flutter 3.24+ (BLoC/Riverpod)` | `flutter test` | `dart analyze` |
| Mobile (React Native) | `**Mobile**: React Native con Expo (Zustand/Jotai)` | `npm test` | `npm run lint` |
| Full-stack | `**Full-stack**: Web Frontend (Next.js/Angular/React) + Backend Node (NestJS)` | `npm test` | `npm run lint` |

#### Per modalita' UPDATE:

Rigenera come per EXISTING o GREENFIELD (a seconda dello stato del progetto).

**Conflict detection**: Se `AGENT.md` esiste gia', chiedi allo sviluppatore prima di sovrascrivere.

Scrivi il risultato in `AGENT.md` nella root del progetto.

---

### Passo 5b — Installa REGISTRY.md

**Conflict detection**: Se `REGISTRY.md` esiste gia' nel progetto, chiedi allo sviluppatore prima di sovrascrivere.

Se non esiste o lo sviluppatore conferma: copia il contenuto scaricato da `/tmp/REGISTRY.md` verbatim in `REGISTRY.md` nella root del progetto.

---

### Passo 6 — Installa configurazione Claude Code

#### 6.1 — Crea la struttura

```bash
mkdir -p .claude/skills .claude/agents
```

#### 6.2 — settings.json

Se `.claude/settings.json` **non** esiste: scrivi il contenuto scaricato da `/tmp/claude_settings.json` verbatim.
Se **esiste gia'**: informa lo sviluppatore e mantieni quello esistente.

#### 6.3 — Skills

Scarica sempre tutte le skills, ma installa quelle appropriate in base al progetto:

**Skills comuni** (sempre installate): start-task.md, review.md, sync-task.md

**Skills di metodologia** (in base al tipo di progetto):
- Se **frontend rilevato** (o stack Web Frontend / Mobile / Full-stack) → installa `bdd.md`
- Se **backend rilevato** (o stack Backend Node / Full-stack) → installa `tdd.md`
- Se **full-stack** o non determinabile → installa entrambe (`tdd.md` + `bdd.md`)

Per ogni skill da installare:
- Se il file **non** esiste in `.claude/skills/`: copialo dal file scaricato
- Se **esiste gia'**: informa lo sviluppatore e mantieni quello esistente

#### 6.3b — Agent files

Per ognuno dei 2 agent (clickup.md, review.md):
- Se il file **non** esiste in `.claude/agents/`: copialo dal file scaricato
- Se **esiste gia'**: informa lo sviluppatore e mantieni quello esistente

#### 6.4 — Mantieni setup.md

Il file `.claude/skills/setup.md` (questa skill) e' gia' presente. Non toccarlo.

---

### Passo 7 — Configura MCP servers

Verifica se `claude` CLI e' disponibile con `command -v claude`. Se non lo e', stampa i comandi da eseguire manualmente e vai al passo successivo.

#### 7.1 — ClickUp (user scope, sempre)

Controlla con `claude mcp list` se `clickup` e' gia' configurato.
Se non lo e':
```bash
claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
```

#### 7.2 — Context7 (project scope, sempre)

Controlla se `context7` e' gia' configurato.
Se non lo e':
```bash
claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest
```

#### 7.3 — Figma (solo se frontend rilevato o stack web-frontend/fullstack)

Se frontend rilevato, chiedi allo sviluppatore: "Vuoi configurare il MCP Figma? Serve il Personal Access Token di Figma."
Se risponde si', chiedi il token e poi:
```bash
claude mcp add figma -s project -e FIGMA_ACCESS_TOKEN="<token>" -- npx -y @figma/mcp-server
```

---

### Passo 8 — Setup file .env

1. Se `.env` esiste e contiene gia' `CLICKUP_SETUP_LIST_ID` → non fare nulla
2. Se `.env` esiste ma **non** contiene `CLICKUP_SETUP_LIST_ID` → appendi:
   ```

   # ClickUp — ID della lista per i task (aggiunto da setup agent)
   CLICKUP_SETUP_LIST_ID=
   ```
3. Se `.env` non esiste ma `.env.example` esiste e non contiene `CLICKUP_SETUP_LIST_ID` → appendi come sopra a `.env.example`
4. Se ne' `.env` ne' `.env.example` esistono → crea `.env.example` con:
   ```
   # ClickUp — ID della lista per i task
   CLICKUP_SETUP_LIST_ID=
   ```

---

### Passo 9 — Setup greenfield (solo modalita' GREENFIELD)

Questo passo si esegue **solo** per progetti greenfield. Per EXISTING e UPDATE, salta al Passo 10.

#### 9.1 — Prerequisiti

Verifica che siano installati: `node` (v20+), `npm`, `git`. Se mancano, informa lo sviluppatore e fermati.

#### 9.2 — Inizializza il progetto

Se `package.json` non esiste:
```bash
npm init -y
```

Se `.git` non esiste:
```bash
git init
```

#### 9.3 — Installa quality tools

```bash
npm install --save-dev husky lint-staged @commitlint/cli @commitlint/config-conventional prettier eslint @typescript-eslint/eslint-plugin @typescript-eslint/parser
```

Inizializza Husky:
```bash
npx husky init
```

Crea i git hook:

**`.husky/pre-commit`**:
```bash
npx lint-staged
```

**`.husky/commit-msg`**:
```bash
npx --no -- commitlint --edit "$1"
```

Rendi eseguibili:
```bash
chmod +x .husky/pre-commit .husky/commit-msg
```

#### 9.4 — Configurazioni di qualita'

Crea **`.commitlintrc.json`**:
```json
{
  "extends": ["@commitlint/config-conventional"]
}
```

Crea **`.prettierrc.json`**:
```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2
}
```

Crea **`.eslintrc.base.json`**:
```json
{
  "parser": "@typescript-eslint/parser",
  "plugins": ["@typescript-eslint"],
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended"
  ],
  "rules": {
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": ["error", { "argsIgnorePattern": "^_" }],
    "no-console": ["warn", { "allow": ["warn", "error"] }]
  }
}
```

#### 9.5 — Applica profilo stack

Leggi il file profilo scaricato (`/tmp/profile.md`) e applica le configurazioni che contiene:

1. **Dipendenze**: Estrai il blocco JSON delle dipendenze dal profilo e installale con `npm install`
2. **ESLint**: Se il profilo contiene una configurazione ESLint, crea `.eslintrc.json` con quel contenuto
3. **TypeScript**: Se il profilo contiene una configurazione TypeScript, crea `tsconfig.json`
4. **Jest**: Se il profilo contiene una configurazione Jest, crea `jest.config.ts`

Per lo stack **fullstack**:
- Crea la struttura `apps/web/` e `apps/api/`
- Applica il profilo web-frontend in `apps/web/`
- Applica il profilo backend-node in `apps/api/`

#### 9.6 — .gitignore

Se `.gitignore` non esiste, crealo con:
```
# Dependencies
node_modules/
.pnp
.pnp.js

# Build
dist/
build/
.next/
out/

# Environment
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Testing
coverage/

# Misc
*.log
npm-debug.log*
```

---

### Passo 10 — Pulizia

Rimuovi i file temporanei:
```bash
rm -f /tmp/CONSTITUTION_SOURCE.md /tmp/AGENT_TEMPLATE.md /tmp/claude_settings.json /tmp/skill_*.md /tmp/agent_*.md /tmp/REGISTRY.md /tmp/profile.md
```

---

### Passo 11 — Riepilogo

Mostra un riepilogo allo sviluppatore in questo formato:

**Per EXISTING:**
```
Setup completato!

File installati:
  - CONSTITUTION.md       — regole di governance
  - AGENT.md              — istruzioni per Claude Code
  - REGISTRY.md           — registro feature e servizi
  - .claude/              — settings + skills + agents

Stack rilevato:
  - Linguaggi:   <linguaggi>
  - Test runner:  <test_command>
  - Linter:       <lint_command>
  - Validazione:  <validation_tool>

NON modificato (tooling esistente rispettato):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Prossimi passi:
  1. Compila CLICKUP_SETUP_LIST_ID nel file .env
  2. Verifica MCP: claude mcp list
  3. Usa /project:start-task per iniziare un task ClickUp
```

**Per GREENFIELD:**
```
Setup completato!

Configurazione del progetto:
  - CONSTITUTION.md       — regole di governance
  - AGENT.md              — istruzioni per Claude Code
  - REGISTRY.md           — registro feature e servizi
  - .claude/              — settings + skills + agents
  - .husky/               — git hooks (lint + commit)
  - .eslintrc.base.json   — ESLint base
  - .eslintrc.json        — ESLint profilo <stack>
  - .prettierrc.json      — Prettier
  - .commitlintrc.json    — Conventional Commits
  - .env.example          — variabili d'ambiente

Prossimi passi:
  1. Copia .env.example in .env e compila le variabili
  2. Verifica MCP: claude mcp list
  3. Inizia a sviluppare con /project:tdd (backend) o /project:bdd (frontend)!
```

---

## Note importanti

- **Verbatim**: CONSTITUTION.md, settings.json, skills e agent files devono essere copiati esattamente come scaricati. Non generare il contenuto di questi file — scaricalo e copialo.
- **Conflict detection**: Chiedi sempre prima di sovrascrivere file esistenti.
- **Tooling esistente**: In modalita' EXISTING, non installare ne' modificare: git hooks, linter, formatter, CI/CD, .gitignore, dipendenze. Innesta solo il workflow AI.
- **Errori di download**: Se `gh api` restituisce un errore (es. 404, 401) o un file vuoto, informa lo sviluppatore e fermati. Non procedere con contenuto parziale.
- **Autenticazione**: Lo sviluppatore deve essere autenticato con `gh auth login`. Se `gh auth status` fallisce, fermati e chiedi di autenticarsi.
