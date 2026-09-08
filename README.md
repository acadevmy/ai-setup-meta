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

### Costo di contesto della sessione

Il plugin **non** dichiara server MCP propri: quelli che dipendono dallo stack (Figma) o
dalla configurazione del team (ClickUp) li registra `/dev-setup:setup` a livello di
progetto, e solo se servono (Passo 6 della setup skill). Per la documentazione delle
librerie il default e' la CLI `ctx7`, non il server Context7: la CLI fa lo stesso lavoro
senza pagare le tool definition in ogni sessione.

**Rete di sicurezza — `ENABLE_TOOL_SEARCH`.** Claude Code tiene le tool definition MCP
fuori dal contesto e le carica a richiesta (*tool search*, attivo di default). Con quel
meccanismo attivo un server da 58 tool costa ~1.000 token a sessione zero invece di
~31.000. La variabile serve quando il default non si applica — `ANTHROPIC_BASE_URL` verso
un proxy non first-party, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`, deployment Foundry su
Azure, modelli Agent Platform pre-4.5:

| Valore | Effetto |
|---|---|
| non impostata | tool search attivo, con i fallback sopra |
| `true` | sempre attivo (il beta header passa anche dai proxy) |
| `auto` | si attiva quando le definition deferibili arrivano al 10% della finestra |
| `auto:N` | come `auto` con soglia N% (es. `auto:5`) |
| `false` | disattivato: tutte le definition entrano in contesto a ogni turno |

Si imposta come variabile d'ambiente o nel blocco `env` di `settings.json`. Misure con
`scripts/measure-session-zero.sh` (fixture backend puro, sonnet, `--strict-mcp-config`):

| Server MCP registrati | tool | tool search attivo | tool search disattivo |
|---|---|---|---|
| nessuno | 0 | 35.479 | 51.282 |
| clickup | 58 | 36.525 | 82.030 |
| clickup + figma + context7 | 101 | 37.512 | 120.956 |

I valori assoluti includono la configurazione globale di chi misura (CLAUDE.md utente,
skill e plugin installati): confrontabili sono le differenze fra due run nello stesso
ambiente, non i totali fra macchine diverse.

**Override di modello nelle skill**: nessuna skill distribuita imposta `model:`. Il
frontmatter `model:` sposta il modello del loop principale e la cache del prompt e'
model-scoped, quindi ogni cambio nella catena paga un prefisso freddo — e l'override
resta attivo anche nei turni successivi all'uso della skill. Le skill differenziano solo
`effort`; il modello lo scegli tu per la sessione.

### Altri tool (Cursor, Codex, Copilot…)

Il plugin ha un solo target di build: **Claude Code**. I builder dedicati agli altri
runtime sono stati rimossi, perche' le skill del plugin seguono lo standard aperto
[Agent Skills](https://agentskills.io): una `SKILL.md` conforme e' leggibile dagli
altri tool **senza conversione**.

Chi lavora in un altro editor punta il proprio tool alle `SKILL.md` di
`dist/dev-setup/skills/` (o le copia nella cartella skill del progetto). Rispetto al
plugin dedicato di prima non si perde nulla di funzionante: gli hook erano lo schema
di Claude Code con una variabile rinominata — inerti fuori da Claude Code — e i
`commands/` erano copie letterali dei corpi delle skill.

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
│  → Configura i soli MCP che lo stack usa (Passo 6)          │
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
│   └── dev-setup/               # Plugin Claude Code
│       ├── .claude-plugin/      # Manifest del plugin
│       ├── skills/              # 14 skills (10 del template + 3 shared + setup)
│       ├── agents/              # 5 agents (4 del template + clickup shared)
│       └── hooks/               # hooks.json + hooks/scripts/
├── scripts/
│   ├── build-plugin.sh          # Orchestratore: legge manifest, invoca il builder
│   ├── builders/
│   │   ├── common.sh            # Funzioni condivise (ok, warn, fail, step)
│   │   └── build-claude.sh      # Builder Claude Code (unico target)
│   ├── validate-plugin.sh       # 12 check statici sulla qualita' delle skill
│   ├── validate-baseline.txt    # Fail noti, riportati ma non bloccanti in CI
│   ├── validate-setup-urls.sh   # Link check degli URL citati dalla setup skill
│   └── auto-maintain-runner.sh  # Runner della pipeline di manutenzione
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
