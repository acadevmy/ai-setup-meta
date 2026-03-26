# ai-setup-meta

Repository di governance AI. Contiene i template multi-dominio, gli asset condivisi (agents, skills, profili)
e il **setup agent** che li distribuisce ai progetti degli sviluppatori.

## Setup per sviluppatori

Per aggiungere il workflow AI-Native a qualsiasi progetto (nuovo o esistente):

Se hai già una cartella .claude/ skills e agents, fai prima un backup:

```bash
# 1. Clona il repo di distribuzione e copia skill + agents nel tuo progetto
gh repo clone acadevmy/dev-setup-template .tmp-ai-setup && \
  cp -r .tmp-ai-setup/.claude/skills .claude/skills && \
  cp -r .tmp-ai-setup/.claude/agents .claude/agents && \
  rm -rf .tmp-ai-setup

# 2. Avvia Claude Code ed esegui il setup
claude
# poi digita: /project:setup
```

Se non hai una cartella .claude nel progetto

```bash
mkdir .claude && mkdir .claude/skills && gh repo clone acadevmy/dev-setup-template ./tmp-ai-setup && \
  cp -r ./tmp-ai-setup/.claude/skills .claude/skills && \
  cp -r ./tmp-ai-setup/.claude/agents .claude/agents && \
  rm -rf ./tmp-ai-setup

# 2. Avvia Claude Code ed esegui il setup
claude
# poi digita: /project:setup
```

L'agente analizzera' il progetto, scarichera' le risorse da questo repository
e applichera' tutto in modo adattivo:
- **Progetto esistente**: innesta solo il workflow AI (CONSTITUTION, AGENT, skills, MCP) senza toccare il tooling
- **Progetto nuovo (greenfield)**: setup completo con quality tools, profilo stack, MCP

**Prerequisiti**: `git`, `gh` CLI (autenticata), `claude` CLI

## Architettura

```
┌─────────────────────────────────────────────────────────────┐
│                      ai-setup-meta                          │
│  (questo repo — sorgente di verita')                        │
│                                                             │
│  Contiene: template, profili stack, shared skills/agents.   │
│  Il setup agent e' pubblicato su dev-setup-template.        │
│                                                             │
│  Ogni modifica a main passa per PR obbligatoria.            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │  release script
                         │  (copia agent + dispatcher in dist/)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│          dev-setup-template (repo distribuzione)             │
│  Contiene: .claude/skills/setup/ + .claude/agents/ + README │
│  Lo sviluppatore clona con gh e copia skill + agents.       │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │  /project:setup
                         │  L'agente scarica risorse da ai-setup-meta
                         │  via raw.githubusercontent.com
                         ▼
┌─────────────────────────────────────────────────────────────┐
│            Repo progetto sviluppatore (×11)                  │
│                                                             │
│  Claude Code scarica e applica le risorse in modo adattivo. │
│  Workflow AI-Native configurato, MCP connessi.              │
└─────────────────────────────────────────────────────────────┘
```

## Struttura del meta-repo

```
ai-setup-meta/
├── AGENT.md                  # Contesto e istruzioni per Claude Code (questo repo)
├── .claude/
│   ├── settings.json         # Configurazione Claude Code per questo repo
│   ├── skills/               # Skills invocabili del meta-repo
│   │   ├── generate-setup/          # /project:generate-setup
│   │   ├── update-constitution/     # /project:update-constitution
│   │   ├── sync-profiles/           # /project:sync-profiles
│   │   ├── new-skill/               # /project:new-skill
│   │   └── release/                 # /project:release
│   └── agents/
│       ├── review.md                # Code review, conformita' CONSTITUTION
│       └── validate-template.md     # Validazione pre-release dei template
├── shared/                   # Asset comuni distribuiti ai template
│   ├── agents/
│   │   └── clickup.md               # Agent CRUD ClickUp generico
│   └── skills/
│       ├── clickup/                  # Documentazione operazioni ClickUp
│       ├── github-ops/               # Branch, PR, commit operations
│       └── render-template/          # Renderizzazione file da template
├── templates/                # Template per dominio
│   └── dev-setup/            # Template dev-setup (qui si modifica)
│       ├── manifest.json            # Dipendenze da shared/ e file specifici
│       ├── dev-setup-agent.md       # Agent di dominio (logica di bootstrap)
│       ├── AGENT.template.md        # Template per AGENT.md generato
│       ├── CONSTITUTION.md          # CONSTITUTION di riferimento per il dominio
│       ├── CHANGELOG.md             # Changelog del template
│       ├── REGISTRY.md              # Registro delle risorse del template
│       └── profiles/                # Profili stack specifici del dominio
│           ├── web-frontend.md      # Stack: Next.js, Angular, React
│           ├── backend-node.md      # Stack: Node.js, NestJS
│           └── mobile.md           # Stack: Flutter, React Native
├── dist/                     # Cio' che viene rilasciato
│   ├── setup.md                     # Dispatcher leggero (selezione dominio)
│   └── agents/
│       └── dev-setup-agent.md       # Agent di dominio (copiato da templates/)
├── scripts/
│   ├── init-meta.sh                 # Bootstrap iniziale di questo repo
│   ├── release-template.sh          # Pubblica nuova versione del template
│   └── validate-setup-urls.sh       # Verifica coerenza URL
├── mcp/
│   └── mcp.json.example             # Esempio configurazione MCP servers
└── docs/
    ├── onboarding.md                # Guida per nuovi sviluppatori
    ├── developer-guide.md           # Guida tecnica per sviluppatori
    └── workflow.md                  # Come opera Claude Code in questo repo
```

## Regole operative

- **Nessun push diretto su `main`** — nemmeno dall'agente. Sempre PR.
- **La `CONSTITUTION.md`** nel template e' la sorgente di verita' per quel dominio.
- **Le API key non entrano mai nel repo** — solo in `.env.local` (gitignored) o nei secret GitHub.
- Dopo ogni modifica ai file in `templates/` o `shared/`, eseguire `bash scripts/validate-setup-urls.sh` per verificare la coerenza.

## Avvio rapido — meta-repo (solo maintainer)

```bash
git clone git@github.com:acadevmy/ai-setup-meta.git
cd ai-setup-meta
cp .env.example .env.local
bash scripts/init-meta.sh
claude
```

## Skill disponibili

### Skill invocabili (`/project:<nome>`)

| Skill | Descrizione |
|---|---|
| `/project:generate-setup` | Genera un template (multi-dominio, guidato da manifest) |
| `/project:update-constitution` | Aggiorna CONSTITUTION e propaga ai template |
| `/project:sync-profiles` | Sincronizza i profili stack nel template di dominio |
| `/project:new-skill` | Scaffolda una nuova skill (shared o specifica) |
| `/project:release` | Pubblica una nuova versione di un template |

### Shared skills (distribuite ai template via manifest)

| Skill | Descrizione |
|---|---|
| `clickup` | Documentazione di riferimento per operazioni ClickUp |
| `github-ops` | Operazioni GitHub (branch, PR, merge) |
| `render-template` | Renderizzazione file da template con variabili |

### Agents

| Agent | File | Ruolo |
|---|---|---|
| **review** | `.claude/agents/review.md` | Code review, conformita' CONSTITUTION |
| **validate-template** | `.claude/agents/validate-template.md` | Validazione pre-release dei template |
| **clickup** (shared) | `shared/agents/clickup.md` | CRUD ClickUp generico, distribuito ai template |

1. Seleziona task da eseguire
2. Fai il plan (intervista)
3. Sviluppa - scegli la metodologia
4. Comando manuale: scrivi i test + PR
5. Messaggio su Slack a Mirko!