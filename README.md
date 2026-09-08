# ai-setup-meta

Repository di governance AI. Contiene i template multi-dominio, gli asset condivisi (agents, skills, profili)
e il sistema **plugin + marketplace** che li distribuisce ai progetti degli sviluppatori.

## Setup per sviluppatori

### Claude Code

Per aggiungere il workflow AI-Native a qualsiasi progetto (nuovo o esistente):

```bash
# 1. Aggiungi il marketplace Acadevmy (una tantum)
/plugin marketplace add acadevmy/ai-setup-meta

# 2. Installa il plugin dev-setup
/plugin install dev-setup@acadevmy

# 3. Avvia il setup nel tuo progetto
/dev-setup:setup
```

L'agente analizzera' il progetto e applichera' tutto in modo adattivo:
- **Progetto esistente**: innesta solo il workflow AI (CONSTITUTION, AGENT, skills, MCP) senza toccare il tooling
- **Progetto nuovo (greenfield)**: setup completo con quality tools, profilo stack, MCP

**Prerequisiti**: `git`, `claude` CLI. Opzionale: `gh` CLI (per MCP ClickUp e operazioni greenfield).

### Cursor

Il plugin `dev-setup` è distribuito nativamente anche per Cursor. Per installarlo localmente:

```bash
# 1. Build del plugin (se non è già aggiornato)
bash scripts/build-plugin.sh dev-setup

# 2. Installa il plugin locale in Cursor
ln -s $(pwd)/dist/dev-setup ~/.cursor/plugins/local/dev-setup

# 3. Ricarica Cursor
# Developer → Reload Window
```

Il plugin Cursor condivide skills e agents con la versione Claude. Aggiunge:
- `commands/` — invocabili da Cursor con `/skill-name`
- `mcp.json` — MCP servers (ClickUp, Figma, Context7) compatibili con Cursor
- `hooks/hooks.cursor.json` — hooks con path variable Cursor-native

**Prerequisiti**: Cursor, `jq`.

### Gemini CLI

I template che supportano Gemini (attualmente `pm-setup`) distribuiscono comandi `.toml`
in `dist/<template>/gemini/`. Per la guida completa vedi
[dist/pm-setup/gemini/README.md](dist/pm-setup/gemini/README.md).

**Prerequisiti**: `gemini` CLI, Node.js 18+, account ClickUp.

## Architettura

```
┌─────────────────────────────────────────────────────────────┐
│                      ai-setup-meta                          │
│  (questo repo — sorgente di verita' E marketplace)          │
│                                                             │
│  templates/     — sorgente dei template per dominio         │
│  shared/        — agents e skills condivisi                 │
│  dist/          — plugin built (generati da build script)   │
│  marketplace.json — indice plugin per Claude Code           │
│                                                             │
│  Ogni modifica a main passa per PR obbligatoria.            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │  /plugin marketplace add
                         │  /plugin install dev-setup@acadevmy
                         ▼
┌─────────────────────────────────────────────────────────────┐
│            Repo progetto sviluppatore                        │
│                                                             │
│  /dev-setup:setup                                           │
│  → Rileva modalita' (UPDATE/GREENFIELD/EXISTING)            │
│  → Auto-detect stack                                        │
│  → Installa CONSTITUTION, AGENTS.md, CLAUDE.md, REGISTRY    │
│  → Configura MCP (ClickUp, Context7, Figma)                │
│  → Skills disponibili via plugin                            │
└─────────────────────────────────────────────────────────────┘
```

## Struttura del meta-repo

```
ai-setup-meta/
├── .claude-plugin/
│   └── marketplace.json         # Indice plugin per Claude Code
├── shared/                      # Asset comuni distribuiti ai template
│   ├── agents/
│   │   └── clickup.md
│   └── skills/
│       ├── clickup/
│       ├── github-ops/
│       └── gitlab-ops/
├── templates/                   # Sorgente dei template per dominio
│   └── dev-setup/
│       ├── manifest.json               # Dipendenze da shared/ e file specifici
│       ├── setup-skill.md              # Setup skill (logica di bootstrap)
│       ├── AGENTS.template.md          # Template per AGENTS.md generato
│       ├── CONSTITUTION.md
│       ├── REGISTRY.md
│       ├── CHANGELOG.md
│       ├── .claude/
│       │   ├── settings.json           # Permessi + hooks (sorgente)
│       │   ├── hooks/                  # protect-files, post-edit, on-compact
│       │   ├── agents/                 # 4 agents specifici del dominio
│       │   └── skills/                 # 10 workflow skills
│       └── profiles/
│           ├── web-frontend.md
│           ├── backend-node.md
│           ├── mobile.md
│           ├── nextjs.md
│           └── terraform.md
├── dist/                        # Plugin built (generati, committati)
│   └── dev-setup/               # Plugin Claude + Cursor (root condivisa)
│       ├── .claude-plugin/      # Manifest Claude Code
│       ├── .cursor-plugin/      # Manifest Cursor
│       ├── skills/              # 14 skills (10 del template + 3 shared + setup)
│       ├── agents/              # 5 agents (4 del template + clickup shared)
│       ├── hooks/               # hooks.json (Claude) + hooks.cursor.json (Cursor)
│       ├── commands/            # 11 commands Cursor (generati da skills)
│       ├── .mcp.json            # MCP config Claude
│       └── mcp.json             # MCP config Cursor (type rimosso)
├── scripts/
│   ├── build-plugin.sh          # Orchestratore: legge manifest, invoca i builder
│   ├── builders/
│   │   ├── common.sh            # Funzioni condivise (ok, warn, fail, step)
│   │   ├── build-claude.sh      # Builder Claude Code (sempre eseguito)
│   │   ├── build-gemini.sh      # Builder Gemini CLI (se gemini_support)
│   │   ├── build-codex.sh       # Builder Codex CLI (se codex_support)
│   │   └── build-cursor.sh      # Builder Cursor (se cursor_support)
│   ├── validate-plugin.sh       # 11 check statici sulla qualita' delle skill
│   ├── validate-baseline.txt    # Fail noti, riportati ma non bloccanti in CI
│   ├── validate-setup-urls.sh   # Link check degli URL citati dalla setup skill
│   └── auto-maintain-runner.sh  # Runner della pipeline di manutenzione
├── mcp/
│   └── mcp.json.example
└── docs/
    ├── developer-guide.md
    ├── workflow.md
    └── legacy/                  # Materiale archiviato, fuori dal prodotto
```

