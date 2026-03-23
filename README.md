# ai-setup-meta

Repository di governance AI. Contiene le risorse sorgente (CONSTITUTION, profili, skills)
e il **setup agent** che le distribuisce ai progetti degli sviluppatori.

## Setup per sviluppatori

Per aggiungere il workflow AI-Native a qualsiasi progetto (nuovo o esistente):

```bash
# 1. Scarica il setup agent nel tuo progetto
mkdir -p .claude/skills && curl -sL \
  https://raw.githubusercontent.com/acadevmy/dev-setup-template/main/.claude/skills/setup.md \
  -o .claude/skills/setup.md

# 2. Avvia Claude Code ed esegui il setup
claude
# poi digita: /project:setup
```

L'agente analizzera' il progetto, scarichera' le risorse da questo repository
e applichera' tutto in modo adattivo:
- **Progetto esistente**: innesta solo il workflow AI (CONSTITUTION, AGENT, skills, MCP) senza toccare il tooling
- **Progetto nuovo (greenfield)**: setup completo con quality tools, profilo stack, MCP

**Prerequisiti**: `git`, `claude` CLI

## Architettura

```
┌─────────────────────────────────────────────────────────────┐
│                      ai-setup-meta                          │
│  (questo repo — sorgente di verita')                        │
│                                                             │
│  Contiene: CONSTITUTION, profili stack, skills.             │
│  Il setup agent e' pubblicato su dev-setup-template.        │
│                                                             │
│  Ogni modifica a main passa per PR obbligatoria.            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │  release script
                         │  (copia setup.md + README)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              dev-setup-template (repo pubblico)              │
│  Contiene SOLO: .claude/skills/setup.md + README.md         │
│  Lo sviluppatore scarica setup.md con un curl one-liner.    │
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
├── CONSTITUTION.md           # Regole inviolabili — sorgente di verita'
├── .claude/
│   ├── settings.json         # Configurazione Claude Code per questo repo
│   ├── skills/               # Skills (invocabili e di background)
│   │   ├── generate-setup.md        # /project:generate-setup
│   │   ├── update-constitution.md   # /project:update-constitution
│   │   ├── sync-profiles.md         # /project:sync-profiles
│   │   ├── new-skill.md             # /project:new-skill
│   │   ├── release.md               # /project:release
│   │   ├── generate-inject.md       # /project:generate-inject
│   │   ├── clickup.md               # Interazione con ClickUp API (background)
│   │   ├── github-ops.md            # Branch, PR, commit operations (background)
│   │   └── render-template.md       # Renderizzazione file da template (background)
│   └── agents/
│       └── setup-maintainer.md      # Sotto-agente specializzato in sync
├── mcp/
│   └── mcp.json              # Configurazione MCP servers
├── profiles/
│   ├── web-frontend.md       # Stack: Next.js, Angular, React
│   ├── backend-node.md       # Stack: Node.js, NestJS
│   └── mobile.md             # Stack: Flutter, React Native
├── dist/
│   └── setup.md              # Sorgente del setup agent (pubblicato su dev-setup-template)
├── scripts/
│   ├── init-meta.sh          # Bootstrap iniziale di questo repo
│   ├── release-template.sh   # Pubblica setup.md su dev-setup-template
│   └── validate-setup-urls.sh # Verifica coerenza URL in setup.md
├── templates/
│   └── dev-setup-template/   # SORGENTE del template (qui si modifica)
│       ├── AGENT.md
│       ├── CONSTITUTION.md
│       ├── .releaserc.json
│       ├── .github/workflows/release.yml
│       ├── .claude/skills/start-task.md
│       ├── mcp.json.example
│       └── init.sh
└── docs/
    ├── onboarding.md         # Guida per nuovi sviluppatori
    ├── workflow.md           # Come opera Claude Code in questo repo
    └── adr/                  # Architecture Decision Records
```

## Regole operative

- **Nessun push diretto su `main`** — nemmeno dall'agente. Sempre PR.
- **La `CONSTITUTION.md`** in questo repo e' la sorgente di verita'.
- **Le API key non entrano mai nel repo** — solo in `.env.local` (gitignored) o nei secret GitHub.
- Dopo ogni modifica ai file in `templates/` o `profiles/`, eseguire `bash scripts/validate-setup-urls.sh` per verificare la coerenza.

## Avvio rapido — meta-repo (solo maintainer)

```bash
git clone git@github.com:acadevmy/ai-setup-meta.git
cd ai-setup-meta
cp .env.example .env.local
bash scripts/init-meta.sh
claude
```

## Skill disponibili

| Skill | Descrizione | Auto-invocabile |
|---|---|---|
| `/project:generate-setup` | Genera/rigenera il dev-setup-template da zero | No |
| `/project:generate-inject` | Genera inject.sh per codebase esistenti | No |
| `/project:update-constitution` | Aggiorna le regole e propaga al template | No |
| `/project:sync-profiles` | Aggiorna i profili stack nel template | No |
| `/project:new-skill` | Crea una nuova skill per gli sviluppatori | No |
| `/project:release` | Tagga e pubblica nuova versione del template | No |
