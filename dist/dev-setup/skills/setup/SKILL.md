---
name: setup
description: Setup AI-Native per progetti di sviluppo software. Rileva modalita' (UPDATE/GREENFIELD/EXISTING), auto-detecta lo stack e configura il progetto con governance, MCP e workflow.
model: opus
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Dev Setup

Skill per innestare il workflow AI-Native in progetti di sviluppo software.
Le risorse sono bundled nel plugin — nessun download remoto necessario.

---

## Risorse locali

Tutti i file template sono disponibili in:
```
${CLAUDE_SKILL_DIR}/templates/
```

Contiene: AGENTS.template.md, CONSTITUTION.md, REGISTRY.md, .env.example, .gitignore, settings.json, profiles/

---

## Strategia di lettura

I file si dividono in due categorie:

- **Verbatim**: letti dal plugin e scritti direttamente nella destinazione finale (REGISTRY, settings, .gitignore, .env.example). Prima della scrittura si verifica il conflict detection.
- **Con trasformazione**: letti dal plugin, trasformati in memoria, poi scritti nella destinazione finale. Riguarda: CONSTITUTION (rimozione sezioni), AGENT template (sostituzione placeholder), profili (estrazione configurazioni).

**IMPORTANTE**: Skills e agents NON vengono installati nel progetto. Sono forniti dal plugin stesso e disponibili automaticamente.

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
1. `pubspec.yaml` presente → **freezed + json_serializable** (modelli immutabili e serializzazione schema-driven, no Zod)
2. `package.json` con: `zod` → **Zod**, `joi` → **Joi**, `yup` → **Yup**, `class-validator` → **class-validator**
3. `pyproject.toml` o `requirements.txt` con `pydantic` → **Pydantic**
4. Nessuno trovato → `non rilevato`

#### Frontend rilevato?
- `package.json` contiene `next`, `react`, `@angular/core`, `vue`, `nuxt`, o `svelte` → **si**
- Oppure: esistono file `.tsx`, `.jsx`, o `.vue` in `src/` → **si**
- Altrimenti → **no**

#### Mobile rilevato?
- `pubspec.yaml` presente → **si**
- `package.json` contiene `react-native` o `expo` → **si**
- Altrimenti → **no**

#### Framework mobile rilevato?
- `pubspec.yaml` presente → **flutter**
- altrimenti, `package.json` contiene `react-native` o `expo` → **react-native**
- altrimenti → `non rilevato`

#### Multi-progetto rilevato?

**Fase 1 — Monorepo tool**:
- `nx.json` presente → **si** (Nx)
- `turbo.json` presente → **si** (Turborepo)
- `pnpm-workspace.yaml` presente → **si** (pnpm workspace)
- `lerna.json` presente → **si** (Lerna)
- Root `package.json` contiene campo `workspaces` → **si** (Yarn/npm workspaces)

Se trovato, enumera i sub-project dalla configurazione del tool (es. `workspaces` in package.json, `projects` in nx.json, `packages` in pnpm-workspace.yaml).

**Fase 2 — Detection strutturale** (solo se Fase 1 non ha trovato nulla):
- Cerca nelle directory di primo livello file indicatori di progetto: `package.json`, `pubspec.yaml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`
- Se **2 o piu'** directory contengono almeno un indicatore → **si** (multi-progetto)
- Ignora directory comuni non-progetto: `node_modules`, `.git`, `.claude`, `dist`, `build`, `coverage`, `.github`, `.husky`

**Se multi-progetto rilevato** (da Fase 1 o Fase 2):
1. Per ogni sub-project trovato, esegui la auto-detection stack (Linguaggio, Test runner, Linter, Tool di validazione, Frontend rilevato?, Mobile rilevato?) nella directory del sub-project
2. Mostra il riepilogo allo sviluppatore e chiedi conferma prima di procedere

**Mostra il riepilogo della detection allo sviluppatore.**

Per progetto singolo:
```
Stack rilevato:
  Linguaggi:   node
  Test runner:  npm test
  Linter:       npm run lint
  Validazione:  Zod
  Frontend:     si
  Mobile:       no
```