## Build e release

```bash
# Build plugin (genera dist/dev-setup/)
bash scripts/build-plugin.sh dev-setup

# Validazione plugin
claude plugin validate dist/dev-setup/
bash scripts/validate-plugin.sh --strict

# Test locale
claude --plugin-dir dist/dev-setup/
```

Il **release e' automatico**: [release-please](https://github.com/googleapis/release-please)
calcola il bump dai conventional commit mergiati su `main`, apre una release PR e — al merge
di quella — crea tag e GitHub Release. Nessuno script di release da lanciare a mano.
Per forzare una versione: `Release-As: X.Y.Z` nel footer di un commit.

## Regole operative

- **Nessun push diretto su `main`** — nemmeno dall'agente. Sempre PR.
- **La `CONSTITUTION.md`** nel template e' la sorgente di verita' per quel dominio.
- **Le API key non entrano mai nel repo** — solo in `.env.local` (gitignored) o nei secret GitHub.
- `dist/` e' generato da `build-plugin.sh` ma committato (il marketplace punta li').

## Skills distribuite dal plugin dev-setup

### Flusso consigliato

```
/dev-setup:setup          ← una tantum, bootstrap del progetto
       │
       ▼
/dev-setup:sdd-discovery  ← intervista strutturata per raccogliere requisiti
       │
       ▼
/dev-setup:sdd-spec       ← genera specifica tecnica dal discovery
       │
       ▼
/dev-setup:sdd-plan       ← presenta la spec per discussione e approvazione
       │
       ▼
/dev-setup:sdd-dev        ← sviluppo guidato dalla spec approvata (TDD/BDD)
       │
       ▼
/dev-setup:review         ← code review con conformita' CONSTITUTION
```

> **`/dev-setup:sdd`** orchestra l'intero flusso in un unico comando:
> task selection → branch → discovery → spec → approval → dev → simplify → verify → review → PR.
>

### Workflow skills

| Skill | Descrizione |
|---|---|
| `/dev-setup:setup` | Bootstrap AI-Native (rileva stack, installa governance) |
| `/dev-setup:sdd` | Flow Spec-Driven completo: task → discovery → spec → approval → dev → review → PR |
| `/dev-setup:sdd-discovery` | Intervista strutturata per raccogliere requisiti prima della spec |
| `/dev-setup:sdd-spec` | Genera specifica tecnica |
| `/dev-setup:sdd-plan` | Presenta spec per discussione |
| `/dev-setup:sdd-dev` | Sviluppo da spec approvata |

### Methodology skills

| Skill | Descrizione |
|---|---|
| `/dev-setup:tdd` | Test-Driven Development (Red-Green-Refactor) |
| `/dev-setup:bdd` | Behavior-Driven Development (Given/When/Then) |
| Nessuna | Sviluppo diretto senza ciclo test-first |
| `/dev-setup:review` | Code review con conformita' CONSTITUTION |

### Shared skills

| Skill | Descrizione |
|---|---|
| `/dev-setup:clickup` | Operazioni ClickUp via MCP |
| `/dev-setup:github-ops` | Branch, PR, release su GitHub (`gh` CLI). Si auto-disattiva se il repo non punta a GitHub. |
| `/dev-setup:gitlab-ops` | Branch, MR, release su GitLab (`glab` CLI). Legge `.gitlab/merge_request_templates/Default.md` quando presente. Si auto-disattiva se il repo non punta a GitLab. |

### Agents

| Agent | Ruolo |
|---|---|
| **review** | Code review, conformita' CONSTITUTION, aggiorna REGISTRY |
| **clickup** | CRUD ClickUp generico (passthrough MCP) |
