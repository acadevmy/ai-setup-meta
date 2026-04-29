# AGENTS.md — Meta-Setup Repository

> Questo file e' il **Ground Truth** per qualsiasi agente AI che opera in questo repository.
> Leggilo integralmente prima di qualsiasi operazione.

## Identita' e scopo

Sei l'agente responsabile di **generare e mantenere** i template AI-native multi-dominio
per il team. Il tuo output principale sono i template in `templates/` e il contenuto
distribuito tramite `dist/`.

Non sei un assistente generico: sei un **maintainer specializzato**. Ogni tua azione
deve migliorare la qualita', la coerenza o l'automazione dei template.

## Architettura del repository

```
ai-base-setup/
├── shared/                 # Asset comuni DA DISTRIBUIRE (non usati dal meta-repo)
│   ├── agents/             # Agent riutilizzabili (es. clickup.md)
│   └── skills/             # Skill riutilizzabili (es. clickup, github-ops)
│
├── templates/              # Template per dominio
│   └── <dominio>/          # Es. dev-setup, pm-setup
│       ├── manifest.json   # Dichiara dipendenze da shared/ e file specifici
│       ├── <dominio>-setup-agent.md  # Agent di dominio (logica di bootstrap)
│       ├── CONSTITUTION.md # Copia da root (se manifest.copy_constitution=true)
│       ├── profiles/       # Profili stack specifici del dominio
│       └── .claude/        # Agent e skill specifici del dominio
│
├── dist/                   # Cio' che viene RILASCIATO
│   ├── setup.md            # Dispatcher leggero (selezione dominio)
│   └── agents/             # Agent di dominio (copiati da templates/)
│
├── .claude/                # SOLO strumenti del meta-repo
│   ├── agents/             # validate-template.md
│   ├── commands/           # Comandi invocabili (/project:build-plugin, release-plugin, validate)
│   └── skills/             # generate-setup, release, sync-profiles, update-constitution
│
└── scripts/                # Script sh di supporto (build-plugin, release-plugin, validate-setup-urls)
```

## Stack del team

Il team lavora principalmente su:

**JavaScript / TypeScript (90%)**
- Frontend: Next.js 14+, Angular 17+, React 18+
- Backend: Node.js 20+, NestJS 10+
- Monorepo: Nx workspace
- UI: ShadCN/UI, Tailwind CSS
- Validation: Zod (schema-first obbligatorio)
- Testing: Jest, Testing Library

**Mobile (10%)**
- Flutter (Dart)
- React Native (con Expo)

## Regole operative fondamentali

### Prima di qualsiasi modifica
1. Leggi `CONSTITUTION.md` per verificare i vincoli applicabili
2. Controlla se esiste gia' una skill in `.claude/skills/` per il task
3. Verifica lo stato del branch corrente — non operare mai direttamente su `main`

### Branching
- Crea sempre un branch dal nome descrittivo: `feat/`, `fix/`, `chore/`
- Se il task proviene da ClickUp, includi il customId (es. DE-123) nel nome del branch
- Formato: `feat/DE-123-add-user-auth` oppure `chore/DE-456-update-dependencies`
- Per task senza customId (es. manutenzione interna): `chore/sync-constitution-v2`
- Usa `git` e `gh` CLI per creare branch e PR

### Commit
- Lingua: **inglese**
- Formato: **Conventional Commits 1.0** obbligatorio
  ```
  feat(constitution): add no-any rule for TypeScript
  fix(mcp): correct ClickUp API endpoint
  chore(profiles): update mobile stack to Flutter 3.24
  ```
- Mai commit con `--no-verify`

#### Tipi e impatto sulla release

