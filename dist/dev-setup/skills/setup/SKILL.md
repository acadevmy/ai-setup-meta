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
- Qualsiasi file `*.tf` nella root o in una subdirectory diretta (profondita' ≤ 2) → **terraform**
- Nessuno dei precedenti → **unknown**

Possono coesistere piu' linguaggi (es. node + python, oppure node + terraform per un monorepo full-stack).

#### Test runner
Cerca nell'ordine:
1. `package.json` con script `test` → se contiene `vitest` usa `npx vitest`, altrimenti `npm test`
2. `pytest.ini` o `pyproject.toml` con `[tool.pytest]` → `pytest`
3. `go.mod` → `go test ./...`
4. `pubspec.yaml` → `flutter test`
5. `Cargo.toml` → `cargo test`
6. Linguaggi rilevati includono `terraform` → `terraform validate` (nota: Terraform non ha un test runner classico; `terraform validate` e' il piu' vicino built-in. Il profilo `terraform.md` documenta `terraform test` 1.6+ e Terratest come opzioni)
7. Nessuno trovato → `non rilevato`

#### Linter
Cerca nell'ordine:
1. File `.eslintrc*` o `eslint.config*` o `eslint` in `package.json` → se c'e' script `lint` usa `npm run lint`, altrimenti `npx eslint .`
2. `pyproject.toml` con `[tool.ruff]` → `ruff check .`
3. `.flake8` o `setup.cfg` con `[flake8]` → `flake8`
4. `.golangci.yml` → `golangci-lint run`
5. `analysis_options.yaml` → `dart analyze`
6. `Cargo.toml` → `cargo clippy`
7. Linguaggi rilevati includono `terraform` → `terraform fmt -check -recursive`
8. Nessuno trovato → `non rilevato`

#### Tool di validazione
1. `pubspec.yaml` presente → **freezed + json_serializable** (modelli immutabili e serializzazione schema-driven, no Zod)
2. `package.json` con: `zod` → **Zod**, `joi` → **Joi**, `yup` → **Yup**, `class-validator` → **class-validator**
3. `pyproject.toml` o `requirements.txt` con `pydantic` → **Pydantic**
4. Nessuno trovato → `non rilevato`

#### Frontend rilevato?
- `package.json` contiene `next`, `react`, `@angular/core`, `vue`, `nuxt`, o `svelte` → **si**
- Oppure: esistono file `.tsx`, `.jsx`, o `.vue` in `src/` → **si**
- Altrimenti → **no**

#### Framework frontend rilevato?
Solo se "Frontend rilevato?" → **si**. Identifica il framework principale e la versione (usato dal Passo 5 per pattern framework-specifici come il blocco AGENTS.md di Next.js).

- `package.json` contiene `next` → **nextjs**
- `package.json` contiene `nuxt` → **nuxt**
- `package.json` contiene `@angular/core` → **angular**
- `package.json` contiene `vue` (senza `nuxt`) → **vue**
- `package.json` contiene `svelte` → **svelte**
- `package.json` contiene `react` (senza `next`/`@angular/core`/`vue`/`nuxt`/`svelte`) → **react**
- Altrimenti → `non rilevato`

Quando il framework e' rilevato, leggi anche la versione da `dependencies.<pkg>` o `devDependencies.<pkg>` e parsa il major.minor (es. `"next": "^16.0.7"` → `16.0`; `"next": "~17.2.0"` → `17.2`). Salva come `{FRAMEWORK_FRONTEND}` e `{FRAMEWORK_FRONTEND_VERSION}`.

#### Verifica convenzioni AI-tooling correnti (per ogni framework rilevato)

Lo stato dell'arte delle convenzioni `AGENTS.md` (e equivalenti) cambia velocemente — i profile hard-coded in `profiles/<framework>.md` riflettono lo stato al rilascio del plugin, ma framework nuovi e versioni recenti introducono pattern aggiuntivi che il plugin non conosce ancora. Per ogni framework rilevato (`{FRAMEWORK_FRONTEND}`, framework backend se applicabile, framework infrastruttura come Terraform, ecc.) interroga la documentazione corrente per scoprire convenzioni AI-tooling.

**Strategia di lookup** (in ordine, prima fonte che produce risultato vince):

1. **`ctx7` CLI** in PATH, oppure via `npx ctx7@latest` se non installata:
   - `ctx7 library <framework>` per risolvere l'ID (es. `/vercel/next.js`)
   - `ctx7 docs <id> "AGENTS.md convention bundled docs agent rules"` per la query
2. **Context7 MCP**, solo se il progetto lo ha registrato (non e' nella configurazione di default, vedi Passo 6.2): `mcp__context7__resolve-library-id` + `mcp__context7__query-docs` con la stessa query
3. **WebSearch** se ctx7/Context7 non sono disponibili: query `"AGENTS.md convention <framework> <major>.<minor>"` (es. `"AGENTS.md convention next.js 16.2"`), preferendo risultati dal dominio ufficiale del framework
4. **Skip** se nessuna fonte e' raggiungibile (ambiente offline) — procedi con i soli profile hard-coded e segnala la skip nel riepilogo del Passo 9

**Cosa cercare**, per ciascun framework:

- Esiste una convenzione `AGENTS.md` ufficialmente supportata dal framework (es. il blocco `BEGIN:nextjs-agent-rules` di Next.js)?
- Quali marker / sezioni vengono gestite automaticamente dal framework (es. da un comando `<framework> upgrade`)?
- Path dei docs bundled (se applicabile, es. `node_modules/<framework>/dist/docs/`)
- Codemod o tooling correlato per progetti esistenti (es. `npx @next/codemod@latest agents-md`)
- Versione minima del framework che supporta la convenzione

**Precedenza delle fonti**:

- Profile hard-coded (`profiles/<framework>.md`) → fonte primaria per framework documentati al rilascio plugin (deterministico, predicibile)
- Verifica runtime → fonte aggiuntiva per framework non ancora documentati nel plugin **o** per versioni piu' recenti che hanno introdotto nuove convenzioni

Salva eventuali convenzioni scoperte come `{FRAMEWORK_AGENTS_CONVENTION}` (oggetto strutturato con: nome marker, contenuto del blocco, fonte, link doc) — il Passo 5 le applica come framework-specific block injection con la stessa strategia documentata per Next.js.

**Output al developer**: una riga nel riepilogo del Passo 9 per ogni framework verificato, formato:
```
- <framework> <version>: convenzione <name> trovata via <source> → <azione applicata>
- <framework> <version>: nessuna convenzione AI-tooling documentata → nessuna azione
- <framework> <version>: verifica saltata (offline) → applicato solo profile hard-coded
```

#### Mobile rilevato?
- `pubspec.yaml` presente → **si**
- `package.json` contiene `react-native` o `expo` → **si**
- Altrimenti → **no**

#### Framework mobile rilevato?
- `pubspec.yaml` presente → **flutter**
- altrimenti, `package.json` contiene `react-native` o `expo` → **react-native**
- altrimenti → `non rilevato`

#### Infrastructure rilevato?
- Linguaggi rilevati includono `terraform` → **si**
- Altrimenti → **no**

Questa flag deriva dal rilevamento linguaggio e serve a gatettare la Sezione X della CONSTITUTION (Passo 4, regola 5).

#### Multi-progetto rilevato?

**Fase 1 — Monorepo tool**:
- `nx.json` presente → **si** (Nx)
- `turbo.json` presente → **si** (Turborepo)
- `pnpm-workspace.yaml` presente → **si** (pnpm workspace)
- `lerna.json` presente → **si** (Lerna)
- Root `package.json` contiene campo `workspaces` → **si** (Yarn/npm workspaces)

**Enumerazione sub-project** (in ordine di priorita', il primo che produce risultati e' quello buono):
1. `pnpm-workspace.yaml` → leggi `packages:` (lista di glob)
2. Root `package.json` → leggi campo `workspaces` (array di glob)
3. `lerna.json` → leggi `packages` (lista di glob)
4. `nx.json` → leggi `projects` SOLO se il campo esiste (legacy, Nx ≤ 17). Da Nx 18+ il campo non e' piu' presente: i progetti sono dedotti da `package.json`/`project.json` sotto i path workspace ("inferred projects" model). In questo caso usa una delle fonti precedenti.
5. `turbo.json` → i progetti sono dedotti dai workspace di pnpm/yarn/npm; Turborepo non mantiene una lista propria.

Espandi i glob in directory effettive contenenti `package.json`. Cross-check opzionale: se il CLI Nx e' disponibile in `node_modules/.bin` o in PATH, lancia `pnpm nx show projects` (o `npx nx show projects`) e confronta l'elenco dedotto con l'output del CLI.

Per ogni sub-project, leggi il suo `package.json`:
- `name` → identificatore del progetto (usato sia per la display path che per il wrapping dei comandi, vedi sotto)
- `scripts` → comandi disponibili (`dev`, `build`, `test`, `lint`, ...)
- `dependencies` / `devDependencies` → driver per la rilevazione stack
- Eventuale campo `nx` (per-target inputs/outputs/cache) → informativo, non cambia l'invocazione

**Fase 2 — Detection strutturale** (solo se Fase 1 non ha trovato nulla):
- Cerca nelle directory di primo livello file indicatori di progetto: `package.json`, `pubspec.yaml`, `go.mod`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`
- Se **2 o piu'** directory contengono almeno un indicatore → **si** (multi-progetto)
- Ignora directory comuni non-progetto: `node_modules`, `.git`, `.claude`, `dist`, `build`, `coverage`, `.github`, `.husky`

**Se multi-progetto rilevato** (da Fase 1 o Fase 2):
1. Per ogni sub-project trovato, esegui la auto-detection stack (Linguaggio, Test runner, Linter, Tool di validazione, Frontend rilevato?, Mobile rilevato?) nella directory del sub-project, leggendo il suo `package.json` (se presente) per `scripts`, `dependencies`, `devDependencies`.
2. **Wrapping dell'invocazione**: in modalita' multi-progetto i comandi devono essere lanciabili dalla root del workspace, non solo dalla cartella del sub-project. Quando popoli `{{TEST_COMMAND}}` / `{{LINT_COMMAND}}` (e qualunque altro comando) nel template per-progetto, usa la forma wrappata corrispondente al monorepo tool rilevato:
   - **Nx** → `nx run <name>:<target>` (preferito quando il target e' definito in `nx.json` `targetDefaults` o in `package.json` `nx.targets`); fallback `pnpm --filter <name> <script>` (o l'equivalente del package manager)
   - **pnpm workspace** (senza Nx) → `pnpm --filter <name> <script>`
   - **Yarn workspace** → `yarn workspace <name> <script>`
   - **npm workspace** → `npm run <script> --workspace=<name>`
   - **Lerna** → `lerna run <script> --scope=<name>`
   - Sub-project non-Node (es. Terraform sotto `iac/`) → comando raw, eseguito dalla directory del sub-project (nessun wrapping).
3. Mostra il riepilogo allo sviluppatore e chiedi conferma prima di procedere.

**Mostra il riepilogo della detection allo sviluppatore.**

Per progetto singolo:
```
Stack rilevato:
  Linguaggi:     node
  Test runner:   npm test
  Linter:        npm run lint
  Validazione:   Zod
  Frontend:      si
  Mobile:        no
  Infrastructure: no
```

Per multi-progetto (i comandi sono gia' wrappati per essere eseguiti dalla root del workspace):
```
Stack rilevato:
  Multi-progetto: si (Nx + pnpm workspace)
  Sub-project:
    applications/web/   — node, frontend: si, test: pnpm --filter web test, lint: pnpm --filter web lint
    applications/api/   — node, frontend: no, test: pnpm --filter api test, lint: pnpm --filter api lint
    iac/                — terraform, infrastructure: si, test: terraform validate, lint: terraform fmt -check -recursive

Confermi questi sub-project? (si/no)
```

---

### Passo 2b — Selezione stack (solo modalita' GREENFIELD)

Se la modalita' e' GREENFIELD, chiedi allo sviluppatore di scegliere lo stack:

1. **Web Frontend** — Next.js / Angular / React + ShadCN/UI + Tailwind
2. **Backend Node** — Node.js / NestJS + Prisma + Zod
3. **Mobile** — Flutter / React Native (Expo)
4. **Full-stack** — Frontend + Backend (monorepo)
5. **Infrastructure / Terraform** — HCL, remote state (S3 default), AWS/Azure/GCP

Se sceglie **Mobile**, chiedi anche:
- **Flutter**
- **React Native (Expo)**

Se sceglie **Infrastructure / Terraform**: imposta `languages=[terraform]`, `infrastructure=yes`. **Nota importante**: il Passo 8 (setup greenfield) **non** applica boilerplate Terraform-specifico in questa versione (nessun `.gitignore` Terraform auto-generato, nessun workflow CI Terraform auto-emesso, nessun `versions.tf` scaffold). Il profilo `terraform.md` contiene le ricette CI e il backend S3 come testo di riferimento da copiare. Comunica questa limitazione allo sviluppatore nel riepilogo del Passo 9.

---

### Passo 2c — Rilevamento VCS

Determina il provider Git del progetto. Il risultato guida i Passi 5, 8.4, 8.6 e 9.

1. Prova a leggere l'URL del remote:
   ```bash
   git -C <project-root> remote get-url origin 2>/dev/null
   ```
   Se `origin` non esiste, usa il primo remote disponibile (`git remote | head -1`).

2. Se non esiste `.git` o non c'e' nessun remote configurato:
   - `vcs = none`
   - Comunica allo sviluppatore: "Nessun remote Git rilevato. I file VCS-specifici (CI, `.releaserc.json`) non verranno installati."
   - Salta al Passo 3.

3. Altrimenti, normalizza l'URL in minuscolo e classifica:
   - Contiene `github.com` → `vcs = github`
   - Contiene `gitlab` (qualsiasi host, es. `gitlab.com`, `gitlab.company.internal`) → `vcs = gitlab`
   - Nessuno dei due → vai al punto 4 (probe CLI).

4. **Probe CLI** per host self-hosted ambigui (es. `git@git.company.com:...`):
   - Estrai l'hostname dall'URL (gestisci sia HTTPS sia SSH).
   - Esegui `gh auth status --hostname <host> 2>/dev/null` e `glab auth status --hostname <host> 2>/dev/null`.
   - Se esattamente uno dei due riconosce l'host → `vcs = <quello>`.
   - Se nessuno o entrambi → chiedi allo sviluppatore con `AskUserQuestion`:
     ```
     question: "Quale provider Git usa questo progetto?"
     options: [ {label: "GitHub"}, {label: "GitLab"}, {label: "Altro / nessuno"} ]
     ```
   - Se sceglie "Altro / nessuno" → `vcs = other` (stesso trattamento di `none` per i file VCS-specifici).

5. Comunica allo sviluppatore il VCS rilevato prima di procedere. Salva il valore — verra' referenziato come `{VCS}` nei passi successivi.

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

#### 3.3 — Adatta allowlist al package manager rilevato

Il template di `.claude/settings.json` elenca tutti e tre i Node package manager (`Bash(npm *)`, `Bash(pnpm *)`, `Bash(yarn *)`) nell'array `allow`, perche' al rilascio del plugin non sappiamo quale userai. Se il progetto ha un lock file univoco, restringi l'allowlist al PM in uso — un agente non deve invocare `yarn install` in un progetto pnpm e bypassare le convenzioni di workspace/hoisting.

**Skip se**:
- `.claude/settings.json` esisteva gia' al momento del 3.2 e non e' stato sovrascritto (la conflict detection l'ha lasciato intatto — non spettano a te modifiche post-hoc).
- Linguaggi rilevati al Passo 2 NON includono `node` (es. progetto Python/Go/Terraform puro): le 3 entry restano per supportare eventuale `npx <tool>` puntuale.

**Detection del package manager**:

| Lock file rilevato in root | Package manager |
|---|---|
| `pnpm-lock.yaml` | **pnpm** |
| `yarn.lock` | **yarn** |
| `package-lock.json` | **npm** |
| Piu' di un lock file | **ambiguo** — non toccare l'allowlist, segnala l'anomalia nel riepilogo del Passo 9 |
| Nessun lock file (`package.json` esiste ma il progetto non e' ancora stato `install`-ato) | **nessuno** — lascia tutte e tre le entry, segnala nel riepilogo del Passo 9 |

**Modifiche all'allowlist** (solo se PM rilevato e univoco):

- `pnpm` → mantieni `Bash(pnpm *)`, aggiungi `Bash(pnpx *)` se non gia' presente, rimuovi `Bash(npm *)` e `Bash(yarn *)`. **Mantieni `Bash(npx *)`** — e' universale, usato dalla CLI di `ctx7` (`npx ctx7@latest`), dai codemod ufficiali (`npx @next/codemod@latest`), e da molti README di tool one-shot. Rimuovere `npx` rompe questi flussi senza guadagno reale.
- `yarn` → mantieni `Bash(yarn *)` e `Bash(npx *)`, rimuovi `Bash(npm *)` e `Bash(pnpm *)`.
- `npm` → mantieni `Bash(npm *)` e `Bash(npx *)`, rimuovi `Bash(yarn *)` e `Bash(pnpm *)`.

**Deny array intatto**: NON toccare l'array `deny`. `Bash(npm publish*)`, `Bash(pnpm publish*)`, `Bash(yarn publish*)` rimangono tutti — una `publish` accidentale via il PM "sbagliato" e' comunque un evento da bloccare.

**Implementazione (jq, idempotente, preserva il resto del file)**:

```bash
# Rilevato PM == "pnpm"
jq '.permissions.allow |= ((. - ["Bash(npm *)", "Bash(yarn *)"]) | if any(. == "Bash(pnpx *)") then . else . + ["Bash(pnpx *)"] end)' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Rilevato PM == "yarn"
jq '.permissions.allow -= ["Bash(npm *)", "Bash(pnpm *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json

# Rilevato PM == "npm"
jq '.permissions.allow -= ["Bash(yarn *)", "Bash(pnpm *)"]' \
  .claude/settings.json > .claude/settings.json.tmp \
  && mv .claude/settings.json.tmp .claude/settings.json
```

`jq` e' gia' una dipendenza dichiarata del plugin (vedi `scripts/build-plugin.sh`), quindi e' ragionevole assumerlo presente.

**Riporta nel riepilogo del Passo 9** (una sola riga):
- PM univoco rilevato: `allowlist tightened to <pm>-only commands per detected lock file (<lockfile>)`
- Lock file multipli: `multiple lock files detected (<list>) — allowlist left as default; consider committing to a single PM`
- Nessun lock file ma `node` rilevato: `no lock file present — allowlist left as default; the team should run \`<pm> install\` and re-run setup to tighten`

---

### Passo 4 — Adatta CONSTITUTION.md

Parti dal contenuto letto da `${CLAUDE_SKILL_DIR}/templates/CONSTITUTION.md`.

#### Per modalita' EXISTING:

> Ogni regola cita la sezione da rimuovere per numero: la sola fonte del numero sono gli
> heading `## <N>.` di `CONSTITUTION.md`, e il check 9 di `/project:validate` verifica che
> la coppia regola↔heading corrisponda.

1. Se il frontend **non** e' stato rilevato, oppure `{FRAMEWORK_FRONTEND}` e' `nuxt` o `vue` → rimuovi l'intera Sezione VI (da `## VI.` fino a prima di `## VII.`)
   - **Multi-progetto**: mantieni Sezione VI se **qualsiasi** sub-project ha `{FRAMEWORK_FRONTEND}` diverso da `nuxt` e `vue`
2. Se `{FRAMEWORK_FRONTEND}` **non** e' `nuxt` ne' `vue` → rimuovi l'intera Sezione VII (da `## VII.` fino a prima di `## VIII.`)
   - **Multi-progetto**: mantieni Sezione VII se **qualsiasi** sub-project ha `{FRAMEWORK_FRONTEND}` = `nuxt` o `vue`
   - Le due sezioni sono alternative: §VI copre Next.js / Angular / React, §VII copre Nuxt 3 / Vue 3. Un progetto con un solo framework frontend ne tiene una sola; un multi-progetto misto puo' tenerle entrambe
3. Se il mobile **non** e' stato rilevato → rimuovi l'intera Sezione VIII (da `## VIII.` fino a prima di `## IX.`)
   - **Multi-progetto**: mantieni Sezione VIII se **qualsiasi** sub-project ha mobile rilevato
4. Se il linguaggio rilevato **non** include `node` → aggiungi questa nota subito dopo la riga `## I. Principi fondamentali`:
   - **Multi-progetto**: aggiungi la nota solo se **nessun** sub-project usa `node`
   - Se il linguaggio include `terraform`, adatta il testo della nota per menzionare esplicitamente §X (vedi variante sotto)

**Nota standard** (nessun Terraform):
```
> **Nota**: Le regole specifiche a TypeScript/Zod si applicano ai progetti TypeScript.
> Per altri linguaggi, applicare il principio equivalente (validazione schema-first
> con lo strumento appropriato del proprio stack, strict typing nativo del linguaggio).
```

**Nota con Terraform** (linguaggi includono `terraform` e non includono `node`):
```
> **Nota**: Le regole specifiche a TypeScript/Zod si applicano ai progetti TypeScript.
> Per altri linguaggi, applicare il principio equivalente. Per progetti Terraform / HCL,
> le regole IaC sono codificate in **§X (Infrastructure as Code)** piu' avanti in questo
> documento.
```

5. Se `infrastructure` **non** e' stato rilevato → rimuovi l'intera Sezione X (da `## X.` fino alla fine del documento, **preservando il blocco footer** `*Version: ...*`)
   - **Multi-progetto**: mantieni Sezione X se **qualsiasi** sub-project ha `infrastructure` rilevato
   - Quando la Sezione X viene rimossa, rimuovi anche la nota `> **Note for Terraform projects**` subito dopo `## I. Core Principles` (per evitare un puntatore a una sezione inesistente)

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
- `{{TYPECHECK_COMMAND}}` → il comando di type-check rilevato. Per progetti Node con `tsconfig.json`, leggi `package.json.scripts.typecheck` o `package.json.scripts['type-check']`; se mancano, usa `tsc --noEmit`. Per altri stack, lascia `non rilevato`.
- `{{QUALITY_COVERAGE_TARGET}}` → soglia di coverage. Default: `80%` con commento `(industry baseline; adjust if your team has set a different bar)`. Se il `package.json` o il config del test runner espone una soglia esplicita, usa quella.
- `{{VCS_OPS_NOTE}}` → riga informativa sul provider Git rilevato al Passo 2c. Scegli una delle seguenti in base a `{VCS}`:
  - `github` → `> GitHub operations (branch, PR, commit) are performed with the \`gh\` CLI.`
  - `gitlab` → `` > GitLab operations (branch, MR, commit) are performed with the `glab` CLI. MR descriptions follow `.gitlab/merge_request_templates/Default.md` when present. ``
  - `none` / `other` → `` > Git operations via the `git` CLI. No remote provider configured. ``

**Project Identity (interattivo, modalita' EXISTING e GREENFIELD):**

Emetti UNA singola domanda batch con tre sotto-campi e raccogli le risposte. Lascia `{{TODO: <hint>}}` per i campi vuoti — non improvvisare valori.

> Domanda da porre allo sviluppatore:
>
> "Per popolare la sezione `Project Identity` di AGENTS.md mi servono tre informazioni brevi (premi Invio per saltare un campo, lo lascio come TODO):
> - **Name**: nome corto del progetto (es. 'Acme Web App')
> - **Purpose**: una frase su cosa fa il progetto
> - **Primary users**: chi lo usa (es. 'consumer travelers', 'internal ops')"

Sostituzioni:
- `{{PROJECT_NAME}}` → risposta del developer, oppure `{{TODO: short app name}}`
- `{{PROJECT_PURPOSE}}` → risposta del developer, oppure `{{TODO: one-sentence purpose}}`
- `{{PROJECT_PRIMARY_USERS}}` → risposta del developer, oppure `{{TODO: who uses this app}}`

**Infrastructure (auto-detect + TODO, modalita' EXISTING e GREENFIELD):**

Tenta auto-detection nell'ordine sotto; tutto cio' che non e' rilevabile diventa `{{TODO: <hint>}}`:

- `{{INFRA_VCS_CI}}` → combina:
  - VCS: parsa l'URL del remote da `.git/config` (`gitlab.com` → `GitLab`, `github.com` → `GitHub`, `bitbucket.org` → `Bitbucket`, `dev.azure.com` → `Azure DevOps`)
  - CI: presenza di `.gitlab-ci.yml` → `GitLab CI`; `.github/workflows/` → `GitHub Actions`; `.circleci/config.yml` → `CircleCI`; `bitbucket-pipelines.yml` → `Bitbucket Pipelines`; `azure-pipelines.yml` → `Azure Pipelines`; `Jenkinsfile` → `Jenkins`
  - Risultato: `<VCS> + <CI>` (es. `GitLab + GitLab CI`). Se VCS rilevato e CI no, scrivi `<VCS>, CI: {{TODO: which CI provider}}`.
- `{{INFRA_SECRETS}}` → presenza di `dotenv-vault.json` o `.env.vault` → `dotenv-vault`; `*.tfstate` con backend `vault` → `HashiCorp Vault`; `aws-secretsmanager` o `aws ssm` riferimenti in IaC/CI → `AWS Secrets Manager` / `AWS Parameter Store`. Altrimenti `{{TODO: secrets manager (e.g. dotenv-vault, AWS SSM, Vault)}}`.
- `{{INFRA_HOSTING}}` → euristica leggera dal CI: rileva nomi di provider in step di deploy (`vercel`, `netlify`, `aws-eks`, `kubectl`, `gcloud run`, `firebase deploy`). Altrimenti `{{TODO: hosting/deploy target}}`.
- `{{INFRA_OBSERVABILITY}}` → presenza di `datadog.yaml` / dipendenza `dd-trace` → `Datadog`; `sentry.client.config.*` o `@sentry/*` in package.json → `Sentry`; `newrelic.{yml,json}` → `New Relic`. Altrimenti `{{TODO: observability tool}}`.

**Boundaries (semi-auto, modalita' EXISTING e GREENFIELD):**

- `{{BOUNDARIES_ALWAYS}}` → seed automatico con i comandi di qualita' rilevati, formato bullet list:
  - `- Run \`{{TEST_COMMAND}}\` before commit` (omettilo se `{{TEST_COMMAND}}` e' `non rilevato`)
  - `- Run \`{{LINT_COMMAND}}\` before commit` (omettilo se `{{LINT_COMMAND}}` e' `non rilevato`)
  - `- Run \`{{TYPECHECK_COMMAND}}\` before commit` (omettilo se `{{TYPECHECK_COMMAND}}` e' `non rilevato`)
  - Se tutti tre sono `non rilevato`, lascia `{{TODO: list always-do actions for this project}}`
- `{{BOUNDARIES_ASK_FIRST}}` → `{{TODO: list actions that require explicit go-ahead (e.g. adding new dependencies, schema migrations, brand-color changes)}}`
- `{{BOUNDARIES_NEVER_EXTRA}}` → vuota di default (la lista `Never Do` di base e' gia' nel template; aggiungi qui solo le proibizioni specifiche del progetto). Esempio se rilevi un repo con prod ref non standard: `- Push to <branch-name> without explicit go-ahead`.

**Valori placeholder per modalita' GREENFIELD:**

In base allo stack scelto nel Passo 2b:

| Stack | `{{STACK_DESCRIPTION}}` | `{{TEST_COMMAND}}` | `{{LINT_COMMAND}}` |
|---|---|---|---|
| Web Frontend | `**Web Frontend**: Next.js 14+ / Angular 17+ / React 18+, ShadCN/UI, Tailwind CSS, Zod, Jest + Testing Library` | `npm test` | `npm run lint` |
| Backend Node | `**Backend Node**: Node.js 20+, NestJS 10+, Zod + class-validator, Jest + Supertest, Prisma` | `npm test` | `npm run lint` |
| Mobile (Flutter) | `**Mobile**: Flutter 3.24+ (BLoC/Riverpod)` | `flutter test` | `dart analyze` |
| Mobile (React Native) | `**Mobile**: React Native con Expo (Zustand/Jotai)` | `npm test` | `npm run lint` |
| Infrastructure (Terraform) | `**Infrastructure**: Terraform — segui la versione pinnata del repo, remote state con locking + encryption at rest, HashiCorp style guide` | `terraform validate` | `terraform fmt -check -recursive` |

**Per modalita' UPDATE:** Rigenera come per EXISTING o GREENFIELD (a seconda dello stato del progetto).

**Conflict detection**: Se `AGENTS.md` esiste gia', chiedi allo sviluppatore prima di sovrascrivere.

**Framework-specific block — Next.js (`AGENTS.md` bundled-docs convention)**:

Se `{FRAMEWORK_FRONTEND}` == `nextjs`, prepend il blocco canonico Next.js al `AGENTS.md` generato, **prima** di tutto il contenuto derivato dal template:

```md
<!-- BEGIN:nextjs-agent-rules -->

# Next.js: ALWAYS read docs before coding

Before any Next.js work, find and read the relevant doc in `node_modules/next/dist/docs/`. Your training data is outdated — the docs are the source of truth.

<!-- END:nextjs-agent-rules -->

```

I marker `BEGIN:nextjs-agent-rules` / `END:nextjs-agent-rules` delimitano una sezione gestita da `next upgrade` (Next.js 16.2+): tutto cio' che e' tra i marker viene riscritto agli upgrade, tutto cio' che e' fuori e' preservato. Tenere il contenuto del plugin sotto il `END` marker garantisce che `next upgrade` non lo sovrascriva. Per dettagli completi vedi `profiles/nextjs.md`.

In base a `{FRAMEWORK_FRONTEND_VERSION}` (parsato come major.minor, es. `16.0`, `17.2`):

- `>= 16.2` → i docs sono bundled in `node_modules/next/dist/docs/`. Aggiungi al riepilogo del Passo 9: "esegui `npx next upgrade@canary` periodicamente per aggiornare il blocco AGENTS.md."
- `< 16.2` → i docs **non** sono bundled. Aggiungi al riepilogo del Passo 9: "esegui `npx @next/codemod@latest agents-md` per generare i docs in `.next-docs/` e aggiornare il path nel blocco."

**Brownfield**: se `AGENTS.md` esiste gia' e contiene un blocco `BEGIN:nextjs-agent-rules` … `END:nextjs-agent-rules`, **non rigenerare** il contenuto interno. Preserva il blocco verbatim e plug il template del plugin sotto la chiusura `END`. Il blocco interno e' territorio di Next.js — riscriverlo confliggerebbe con il prossimo `next upgrade`.

**Convenzioni framework scoperte a runtime**:

Se la verifica del Passo 2a ha popolato `{FRAMEWORK_AGENTS_CONVENTION}` per un framework diverso da Next.js (o per una versione di Next.js piu' recente di quanto documentato sopra), applica la stessa strategia di iniezione: marker delimitati al top del file, contenuto del template del plugin sotto la chiusura. Precedenza: profile hard-coded (es. il blocco Next.js sopra) → convenzione runtime → nessuna iniezione. In caso di conflitto fra profile hard-coded e runtime, il profile vince e la convenzione runtime viene segnalata come "non applicata, fonte hard-coded ha precedenza" nel riepilogo del Passo 9.

Scrivi il risultato in `AGENTS.md` nella root del progetto.

#### 5B — Multi-progetto (o stack fullstack)

Genera **due livelli** di AGENTS.md: uno alla root e uno per ogni sub-project **applicazione**. Le librerie non ricevono file di setup per-progetto — la loro usage viene citata nel REGISTRY dell'applicazione che le consuma (vedi sotto, "Citazione delle librerie consumate").

**Classificazione sub-project (application vs library)**, in ordine di priorita':

1. Path matcha `applications/*`, `apps/*`, `services/*` → **application**
2. Path matcha `libraries/*`, `libs/*`, `packages/*` → **library**
3. `package.json` ha `"private": false` E `"main"`/`"exports"` → **library** (forma pubblicabile)
4. `package.json` ha `scripts.dev` o `scripts.start` → **application** (forma eseguibile)
5. Altrimenti → chiedi allo sviluppatore (default: **application**)

Salva la classificazione per ciascun sub-project come `{SUBPROJECT_TYPE}`.

**Root AGENTS.md** — usa `${CLAUDE_SKILL_DIR}/templates/AGENTS.workspace-template.md`:
- `{{WORKSPACE_STRUCTURE}}` → genera una tabella con TUTTI i sub-project confermati (apps + libs), con colonna `Type` e con la colonna `Instructions` differenziata:
  ```
  | Project | Type | Path | Stack | Instructions |
  |---|---|---|---|---|
  | web   | application | apps/web/ | Next.js 14+, React 18+ | [apps/web/AGENTS.md](apps/web/AGENTS.md) |
  | api   | application | apps/api/ | Node.js 20+, NestJS 10+ | [apps/api/AGENTS.md](apps/api/AGENTS.md) |
  | shared | library    | libs/shared/ | TypeScript, Zod | (no per-library file — see consuming app REGISTRY) |
  ```
- Aggiungi sotto la tabella la nota:
  > Libraries do not get per-project setup files. When a library exposes an interesting pattern, ADR, or breaking change, add a `### library/<name>` entry to the **consuming application's `REGISTRY.md`** under "Services and utilities" — that's where library usage is documented.
- `{{PROJECT_NAME}}`, `{{PROJECT_PURPOSE}}`, `{{PROJECT_PRIMARY_USERS}}`, `{{INFRA_VCS_CI}}`, `{{INFRA_SECRETS}}`, `{{INFRA_HOSTING}}`, `{{INFRA_OBSERVABILITY}}`, `{{QUALITY_COVERAGE_TARGET}}`, `{{TEST_COMMAND}}`, `{{LINT_COMMAND}}`, `{{TYPECHECK_COMMAND}}`, `{{BOUNDARIES_ALWAYS}}`, `{{BOUNDARIES_ASK_FIRST}}`, `{{BOUNDARIES_NEVER_EXTRA}}` → segui le stesse istruzioni del Passo 5A (prompt interattivo per Project Identity, auto-detect per Infrastructure, semi-auto per Boundaries). Per i comandi di workspace, preferisci la forma multi-progetto del build tool: Nx → `nx run-many -t <target>`; pnpm workspace puro → `pnpm -r <script>`; turbo → `turbo run <task>`. Se ne rilevi piu' di uno, usa quello esposto come root script in `package.json`.
- Scrivi il risultato in `AGENTS.md` nella root

**AGENTS.md per sub-project** — usa `${CLAUDE_SKILL_DIR}/templates/AGENTS.project-template.md`:

**Solo per i sub-project con `{SUBPROJECT_TYPE} == 'application'`**, sostituisci i placeholder:
- `{{PROJECT_NAME}}` → nome descrittivo del sub-project (es. "Web Frontend", "Backend API")
- `{{STACK_DESCRIPTION}}` → stack rilevato del sub-project (stessi criteri del punto 5A)
- `{{TEST_COMMAND}}` → test runner rilevato nel sub-project
- `{{LINT_COMMAND}}` → linter rilevato nel sub-project
- `{{ROOT_AGENTS_REL_PATH}}` → path relativo alla root (es. `../../AGENTS.md`)

Scrivi il risultato in `<sub-project-path>/AGENTS.md`.

I sub-project con `{SUBPROJECT_TYPE} == 'library'` **non ricevono** AGENTS.md / CLAUDE.md / REGISTRY.md.

**Citazione delle librerie consumate** (per ogni applicazione):

Per ogni sub-project con `{SUBPROJECT_TYPE} == 'application'`, leggi il suo `package.json` e identifica le dipendenze workspace verso le librerie del monorepo. Una dipendenza e' workspace-resolved quando:
- Il valore e' `workspace:*`, `workspace:^`, `workspace:~`, o `workspace:<version>`
- Oppure il nome del package matcha esattamente il `name` di un sub-project con `{SUBPROJECT_TYPE} == 'library'`

Per ogni libreria consumata, aggiungi una entry in `<app>/REGISTRY.md` sezione "Services and utilities" usando questo template:

```markdown
### library/<name>

- **Where**: `libraries/<name>/` (o il path effettivo) — workspace package
- **Used by**: this application (aggiungi le altre app che la consumano, separate da virgola)
- **Summary**: <una riga; usa la `description` di `<lib>/package.json` se presente, oppure il primo paragrafo significativo del README della libreria; se nessuno e' utilizzabile, scrivi "TBD — refine when first touched">
```

Cosi' l'agente AI che lavora nell'applicazione vede subito quali librerie usa, dove vivono, e ha un punto da cui partire per indagare il loro contenuto. Quando il team aggiunge pattern/ADR che toccano una libreria, vivono nel REGISTRY dell'app consumante e possono fare riferimento a `### library/<name>` per ancoraggio.

---

### Passo 5b — Genera CLAUDE.md

Claude Code legge `CLAUDE.md`, non `AGENTS.md`. Per garantire compatibilita' con Claude Code
e al tempo stesso mantenere `AGENTS.md` come standard cross-tool,
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

Il plugin **non** dichiara server MCP propri: ogni server pesa sul contesto di ogni
sessione, quindi si registra solo cio' che il progetto usa davvero. Questo passo
decide in base alla detection del Passo 2.

Verifica se `claude` CLI e' disponibile con `command -v claude`. Se non lo e', stampa i comandi da eseguire manualmente e vai al passo successivo.

> **Transport**: `-t` accetta `stdio`, `sse`, `http`. `url` non e' un transport valido:
> un server dichiarato con `"type": "url"` viene scartato in silenzio.

#### 6.1 — ClickUp (user scope, solo con la lista task configurata)

ClickUp serve solo se il team traccia i task su ClickUp. Cerca `CLICKUP_SETUP_LIST_ID`
in quest'ordine: variabile d'ambiente, `.env` del progetto, `userConfig` del plugin.

- **Valorizzato** → controlla con `claude mcp list` se `clickup` e' gia' configurato. Se non lo e':
  ```bash
  claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp
  ```
- **Vuoto o assente** → **non** registrare il server. Riporta nel riepilogo del Passo 9:
  "ClickUp MCP non configurato: valorizza `CLICKUP_SETUP_LIST_ID` in `.env`, poi esegui
  `claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`".

#### 6.2 — Documentazione librerie: CLI `ctx7`, non MCP

**Non** registrare Context7 come server MCP. `AGENTS.md` dichiara la CLI `ctx7` come
fonte preferita — piu' veloce e senza budget di tool-call — quindi il server
duplicherebbe la stessa capacita' pagando le sue tool definition a ogni sessione.

Verifica con `command -v ctx7`:
- **presente** → nulla da fare
- **assente** → nulla da installare: `AGENTS.md` istruisce a invocarla via `npx ctx7@latest <command>`

Solo se ne' la CLI ne' `npx` sono raggiungibili (ambiente senza rete npm), segnala nel
riepilogo del Passo 9 il fallback manuale:
```bash
claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest
```

#### 6.3 — Figma (project scope, solo se frontend o mobile rilevato)

Solo se il Passo 2 ha rilevato frontend o mobile, o se lo stack scelto al Passo 2b e'
web-frontend / mobile / fullstack. Su un backend puro Figma **non** si registra.

Chiedi allo sviluppatore: "Vuoi configurare il MCP Figma? L'autenticazione avviene via OAuth nel browser."
Se risponde si':
```bash
claude mcp add figma -t http -s project https://mcp.figma.com/mcp
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

Verifica che siano installati: `node` (**v24+**), `npm`, `git`. Se mancano, informa lo sviluppatore
e fermati.

Node 24 e' il minimo reale, non una preferenza: `semantic-release@25` richiede
`^22.14.0 || >=24.10.0`, `lint-staged@17` richiede `>=22.22.1`, `eslint@9` richiede
`^20.19.0 || ^22.13.0 || >=24`. Node 20 e' in EOL dal 2026-04-30.

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
npm install --save-dev husky lint-staged @commitlint/cli @commitlint/config-conventional \
  prettier 'eslint@^9.39.0' '@eslint/js@^9.39.0' typescript-eslint globals typescript
```

**Non installare `eslint` senza pin**: la `latest` e' la 10.x, e i plugin dei profili
frontend (`eslint-plugin-react`, `eslint-plugin-jsx-a11y`, `eslint-plugin-import`)
dichiarano `eslint: ^9` come peer massimo — con la 10 l'install esce in `ERESOLVE`.

`typescript-eslint` (pacchetto unico) sostituisce la coppia
`@typescript-eslint/eslint-plugin` + `@typescript-eslint/parser`: e' la forma
prevista dalla flat config.

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

Copia i file dal boilerplate distribuito con la skill
(`${CLAUDE_SKILL_DIR}/templates/boilerplate/`) — non riscriverli a mano: la
copia e' l'unica forma che resta allineata al template.

| Sorgente nel boilerplate | Destinazione nel progetto | Condizione |
|---|---|---|
| `.commitlintrc.json` | `.commitlintrc.json` | sempre |
| `.lintstagedrc.json` | `.lintstagedrc.json` | sempre (gli hook husky del Passo 8.3 chiamano `npx lint-staged`) |
| `eslint.config.base.mjs` | `eslint.config.base.mjs` | sempre |
| `.prettierrc.json` | `.prettierrc.json` | stack **senza** Tailwind |
| `.prettierrc.tailwind.json` | `.prettierrc.json` | stack **con** Tailwind (web-frontend, mobile RN) |
| `.releaserc.github.json` | `.releaserc.json` | `vcs = github` |
| `.releaserc.gitlab.json` | `.releaserc.json` | `vcs = gitlab` |

Sul `vcs = none` / `other` **salta** `.releaserc.json`: non c'e' un provider a
cui pubblicare release. I due `.releaserc.*` differiscono solo nell'ultimo
plugin (`@semantic-release/github` vs `@semantic-release/gitlab`).

`.prettierrc.tailwind.json` e' identico alla variante base piu'
`plugins: ["prettier-plugin-tailwindcss"]`. Copialo **solo** se il profilo
installa `prettier-plugin-tailwindcss`: senza il plugin installato Prettier
esce in errore a ogni run.

`eslint.config.base.mjs` e' la base condivisa in **flat config**. Il file che
ESLint legge davvero e' `eslint.config.mjs`, che il Passo 8.5 crea dal profilo
importando la base. Se lo stack non ha un profilo con config ESLint, crea un
`eslint.config.mjs` che si limita a rilanciare la base:

```javascript
// eslint.config.mjs
import base from './eslint.config.base.mjs';

export default base;
```

#### 8.4b — Script npm

Senza questi script `npm run lint`, gli hook husky e la CI del boilerplate
falliscono con *Missing script*. Aggiungili al `package.json`:

```bash
npm pkg set \
  scripts.lint="eslint ." \
  scripts.lint:fix="eslint . --fix" \
  scripts.format="prettier --write ." \
  scripts.typecheck="tsc --noEmit" \
  scripts.test="jest" \
  scripts.test:cov="jest --coverage" \
  scripts.prepare="husky"
```

Adatta `test`/`test:cov` al runner del profilo (`vitest` / `vitest --coverage`,
`flutter test` su Flutter) e `typecheck` allo stack: sono i tre comandi che la
CI del boilerplate esegue come quality gate.

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
2. **ESLint**: Se il profilo contiene una configurazione ESLint, crea `eslint.config.mjs` con quel
   contenuto (flat config — importa `./eslint.config.base.mjs` copiata al Passo 8.4)
3. **TypeScript**: Se il profilo contiene una configurazione TypeScript, crea `tsconfig.json`
4. **Jest**: Se il profilo contiene una configurazione Jest, crea `jest.config.mjs` — **non** `.ts`:
   Jest non parsa un config TypeScript senza `ts-node` installato

Per lo stack **fullstack** (multi-progetto):
- Crea la struttura `apps/web/` e `apps/api/`
- Applica il profilo web-frontend in `apps/web/`
- Applica il profilo backend-node in `apps/api/`
- Genera `AGENTS.md`, `CLAUDE.md` e `REGISTRY.md` per ogni sub-project (come descritto nei Passi 5B e 5b)
- Alla root usa il workspace template (come descritto nel Passo 5B)

#### 8.6 — CI/CD workflow

Scegli il template CI in base a `{VCS}` rilevato al Passo 2c.

- `vcs = github` → copia **entrambi** i workflow da
  `${CLAUDE_SKILL_DIR}/templates/boilerplate/.github/workflows/` in `.github/workflows/`
  (crea la directory se manca): `ci.yml` (quality gate su ogni PR) e `release.yml`
  (quality gate + semantic-release sul default branch). Il release richiede il secret
  `GITHUB_TOKEN`, fornito di default da GitHub Actions.
- `vcs = gitlab` → copia `${CLAUDE_SKILL_DIR}/templates/boilerplate/.gitlab-ci.yml` in
  `.gitlab-ci.yml` nella root del progetto. Contiene lo stage `test` (che gira sulle
  pipeline di MR e sul default branch) e lo stage `release`. Richiede una variabile CI/CD
  `GITLAB_TOKEN` con scope `api` + `write_repository` (Settings → CI/CD → Variables).
- `vcs = none` / `other` → **salta questo passo**. Informa lo sviluppatore che puo' aggiungere manualmente un workflow CI al provider che preferisce.

Entrambi i template girano su **Node 24** ed eseguono gli stessi step: `npm ci`,
`npm run lint`, `npm run typecheck`, `npm run test:cov` e — solo sul default branch e
solo se il quality gate e' verde — `npx semantic-release`. I commit con `[skip ci]`
sono bypassati.

Il quality gate dipende dagli script npm del Passo 8.4b: se mancano, la CI
fallisce con *Missing script*.

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
  - /dev-setup:sdd         — SDD interattivo (spec → approvazione → sviluppo, con checkpoint)
  - /dev-setup:auto-sdd    — SDD autonomo end-to-end (fino alla PR, senza intervento umano)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — Code review con CONSTITUTION

Stack rilevato:
  - Linguaggi:      <linguaggi>
  - Test runner:    <test_command>
  - Linter:         <lint_command>
  - Validazione:    <validation_tool>
  - Infrastructure: <si|no> (se si: applicata §X CONSTITUTION, skill terraform profilo)
  - VCS:            <github|gitlab|none|other> → skill VCS attiva: <github-ops|gitlab-ops|nessuna>

NON modificato (tooling esistente rispettato):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Prossimi passi:
  1. Compila CLICKUP_SETUP_LIST_ID nel file .env
  2. Verifica MCP: claude mcp list
  3. Usa /dev-setup:sdd (interattivo) o /dev-setup:auto-sdd (autonomo) per iniziare un task ClickUp
```

**Per GREENFIELD:**
```
Setup completato!

Configurazione del progetto:
  - CLAUDE.md               — entry point per Claude Code (importa AGENTS.md)
  - AGENTS.md               — istruzioni per agenti AI (standard cross-tool)
  - CONSTITUTION.md         — regole di governance
  - REGISTRY.md             — registro feature e servizi
  - .claude/settings.json   — permessi progetto
  - .husky/                 — git hooks (lint + commit)
  - .lintstagedrc.json      — lint-staged (usato dall'hook pre-commit)
  - eslint.config.base.mjs  — ESLint base (flat config)
  - eslint.config.mjs       — ESLint profilo <stack> (importa la base)
  - .prettierrc.json        — Prettier (variante Tailwind se lo stack la usa)
  - .commitlintrc.json      — Conventional Commits
  - .releaserc.json         — semantic-release (variante <github|gitlab>)
  - <CI config>             — .github/workflows/{ci,release}.yml (GitHub) oppure .gitlab-ci.yml (GitLab)
  - .env.example            — variabili d'ambiente
  - package.json scripts    — lint, lint:fix, format, typecheck, test, test:cov

Skills disponibili (fornite dal plugin):
  - /dev-setup:sdd         — SDD interattivo (spec → approvazione → sviluppo, con checkpoint)
  - /dev-setup:auto-sdd    — SDD autonomo end-to-end (fino alla PR, senza intervento umano)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — Code review con CONSTITUTION

VCS rilevato: <github|gitlab|none|other> → skill VCS attiva: <github-ops|gitlab-ops|nessuna>
Infrastructure: <si|no>

Prossimi passi:
  1. Copia .env.example in .env e compila le variabili
  2. Verifica MCP: claude mcp list
  3. Usa /dev-setup:sdd (interattivo) o /dev-setup:auto-sdd (autonomo) per iniziare!
```

**Nota GREENFIELD Terraform**: se lo stack scelto e' **Infrastructure / Terraform**, il Passo 8 non genera boilerplate Terraform (nessun `.gitignore` Terraform auto-emesso, nessun workflow CI auto-emesso, nessun `versions.tf` scaffold). Lo sviluppatore deve creare manualmente `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf` (o `versions.tf`) e il blocco `backend "s3"` seguendo le ricette in `profiles/terraform.md`. Aggiungi al riepilogo GREENFIELD:
```
  [Terraform GREENFIELD] Il plugin NON ha generato boilerplate Terraform.
                         Vedi profiles/terraform.md per la struttura consigliata e le ricette CI.
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
  - /dev-setup:sdd         — SDD interattivo (spec → approvazione → sviluppo, con checkpoint)
  - /dev-setup:auto-sdd    — SDD autonomo end-to-end (fino alla PR, senza intervento umano)
  - /dev-setup:tdd         — Test-Driven Development
  - /dev-setup:bdd         — Behavior-Driven Development
  - /dev-setup:review      — Code review con CONSTITUTION

VCS rilevato: <github|gitlab|none|other> → skill VCS attiva: <github-ops|gitlab-ops|nessuna>
Infrastructure: <si|no> (se si: ogni sub-project Terraform ha la §X CONSTITUTION applicata)

NON modificato (tooling esistente rispettato):
  - Git hooks, ESLint, Prettier, CI/CD, .gitignore

Prossimi passi:
  1. Compila CLICKUP_SETUP_LIST_ID nel file .env
  2. Verifica MCP: claude mcp list
  3. Usa /dev-setup:sdd (interattivo) o /dev-setup:auto-sdd (autonomo) per iniziare un task ClickUp
```

---

## Note importanti

- **Verbatim**: settings.json e REGISTRY.md devono essere scritti esattamente come letti dal plugin. Non generare il contenuto di questi file — leggilo e copialo.
- **Conflict detection**: Chiedi sempre prima di sovrascrivere file esistenti.
- **Tooling esistente**: In modalita' EXISTING, non installare ne' modificare: git hooks, linter, formatter, CI/CD, .gitignore, dipendenze. Innesta solo il workflow AI.
- **Skills e agents**: NON installare skills e agents nel progetto. Sono forniti dal plugin e disponibili automaticamente come /dev-setup:<skill-name>.
- **gh CLI**: Necessaria solo per la configurazione MCP (Passo 6) e per operazioni greenfield. Se non presente, il setup puo' comunque completarsi — stampa i comandi MCP da eseguire manualmente.
- **VCS (GitHub vs GitLab)**: Il Passo 2c rileva il provider dal remote `origin`. Entrambe le skill `github-ops` e `gitlab-ops` sono sempre installate — ciascuna fa self-check all'invocazione e si disattiva se il repo non e' suo. Le skill di workflow (`sdd`, `auto-sdd`) chiamano quella corretta in base al remote corrente.
