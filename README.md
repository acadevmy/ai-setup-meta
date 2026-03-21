# ai-setup-meta

Repository privato di governance AI. Claude Code opera qui per **generare e mantenere** il
`dev-setup-template` usato dagli 11 sviluppatori del team.

## Architettura a due repository

```
┌─────────────────────────────────────────────────────────────┐
│                      ai-setup-meta                          │
│  (questo repo — solo il maintainer ci lavora)               │
│                                                             │
│  Contiene: CONSTITUTION, profili stack, skill, comandi,     │
│  script di release e la SORGENTE del template in            │
│  templates/dev-setup-template/                              │
│                                                             │
│  Claude Code opera qui con autonomia su task definiti.      │
│  Ogni modifica a main passa per PR obbligatoria.            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ bash scripts/release-template.sh
                         │ (copia files, commit, tag, GitHub Release)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│           dev-setup-template (repo GitHub separato)          │
│  (GITHUB_ORG/GITHUB_TEMPLATE_REPO in .env.local)           │
│                                                             │
│  Contiene SOLO i file generati dal template.                │
│  NON va modificato direttamente — le modifiche si fanno    │
│  nel meta-repo e si pubblicano con release-template.sh.    │
│                                                             │
│  Configurato come GitHub Template Repository per            │
│  permettere "Use this template" ai developer.               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ "Use this template" su GitHub
                         │ oppure: git clone + init.sh
                         ▼
┌─────────────────────────────────────────────────────────────┐
│            Repo progetto sviluppatore (×11)                  │
│                                                             │
│  Ogni progetto e' un repo indipendente creato dal           │
│  template. Lo sviluppatore esegue init.sh per               │
│  personalizzare stack, MCP e AGENT.md.                      │
│                                                             │
│  Claude Code / Codex pronti, MCP connessi,                  │
│  semantic-release configurato per release automatiche.      │
└─────────────────────────────────────────────────────────────┘
```

## Struttura del meta-repo

```
ai-setup-meta/
├── AGENT.md                  # Contesto e istruzioni per Claude Code (questo repo)
├── CONSTITUTION.md           # Regole inviolabili — sorgente di verita'
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
│   └── release-template.sh   # Sincronizza e pubblica sul repo template
├── templates/
│   └── dev-setup-template/   # SORGENTE del template (qui si modifica)
│       ├── AGENT.md
│       ├── CONSTITUTION.md
│       ├── .releaserc.json
│       ├── .github/workflows/release.yml
│       ├── .claude/commands/start-task.md
│       ├── mcp.json.example
│       └── init.sh
└── docs/
    ├── onboarding.md         # Guida per nuovi sviluppatori
    ├── workflow.md           # Come opera Claude Code in questo repo
    └── adr/                  # Architecture Decision Records
```

## Flusso di release

```
1. Maintainer lavora nel meta-repo (branch + PR)
2. Merge su main
3. bash scripts/release-template.sh minor
   → Aggiorna versione nel meta-repo
   → Copia templates/dev-setup-template/ → repo template
   → Crea tag e GitHub Release sul repo template
4. /project:release in Claude Code → notifica il team su ClickUp
```

## Regole operative

- **Nessun push diretto su `main`** — nemmeno dall'agente. Sempre PR.
- **La `CONSTITUTION.md`** in questo repo e' la sorgente di verita'. Quella nel template e' generata.
- **Le API key non entrano mai nel repo** — solo in `.env.local` (gitignored) o nei secret GitHub.
- **Ogni modifica al template** deve aggiornare anche `CHANGELOG.md` nel template stesso.
- **Il repo template non va mai modificato direttamente** — le modifiche si fanno qui.

## Avvio rapido (prima volta)

```bash
git clone git@github.com:your-org/ai-setup-meta.git
cd ai-setup-meta
cp .env.example .env.local          # Compilare: GITHUB_ORG, GITHUB_TEMPLATE_REPO, ecc.
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
