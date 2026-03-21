# ai-setup-meta

Repository privato di governance AI. Claude Code opera qui per **generare e mantenere** il
[dev-setup-template](../dev-setup-template) usato dagli 11 sviluppatori del team.

## Struttura

```
ai-setup-meta/
├── AGENT.md                  # Contesto e istruzioni per Claude Code (questo repo)
├── CONSTITUTION.md           # Regole inviolabili — sorgente di verità
├── .claude/
│   ├── settings.json         # Configurazione Claude Code per questo repo
│   ├── commands/             # Slash commands disponibili in questo repo
│   │   ├── generate-setup.md        # /project:generate-setup
│   │   ├── update-constitution.md   # /project:update-constitution
│   │   ├── sync-profiles.md         # /project:sync-profiles
│   │   ├── new-skill.md             # /project:new-skill
│   │   └── release.md               # /project:release
│   ├── skills/               # Skill riutilizzabili dall'agente
│   │   ├── clickup.md               # Interazione con ClickUp API
│   │   ├── github-ops.md            # Branch, PR, commit operations
│   │   ├── validate-setup.md        # Validazione coerenza del template
│   │   └── render-template.md       # Renderizzazione file da template
│   └── agents/
│       └── setup-maintainer.md      # Sotto-agente specializzato in sync
├── mcp/
│   └── mcp.json              # Configurazione MCP servers
├── profiles/
│   ├── web-frontend.md       # Stack: Next.js, Angular, React
│   ├── backend-node.md       # Stack: Node.js, NestJS
│   └── mobile.md             # Stack: Flutter, React Native
├── scripts/
│   ├── init-meta.sh          # Bootstrap iniziale di questo repo
│   └── release-template.sh  # Pubblica nuova versione del dev-setup-template
├── templates/
│   └── dev-setup-template/   # Sorgente del template per gli sviluppatori
│       ├── AGENT.md
│       ├── CONSTITUTION.md
│       ├── mcp.json.example
│       ├── .claude/
│       ├── .husky/
│       └── init.sh
└── docs/
    ├── onboarding.md         # Guida per nuovi sviluppatori
    ├── workflow.md           # Come opera Claude Code in questo repo
    └── adr/                  # Architecture Decision Records
```

## Come funziona

```
┌─────────────────────────────────────────────────────┐
│                   ai-setup-meta                     │
│  Claude Code opera qui con autonomia su task definiti│
│  Ogni modifica a main passa per PR obbligatoria      │
└────────────────────┬────────────────────────────────┘
                     │ genera / aggiorna
                     ▼
┌─────────────────────────────────────────────────────┐
│             dev-setup-template (repo GitHub)         │
│  Template clonato da ogni sviluppatore               │
└────────────────────┬────────────────────────────────┘
                     │ clone + init.sh
                     ▼
┌─────────────────────────────────────────────────────┐
│          Workstation sviluppatore (×11)               │
│  Claude Code / Codex pronti, MCP connessi            │
└─────────────────────────────────────────────────────┘
```

## Regole operative

- **Nessun push diretto su `main`** — nemmeno dall'agente. Sempre PR.
- **La `CONSTITUTION.md`** in questo repo è la sorgente di verità. Quella nel template è generata.
- **Le API key non entrano mai nel repo** — solo in `.env.local` (gitignored) o nei secret GitHub.
- **Ogni modifica al template** deve aggiornare anche `CHANGELOG.md` nel template stesso.

## Avvio rapido (prima volta)

```bash
git clone git@github.com:your-org/ai-setup-meta.git
cd ai-setup-meta
cp .env.example .env.local          # Inserire le API key
bash scripts/init-meta.sh           # Installa dipendenze e verifica MCP
claude                              # Avvia Claude Code
```

## Comandi disponibili

| Comando | Descrizione |
|---|---|
| `/project:generate-setup` | Genera/rigenera il dev-setup-template da zero |
| `/project:update-constitution` | Aggiorna le regole e propaga al template |
| `/project:sync-profiles` | Aggiorna i profili stack nel template |
| `/project:new-skill` | Crea una nuova skill per gli sviluppatori |
| `/project:release` | Tagga e pubblica nuova versione del template |