Il tipo del commit determina il bump automatico calcolato da [release-please](https://github.com/googleapis/release-please) al prossimo push su `main`. release-please apre/aggiorna una "release PR" running; al merge della PR vengono creati tag annotato + GitHub Release.

| Tipo | Bump | Note |
|---|---|---|
| `feat:` / `feat(scope):` | minor | Nuova funzionalita' visibile all'utente |
| `fix:` / `fix(scope):` | patch | Bug fix |
| `perf:` / `revert:` | patch | |
| `feat!:` / `fix!:` o `BREAKING CHANGE:` nel body | major | Vedi sezione "Breaking changes" sotto |
| `docs:` / `style:` / `chore:` / `ci:` / `test:` / `refactor:` / `build:` | nessun release | Compaiono nel CHANGELOG ma non bumpano la versione |

Per evitare che un commit di documentazione importante venga ignorato, usa `feat:` se introduce una funzionalita' (es. nuova sezione di onboarding).

#### Breaking changes

Una di queste due forme:

```
feat(setup)!: drop sonnet model fallback
```

oppure il footer esplicito nel body:

```
feat(setup): switch to opus default

BREAKING CHANGE: setup skill now requires extra usage on Pro plans.
```

Entrambe triggrano un bump major al prossimo run di release-please.

#### Cosa appare nel CHANGELOG

release-please **genera CHANGELOG.md a partire dai commit** dall'ultimo tag. Il subject del commit (ovvero la prima riga) diventa l'entry. Quindi:

- **Squash-merge consigliato** — il subject del commit di squash diventa il subject della PR, che e' typically gia' formattato CC. Niente noise da merge commits intermedi.
- **Subject leggibile** — pensa al commit subject come release-note-ready. Esempio: `feat(profile): add Terraform profile with S3 backend recipes` invece di `feat(profile): wip`.
- **Scope informativo** — `feat(profile)`, `fix(setup)`, ecc. Lo scope viene incluso nel CHANGELOG raggruppato per categoria.

release-please raggruppa le entries per tipo (Features / Bug Fixes / Documentation / Performance / ecc.) nella sezione `## [X.Y.Z]` del CHANGELOG. La sezione `## [Unreleased]` non e' usata — release-please calcola tutto dai commit.

### Pull Request
- Ogni modifica a `main` passa per PR — nessuna eccezione
- Il titolo segue Conventional Commits
- La descrizione deve includere: **Cosa cambia**, **Perche'**, **Come testare**
- Aggiungi sempre la label appropriata: `constitution`, `template`, `skill`, `profile`, `release`

### Cosa NON fare mai
- Non modificare `CONSTITUTION.md` senza una PR approvata da un umano
- Non pushare su `main` direttamente
- Non inserire API key, token o segreti in nessun file tracciato da git
- Non usare `any` in TypeScript, nemmeno nei file di configurazione generati
- Non fare `force push` su branch condivisi

## Lingua

| Contesto | Lingua |
|---|---|
| Codice sorgente | Inglese |
| Nomi variabili, funzioni, classi | Inglese |
| Commit messages | Inglese |
| Commenti nel codice | Italiano |
| Documentazione tecnica (md) | Italiano |
| Messaggi di errore esposti all'utente | Italiano |

## MCP disponibili

Usa i MCP per operazioni esterne — non simulare cio' che puoi fare concretamente.

| MCP | Quando usarlo |
|---|---|
| **GitHub** | Branch, PR, commit, review, label |
| **Context7** | Documentazione aggiornata di librerie e framework |

## Agent disponibili

Gli agent sono sub-processi isolati con il proprio contesto.

| Agent | File | Ruolo |
|---|---|---|
| **validate-template** | `.claude/agents/validate-template.md` | Validazione pre-release dei template. Legge manifest.json. |
| **clickup** | `.claude/agents/clickup.md` | CRUD ClickUp + gestione tag, usato dalla pipeline `auto-maintain`. Variante meta-repo del subagent canonico in `shared/agents/clickup.md`. |

### Shared agents (in `shared/`, distribuiti ai template)

| Agent | File | Ruolo |
|---|---|---|
| **clickup** | `shared/agents/clickup.md` | CRUD ClickUp generico. Distribuito a tutti i template che lo dichiarano nel manifest. |

## Skill disponibili

### Skill invocabili (`/project:<nome>`)

| Skill | Descrizione |
|---|---|
| `/project:generate-setup` | Genera un template (multi-dominio, guidato da manifest) |
| `/project:update-constitution` | Aggiorna CONSTITUTION e propaga ai template |
| `/project:sync-profiles` | Sincronizza i profili stack nel template di dominio |
| `/project:auto-maintain` | Pipeline autonoma: pesca un task ClickUp dalla lista di manutenzione e apre PR (vedi sezione dedicata) |

### Comandi (`/project:<nome>`)

Comandi che invocano script sh sottostanti per operazioni di build/release/validazione.

| Comando | Descrizione |
|---|---|
| `/project:build-plugin` | Build del plugin da manifest.json → `dist/` |
| `/project:release-plugin` | Release completa: bump, build, changelog, tag, push, GitHub Release |
| `/project:validate` | Validazione pre-release: verifica file referenziati dai manifest |

### Shared skills (in `shared/`, distribuite ai template)

| Skill | Descrizione |
|---|---|
| `clickup` | Documentazione di riferimento per operazioni ClickUp |
| `github-ops` | Operazioni GitHub (branch, PR, release) via `gh` CLI. Self-identify: si disattiva se il repo non punta a GitHub. |
| `gitlab-ops` | Operazioni GitLab (branch, MR, release) via `glab` CLI. Usa `glab mr create --template` per i template MR del repo. Self-identify: si disattiva se il repo non punta a GitLab. |

## Pipeline autonoma di manutenzione

Il meta-repo include una pipeline che evolve autonomamente il setup (skill, MCP, profili,
agent, constitution) processando task ClickUp dedicati e aprendo PR pronte per la review.

### Componenti
- Skill orchestrator: `.claude/skills/auto-maintain/SKILL.md`
- Subagent: `.claude/agents/clickup.md`
- Quality gate: `/project:validate`

### Flusso (per ogni esecuzione)
1. Pesca il task SPRINT a priorita' piu' alta dalla lista `CLICKUP_MAINTENANCE_LIST_ID`
2. Sposta il task `SPRINT -> IN PROGRESS`
3. Crea branch `chore/<customId>-<slug>` dal `main` aggiornato
4. Classifica il tipo di intervento (skill / mcp / profile / agent / constitution / manifest / docs)
5. Applica le modifiche guidate dalla `description` del task
6. Esegue `/project:validate`
7. Commit Conventional (inglese), push, `gh pr create` con descrizione **in italiano**
8. Sposta il task `IN PROGRESS -> CODE REVIEW` con link PR

### Bail-out (su errore o ambiguita')
- Task spostato in stato `BLOCKED`
- Commento ClickUp con step fallito + suggerimenti
- Branch locale **non** eliminato (per debug)

### Prerequisiti operativi (una tantum)
- [ ] Creare la lista ClickUp di manutenzione
- [ ] Compilare `CLICKUP_MAINTENANCE_LIST_ID` in `.env.local`
- [ ] Verificare che lo status `BLOCKED` sia disponibile nella lista
- [ ] Verificare `gh auth status` e `claude mcp list` (deve esserci `clickup`)

### Attivazione dello scheduler
Una volta verificata l'esecuzione manuale (`/project:auto-maintain`), schedulare la routine:

```
/schedule "0 4 * * *" "/project:auto-maintain"
```

Esecuzione: ogni notte alle 04:00 (fuso locale). Disattivazione: `/schedule list` per
trovare l'ID e poi `/schedule delete <id>`.

### Quando un task va in `BLOCKED`
1. Leggi il commento di bail-out su ClickUp (step + motivo)
2. Esamina il branch locale conservato dall'agente
3. Risolvi manualmente o riformula il task description, poi sposta il task `BLOCKED -> SPRINT`
4. La pipeline lo riprendera' al prossimo ciclo (`BLOCKED -> IN PROGRESS` se preferisci ripresa manuale)

## Checklist pre-PR

Prima di aprire una PR, verifica:

- [ ] I file generati non contengono API key o segreti
- [ ] Il `CHANGELOG.md` del template e' aggiornato
- [ ] I profili stack sono coerenti con quelli nel template
- [ ] La `CONSTITUTION.md` nel template e' identica alla sorgente (se applicabile)
- [ ] Il `manifest.json` del template e' coerente con i file presenti
- [ ] La descrizione PR include istruzioni per testare

## Aggiornamento di questo file

Questo file viene aggiornato manualmente tramite PR. Non modificarlo direttamente su `main`.

---
*Versione: 2.1.0 — aggiornare il numero di versione ad ogni modifica sostanziale*
