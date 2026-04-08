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

### OpenAI Codex CLI

I template che supportano Codex (attualmente `pm-setup`) distribuiscono un plugin compatibile
in `dist/<template>/codex/`. L'installazione avviene tramite il sistema marketplace di Codex:

```bash
# 1. Scarica il plugin nella directory personale
mkdir -p ~/.codex/plugins
curl -sL "https://github.com/acadevmy/ai-setup-meta/archive/refs/heads/main.tar.gz" | \
  tar -xz --strip-components=3 -C ~/.codex/plugins/ "ai-setup-meta-main/dist/pm-setup/codex"
mv ~/.codex/plugins/codex ~/.codex/plugins/pm-setup

# 2. Registra nel marketplace personale (~/.agents/plugins/marketplace.json)
# Vedi la guida completa per il contenuto del file
```

Il plugin e' accessibile con `@pm-setup` o tramite `/skills` in Codex CLI.
Per la guida completa (inclusa installazione per progetto) vedi
[dist/pm-setup/codex/README.md](dist/pm-setup/codex/README.md).

**Prerequisiti**: `codex` CLI, Node.js 18+, account ClickUp.

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
├── marketplace.json             # Indice plugin per Claude Code
├── shared/                      # Asset comuni distribuiti ai template
│   ├── agents/
│   │   └── clickup.md
│   └── skills/
│       ├── clickup/
│       └── github-ops/
├── templates/                   # Sorgente dei template per dominio
│   └── dev-setup/
│       ├── manifest.json               # Dipendenze da shared/ e file specifici
│       ├── setup-skill.md              # Setup skill (logica di bootstrap)
│       ├── dev-setup-agent.md          # Agent legacy (reference)
│       ├── AGENTS.template.md          # Template per AGENTS.md generato
│       ├── CONSTITUTION.md
│       ├── REGISTRY.md
│       ├── CHANGELOG.md
│       ├── .claude/
│       │   ├── settings.json           # Permessi + hooks (sorgente)
│       │   ├── hooks/                  # protect-files, post-edit, on-compact
│       │   └── skills/                 # 9 workflow skills
│       └── profiles/
│           ├── web-frontend.md
│           ├── backend-node.md
│           └── mobile.md
├── dist/                        # Plugin built (generati, committati)
│   ├── dev-setup/               # Plugin Claude Code self-contained
│   │   ├── .claude-plugin/plugin.json
│   │   ├── skills/              # 13 skills (template + shared + setup)
│   │   ├── agents/              # 2 agents (review + clickup)
│   │   ├── hooks/               # hooks.json + scripts
│   │   └── .mcp.json            # context7
│   └── pm-setup/                # Plugin PM multi-piattaforma
│       ├── .claude-plugin/      # Claude Code
│       ├── gemini/              # Gemini CLI (comandi .toml, mcp-remote)
│       └── codex/               # Codex CLI (SKILL.md nativi, config.toml)
├── scripts/
│   ├── build-plugin.sh          # Orchestratore: legge manifest, invoca i builder
│   ├── builders/
│   │   ├── common.sh            # Funzioni condivise (ok, warn, fail, step)
│   │   ├── build-claude.sh      # Builder Claude Code (sempre eseguito)
│   │   ├── build-gemini.sh      # Builder Gemini CLI (se gemini_support)
│   │   └── build-codex.sh       # Builder Codex CLI (se codex_support)
│   ├── release-plugin.sh        # Release: version bump + build + tag + push
│   ├── init-meta.sh
│   └── validate-setup-urls.sh
├── mcp/
│   └── mcp.json.example
└── docs/
    ├── onboarding.md
    ├── developer-guide.md
    └── workflow.md
```

## Build e release

```bash
# Build plugin (genera dist/dev-setup/)
bash scripts/build-plugin.sh dev-setup

# Validazione plugin
claude plugin validate dist/dev-setup/

# Test locale
claude --plugin-dir dist/dev-setup/

# Release (version bump + build + changelog + tag + push + GitHub Release)
bash scripts/release-plugin.sh patch dev-setup
```

## Regole operative

- **Nessun push diretto su `main`** — nemmeno dall'agente. Sempre PR.
- **La `CONSTITUTION.md`** nel template e' la sorgente di verita' per quel dominio.
- **Le API key non entrano mai nel repo** — solo in `.env.local` (gitignored) o nei secret GitHub.
- `dist/` e' generato da `build-plugin.sh` ma committato (il marketplace punta li').

## Skills distribuite dal plugin dev-setup

### Workflow skills

| Skill | Descrizione |
|---|---|
| `/dev-setup:setup` | Bootstrap AI-Native (rileva stack, installa governance) |
| `/dev-setup:start-task` | Flow rapido: branch → TDD/BDD → review → PR |
| `/dev-setup:sdd` | Flow Spec-Driven: spec → approvazione → sviluppo |
| `/dev-setup:sdd-spec` | Genera specifica tecnica |
| `/dev-setup:sdd-plan` | Presenta spec per discussione |
| `/dev-setup:sdd-dev` | Sviluppo da spec approvata |

### Methodology skills

| Skill | Descrizione |
|---|---|
| `/dev-setup:tdd` | Test-Driven Development (Red-Green-Refactor) |
| `/dev-setup:bdd` | Behavior-Driven Development (Given/When/Then) |
| `/dev-setup:review` | Code review con conformita' CONSTITUTION |

### Shared skills

| Skill | Descrizione |
|---|---|
| `/dev-setup:clickup` | Operazioni ClickUp via MCP |
| `/dev-setup:github-ops` | Branch, PR, merge operations |

### Agents

| Agent | Ruolo |
|---|---|
| **review** | Code review, conformita' CONSTITUTION, aggiorna REGISTRY |
| **clickup** | CRUD ClickUp generico (passthrough MCP) |