Per multi-progetto:
```
Stack rilevato:
  Multi-progetto: si (Nx)
  Sub-project:
    apps/web/  — node, frontend: si, test: npm test, lint: npm run lint
    apps/api/  — node, frontend: no, test: npm test, lint: npm run lint

Confermi questi sub-project? (si/no)
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

### Passo 3 — Installa risorse dal plugin

Leggi i file template dal plugin e installali nel progetto.

#### 3.1 — File con trasformazione (letti in memoria)

Questi file richiedono adattamento. Leggili dal plugin:

**CONSTITUTION.md** (verra' adattato al Passo 4):
Leggi `${CLAUDE_SKILL_DIR}/templates/CONSTITUTION.md`

**AGENTS template** (verra' processato al Passo 5):

Per progetto singolo:
Leggi `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md`

Per multi-progetto (o stack fullstack):
Leggi `${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md`
Leggi `${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`

**Profilo stack** (solo GREENFIELD, verra' applicato al Passo 8.5):
Leggi il profilo selezionato da `${CLAUDE_SKILL_DIR}/templates/profiles/`:
- Web Frontend: `profiles/web-frontend.md`
- Backend Node: `profiles/backend-node.md`
- Mobile: `profiles/mobile.md`
- Full-stack: leggi sia `profiles/web-frontend.md` che `profiles/backend-node.md`

#### 3.2 — File verbatim (direttamente a destinazione)

Questi file vengono copiati esattamente. Prima di ogni scrittura, verifica se il file di destinazione esiste gia' (**conflict detection**): se esiste, informa lo sviluppatore e mantieni quello esistente saltando la scrittura.

**settings.json** (permessi progetto):
Se `.claude/settings.json` **non** esiste:
```bash
mkdir -p .claude
```
Leggi `${CLAUDE_SKILL_DIR}/templates/settings.json` e scrivilo in `.claude/settings.json`.
Se **esiste gia'**: informa lo sviluppatore e mantieni quello esistente.

**REGISTRY.md**:

Per progetto singolo:
Se `REGISTRY.md` **non** esiste (o lo sviluppatore conferma la sovrascrittura):
Leggi `${CLAUDE_SKILL_DIR}/templates/REGISTRY.md` e scrivilo in `REGISTRY.md`.

Per multi-progetto:
Genera un `REGISTRY.md` per ogni sub-project confermato. Non generare REGISTRY.md alla root.
Leggi `${CLAUDE_SKILL_DIR}/templates/REGISTRY.md` e scrivilo in `<sub-project-path>/REGISTRY.md`.

**.gitignore**:
Se `.gitignore` **non** esiste:
Leggi `${CLAUDE_SKILL_DIR}/templates/.gitignore` e scrivilo in `.gitignore`.

**.env.example**:
Se `.env.example` **non** esiste:
Leggi `${CLAUDE_SKILL_DIR}/templates/.env.example` e scrivilo in `.env.example`.

**IMPORTANTE**: Scrivi i file letti **esattamente come ricevuti**, senza modifiche. Non riformattare, non aggiustare, non migliorare. Il contenuto deve essere verbatim.

**Verifica**: controlla che i file scritti non siano vuoti. Se un file e' vuoto, informa lo sviluppatore e fermati.

---

### Passo 4 — Adatta CONSTITUTION.md

Parti dal contenuto letto da `${CLAUDE_SKILL_DIR}/templates/CONSTITUTION.md`.

#### Per modalita' EXISTING:

1. Se il frontend **non** e' stato rilevato → rimuovi l'intera Sezione VI (da `## VI.` fino a prima di `## VII.` o `## VIII.`)
   - **Multi-progetto**: mantieni Sezione VI se **qualsiasi** sub-project ha frontend rilevato
2. Se il mobile **non** e' stato rilevato → rimuovi l'intera Sezione VII (da `## VII.` fino a prima di `## VIII.`)
   - **Multi-progetto**: mantieni Sezione VII se **qualsiasi** sub-project ha mobile rilevato
3. Se il linguaggio rilevato **non** include `node` → aggiungi questa nota subito dopo la riga `## I. Principi fondamentali`:
   - **Multi-progetto**: aggiungi la nota solo se **nessun** sub-project usa `node`

```
> **Nota**: Le regole specifiche a TypeScript/Zod si applicano ai progetti TypeScript.
> Per altri linguaggi, applicare il principio equivalente (validazione schema-first
> con lo strumento appropriato del proprio stack, strict typing nativo del linguaggio).
```

#### Per modalita' GREENFIELD:

Copia il file verbatim (nessuna modifica).

#### Per modalita' UPDATE:

Sovrascrivi il CONSTITUTION.md esistente con la versione letta dal plugin, applicando le stesse regole di EXISTING basandoti sulla detection del Passo 2.

**Conflict detection**: Se `CONSTITUTION.md` esiste gia' nel progetto, chiedi allo sviluppatore prima di sovrascrivere.

Scrivi il risultato in `CONSTITUTION.md` nella root del progetto.

---

### Passo 5 — Genera AGENTS.md

#### 5A — Progetto singolo (non multi-progetto)

Leggi il contenuto da `${CLAUDE_SKILL_DIR}/templates/AGENTS.template.md` e sostituisci i placeholder.
Il template e' unico per tutte le modalita': cambia solo la fonte dei valori.

**Valori placeholder per modalita' EXISTING:**

- `{{STACK_DESCRIPTION}}` → descrizione compatta dello stack rilevato. Formato: `Stack rilevato: linguaggi[, test: comando_test][, linter: comando_lint][, validazione: tool]`
  - Esempio: `Stack rilevato: **node**, test: npm test, linter: npm run lint, validazione: Zod`
  - Se test/linter/validazione sono `non rilevato`, omettili dalla stringa
  - Aggiungi nota: `> Questo stack e' stato rilevato automaticamente. Se non e' corretto, aggiorna questa sezione manualmente.`
- `{{TEST_COMMAND}}` → il comando test rilevato (es. `npm test`, `pytest`, `non rilevato`)
- `{{LINT_COMMAND}}` → il comando linter rilevato (es. `npm run lint`, `ruff check .`, `non rilevato`)

**Valori placeholder per modalita' GREENFIELD:**

In base allo stack scelto nel Passo 2b:

| Stack | `{{STACK_DESCRIPTION}}` | `{{TEST_COMMAND}}` | `{{LINT_COMMAND}}` |
|---|---|---|---|
| Web Frontend | `**Web Frontend**: Next.js 14+ / Angular 17+ / React 18+, ShadCN/UI, Tailwind CSS, Zod, Jest + Testing Library` | `npm test` | `npm run lint` |
| Backend Node | `**Backend Node**: Node.js 20+, NestJS 10+, Zod + class-validator, Jest + Supertest, Prisma` | `npm test` | `npm run lint` |
| Mobile (Flutter) | `**Mobile**: Flutter 3.24+ (BLoC/Riverpod)` | `flutter test` | `dart analyze` |
| Mobile (React Native) | `**Mobile**: React Native con Expo (Zustand/Jotai)` | `npm test` | `npm run lint` |

**Per modalita' UPDATE:** Rigenera come per EXISTING o GREENFIELD (a seconda dello stato del progetto).

**Conflict detection**: Se `AGENTS.md` esiste gia', chiedi allo sviluppatore prima di sovrascrivere.

Scrivi il risultato in `AGENTS.md` nella root del progetto.

#### 5B — Multi-progetto (o stack fullstack)

Genera **due livelli** di AGENTS.md: uno alla root e uno per ogni sub-project.

**Root AGENTS.md** — usa `${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md`:
- `{{WORKSPACE_STRUCTURE}}` → genera una tabella con i sub-project confermati:
  ```
  | Progetto | Path | Stack | Istruzioni |
  |---|---|---|---|
  | Web Frontend | `apps/web/` | Next.js 14+, React 18+ | [`apps/web/AGENTS.md`](apps/web/AGENTS.md) |
  | Backend API | `apps/api/` | Node.js 20+, NestJS 10+ | [`apps/api/AGENTS.md`](apps/api/AGENTS.md) |
  ```
- Scrivi il risultato in `AGENTS.md` nella root

**AGENTS.md per sub-project** — usa `${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`:

Per ogni sub-project confermato, sostituisci i placeholder:
- `{{PROJECT_NAME}}` → nome descrittivo del sub-project (es. "Web Frontend", "Backend API")
- `{{STACK_DESCRIPTION}}` → stack rilevato del sub-project (stessi criteri del punto 5A)
- `{{TEST_COMMAND}}` → test runner rilevato nel sub-project
- `{{LINT_COMMAND}}` → linter rilevato nel sub-project
- `{{ROOT_AGENTS_REL_PATH}}` → path relativo alla root (es. `../../AGENTS.md`)

Scrivi il risultato in `<sub-project-path>/AGENTS.md`.

---

### Passo 5b — Genera CLAUDE.md

Claude Code legge `CLAUDE.md`, non `AGENTS.md`. Per garantire compatibilita' con Claude Code
e al tempo stesso mantenere `AGENTS.md` come standard cross-tool (Codex, Copilot, Cursor, ecc.),
genera un `CLAUDE.md` che referenzia `AGENTS.md`:

```markdown
@AGENTS.md
```

Il file `CLAUDE.md` deve contenere **solo** la riga sopra indicata. Non aggiungere
altro contenuto: tutte le istruzioni devono restare in `AGENTS.md` come single source of truth.

**Conflict detection**: Se `CLAUDE.md` esiste gia', chiedi allo sviluppatore prima di sovrascrivere.

Scrivi il risultato in `CLAUDE.md` nella root del progetto.

**Multi-progetto**: genera `CLAUDE.md` anche in ogni sub-project confermato, con lo stesso contenuto (`@AGENTS.md`). Il CLAUDE.md del sub-project puntera' all'AGENTS.md locale del sub-project.

---

### Passo 6 — Configura MCP servers

Verifica se `claude` CLI e' disponibile con `command -v claude`. Se non lo e', stampa i comandi da eseguire manualmente e vai al passo successivo.

#### 6.1 — ClickUp (user scope, sempre)

Controlla con `claude mcp list` se `clickup` e' gia' configurato.
Se non lo e':
```bash
claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
```

#### 6.2 — Context7 (project scope, sempre)

Il plugin include gia' context7 nella sua .mcp.json. Verifica che non ci sia un conflitto con un context7 gia' configurato a livello progetto.
Se `.mcp.json` del progetto esiste gia' e contiene `context7`, non fare nulla.
Se non esiste o non contiene context7:
```bash
claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest
```

#### 6.3 — Figma (solo se frontend o mobile rilevato, o stack web-frontend/mobile/fullstack)

Se frontend o mobile rilevato, chiedi allo sviluppatore: "Vuoi configurare il MCP Figma? L'autenticazione avviene via OAuth nel browser."
Se risponde si':
```bash
claude mcp add figma -s project --type url https://mcp.figma.com/mcp
```
Al primo utilizzo, Figma chiedera' l'autorizzazione via browser (come ClickUp).

---

### Passo 7 — Setup file .env

1. Se `.env` esiste e contiene gia' `CLICKUP_SETUP_LIST_ID` → non fare nulla
2. Se `.env` esiste ma **non** contiene `CLICKUP_SETUP_LIST_ID` → appendi:
   ```

   # ClickUp — ID della lista per i task (aggiunto da setup)
   CLICKUP_SETUP_LIST_ID=
   ```
3. Se `.env` non esiste ma `.env.example` esiste e non contiene `CLICKUP_SETUP_LIST_ID` → appendi come sopra a `.env.example`
4. Se ne' `.env` ne' `.env.example` esistono → crea `.env.example` con:
   ```
   # ClickUp — ID della lista per i task
   CLICKUP_SETUP_LIST_ID=
   ```

---

### Passo 8 — Setup greenfield (solo modalita' GREENFIELD)

Questo passo si esegue **solo** per progetti greenfield. Per EXISTING e UPDATE, salta al Passo 9.

#### 8.1 — Prerequisiti

Verifica che siano installati: `node` (v20+), `npm`, `git`. Se mancano, informa lo sviluppatore e fermati.

#### 8.2 — Inizializza il progetto

Se `package.json` non esiste:
```bash
npm init -y
```

Se `.git` non esiste:
```bash
git init
```

#### 8.3 — Installa quality tools

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

#### 8.4 — Configurazioni di qualita'

Crea **`.commitlintrc.json`**:
```json
{
  "extends": ["@commitlint/config-conventional"],
  "rules": {
    "type-enum": [
      2,
      "always",
      ["feat", "fix", "docs", "style", "refactor", "test", "chore", "perf", "ci"]
    ],
    "subject-case": [2, "never", ["start-case", "pascal-case", "upper-case"]],
    "subject-max-length": [2, "always", 100],
    "body-max-line-length": [1, "always", 200]
  }
}
```

Crea **`.prettierrc.json`**:
```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

Crea **`.releaserc.json`** (semantic-release):
```json
{
  "branches": ["main"],
  "plugins": [
    [
      "@semantic-release/commit-analyzer",
      {
        "preset": "conventionalcommits",
        "releaseRules": [
          { "type": "feat", "release": "minor" },
          { "type": "fix", "release": "patch" },
          { "type": "perf", "release": "patch" },
          { "type": "refactor", "release": "patch" },
          { "type": "chore", "scope": "deps", "release": "patch" },
          { "breaking": true, "release": "major" }
        ]
      }
    ],
    [
      "@semantic-release/release-notes-generator",
      {
        "preset": "conventionalcommits",
        "presetConfig": {
          "types": [
            { "type": "feat", "section": "Nuove funzionalita'" },
            { "type": "fix", "section": "Bug fix" },
            { "type": "perf", "section": "Performance" },
            { "type": "refactor", "section": "Refactoring" },
            { "type": "chore", "section": "Manutenzione" },
            { "type": "docs", "section": "Documentazione" },
            { "type": "ci", "section": "CI/CD" }
          ]
        }
      }
    ],
    ["@semantic-release/changelog", { "changelogFile": "CHANGELOG.md" }],
    ["@semantic-release/npm", { "npmPublish": false }],
    [
      "@semantic-release/git",
      {
        "assets": ["CHANGELOG.md", "package.json", "package-lock.json"],
        "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }
    ],
    "@semantic-release/github"
  ]
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

#### 8.5 — Applica profilo stack

Leggi il file profilo da `${CLAUDE_SKILL_DIR}/templates/profiles/` (gia' letto al Passo 3.1) e applica le configurazioni che contiene:

Se stack mobile = **Flutter** (rilevato da `pubspec.yaml` o selezionato in GREENFIELD), applica percorso ad-hoc Flutter:

1. **Dipendenze Flutter**: aggiorna `pubspec.yaml` con i pacchetti del profilo (`freezed_annotation`, `json_annotation`, `riverpod`/`flutter_bloc`, `dio`, ecc.)
2. **Dev dependencies Flutter**: includi `build_runner`, `freezed`, `json_serializable`, `flutter_lints`, `riverpod_generator` (se Riverpod codegen)
3. **Linting Flutter**: crea/aggiorna `analysis_options.yaml` includendo `package:flutter_lints/flutter.yaml`
4. **Code generation**: esegui `dart run build_runner build --delete-conflicting-outputs`
5. **Quality gate**: esegui `dart format .`, `dart analyze`, `flutter test`

Se stack mobile = **React Native (Expo)**, applica percorso Node:

1. **Dipendenze**: Estrai il blocco JSON delle dipendenze dal profilo e installale con `npm install`
2. **ESLint**: Se il profilo contiene una configurazione ESLint, crea `.eslintrc.json` con quel contenuto
3. **TypeScript**: Se il profilo contiene una configurazione TypeScript, crea `tsconfig.json`
4. **Jest**: Se il profilo contiene una configurazione Jest, crea `jest.config.ts`

Per lo stack **fullstack** (multi-progetto):
- Crea la struttura `apps/web/` e `apps/api/`
- Applica il profilo web-frontend in `apps/web/`
- Applica il profilo backend-node in `apps/api/`
- Genera `AGENTS.md`, `CLAUDE.md` e `REGISTRY.md` per ogni sub-project (come descritto nei Passi 5B e 5b)
- Alla root usa il workspace template (come descritto nel Passo 5B)

#### 8.6 — CI/CD workflow

Crea **`.github/workflows/release.yml`** (GitHub Actions + semantic-release):
```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release:
    name: Semantic Release
    runs-on: ubuntu-latest
    if: "!contains(github.event.head_commit.message, '[skip ci]')"
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          persist-credentials: false

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm

      - run: npm ci
      - run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> **Nota**: Se lo sviluppatore usa GitLab CI o altro, adatta il workflow al provider CI/CD del progetto mantenendo gli stessi step (checkout, setup, install, semantic-release).

#### 8.7 — .gitignore

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

### Passo 9 — Riepilogo

Mostra un riepilogo allo sviluppatore in questo formato:

**Per EXISTING:**
```
Setup completato!

File installati:
  - CLAUDE.md             — entry point per Claude Code (importa AGENTS.md)
  - AGENTS.md             — istruzioni per agenti AI (standard cross-tool)
  - CONSTITUTION.md       — regole di governance
  - REGISTRY.md           — registro feature e servizi
  - .claude/settings.json — permessi progetto

Skills disponibili (fornite dal plugin):
  - /dev-setup:start-task  — flow rapido (branch → TDD/BDD → review → PR)
  - /dev-setup:sdd         — flow spec-driven (spec → approvazione → sviluppo)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — Code review con CONSTITUTION

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
  3. Usa /dev-setup:start-task o /dev-setup:sdd per iniziare un task ClickUp
```

**Per GREENFIELD:**
```
Setup completato!

Configurazione del progetto:
  - CLAUDE.md             — entry point per Claude Code (importa AGENTS.md)
  - AGENTS.md             — istruzioni per agenti AI (standard cross-tool)
  - CONSTITUTION.md       — regole di governance
  - REGISTRY.md           — registro feature e servizi
  - .claude/settings.json — permessi progetto
  - .husky/               — git hooks (lint + commit)
  - .eslintrc.base.json   — ESLint base
  - .eslintrc.json        — ESLint profilo <stack>
  - .prettierrc.json      — Prettier
  - .commitlintrc.json    — Conventional Commits
  - .releaserc.json       — semantic-release
  - .github/workflows/    — CI/CD (semantic-release)
  - .env.example          — variabili d'ambiente

Skills disponibili (fornite dal plugin):
  - /dev-setup:start-task  — flow rapido (branch → TDD/BDD → review → PR)
  - /dev-setup:sdd         — flow spec-driven (spec → approvazione → sviluppo)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — Code review con CONSTITUTION

Prossimi passi:
  1. Copia .env.example in .env e compila le variabili
  2. Verifica MCP: claude mcp list
  3. Usa /dev-setup:start-task (rapido) o /dev-setup:sdd (spec-driven) per iniziare!
```

**Per MULTI-PROGETTO (EXISTING):**
```
Setup completato! (Multi-progetto rilevato: <tool>)

File alla root:
  - CLAUDE.md             — entry point per Claude Code
  - AGENTS.md             — regole generali + mappa workspace
  - CONSTITUTION.md       — regole di governance
  - .claude/settings.json — permessi progetto

Sub-project configurati:
  <sub-project-path>/:
    - AGENTS.md           — stack: <stack>
    - CLAUDE.md           — entry point locale
    - REGISTRY.md         — registro feature

Skills disponibili (fornite dal plugin):
  - /dev-setup:start-task  — flow rapido (branch → TDD/BDD → review → PR)
  - /dev-setup:sdd         — flow spec-driven (spec → approvazione → sviluppo)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — Code review con CONSTITUTION

NON modificato (tooling esistente rispettato):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Prossimi passi:
  1. Compila CLICKUP_SETUP_LIST_ID nel file .env
  2. Verifica MCP: claude mcp list
  3. Usa /dev-setup:start-task o /dev-setup:sdd per iniziare un task ClickUp
```

---

## Note importanti

- **Verbatim**: settings.json e REGISTRY.md devono essere scritti esattamente come letti dal plugin. Non generare il contenuto di questi file — leggilo e copialo.
- **Conflict detection**: Chiedi sempre prima di sovrascrivere file esistenti.
- **Tooling esistente**: In modalita' EXISTING, non installare ne' modificare: git hooks, linter, formatter, CI/CD, .gitignore, dipendenze. Innesta solo il workflow AI.
- **Skills e agents**: NON installare skills e agents nel progetto. Sono forniti dal plugin e disponibili automaticamente come /dev-setup:<skill-name>.
- **gh CLI**: Necessaria solo per la configurazione MCP (Passo 6) e per operazioni greenfield. Se non presente, il setup puo' comunque completarsi — stampa i comandi MCP da eseguire manualmente.
