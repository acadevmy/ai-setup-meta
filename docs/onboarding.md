# Onboarding sviluppatori — AI-Native Setup

Guida per configurare l'ambiente AI-native sul proprio computer.
Tempo stimato: **30–45 minuti** (prima installazione).

## Prerequisiti

| Strumento | Versione minima | Installazione |
|---|---|---|
| Node.js | 20.x LTS | [nodejs.org](https://nodejs.org) |
| git | 2.40+ | preinstallato su macOS/Linux |
| gh CLI | 2.x+ | `brew install gh` oppure [cli.github.com](https://cli.github.com) |
| Claude Code | ultima | `npm install -g @anthropic-ai/claude-code` |
| Account Claude | Piano Pro o Max | [claude.ai](https://claude.ai) |

## Passo 1 — Creare il progetto dal template

Hai due opzioni:

### Opzione A — Da GitHub (consigliata)
1. Vai su `https://github.com/YOUR_ORG/dev-setup-template`
2. Clicca **"Use this template"** > **"Create a new repository"**
3. Scegli nome e visibilita' del tuo progetto
4. Clona il repo appena creato:
   ```bash
   git clone git@github.com:YOUR_ORG/nome-progetto.git
   cd nome-progetto
   ```

### Opzione B — Da CLI
```bash
gh repo create YOUR_ORG/nome-progetto \
  --template YOUR_ORG/dev-setup-template \
  --private --clone
cd nome-progetto
```

## Passo 2 — Configurare i token MCP (account personale)

Ogni sviluppatore deve usare i **propri token personali** per i server MCP.
Non condividere mai i token con altri membri del team.

1. Copia il template MCP nella tua configurazione locale:
   ```bash
   cp mcp/mcp.json.example mcp/mcp.json
   ```

2. **ClickUp** — autenticazione OAuth (non serve API key):
   La configurazione e' gia' nel `mcp.json.example`. Al primo utilizzo, `mcp-remote`
   apre il browser per l'autenticazione OAuth con il tuo account ClickUp.
   Funziona anche per utenti guest.

3. **GitHub** — autenticazione via `gh` CLI (non serve PAT manuale):
   ```bash
   gh auth login
   ```
   Si apre il browser: accedi con il tuo account GitHub e autorizza. Le operazioni git e GitHub useranno la tua identità.

4. **Figma** (opzionale) — genera il tuo token personale:
   | Servizio | Dove generarlo |
   |---|---|
   | Figma | [figma.com/developers/api](https://www.figma.com/developers/api#access-tokens) |

   Configura la variabile d'ambiente nel tuo `~/.zshrc` (o `~/.bashrc`):
   ```bash
   export FIGMA_ACCESS_TOKEN="figd_il_tuo_token"
   ```
   Poi ricarica il terminale: `source ~/.zshrc`

## Passo 3 — Eseguire il setup agent

```bash
# Scarica il setup agent
mkdir -p .claude/skills && curl -sL \
  https://raw.githubusercontent.com/acadevmy/dev-setup-template/main/.claude/skills/setup.md \
  -o .claude/skills/setup.md

# Avvia Claude Code ed esegui il setup
claude
# poi digita: /project:setup
```

L'agente analizzera' il progetto e applichera' il setup in modo adattivo.

## Passo 4 — Verificare la configurazione

```bash
# Verifica Claude Code
claude --version

# Verifica MCP (dovrebbero apparire tutti e 4)
claude mcp list

# Verifica git hooks
cat .husky/pre-commit
```

## Passo 5 — Primo avvio

```bash
claude
```

Al primo avvio Claude Code legge automaticamente `AGENT.md` e `CONSTITUTION.md`.
Puoi subito usare i comandi slash disponibili per il tuo stack.

## Comandi slash disponibili (dopo l'init)

| Comando | Descrizione |
|---|---|
| `/project:start-task` | Prende il prossimo task da ClickUp e inizia il flusso TDD |
| `/project:new-feature` | Scaffolda una nuova feature per il tuo stack |
| `/project:write-tests` | Genera test Jest/flutter_test per il file corrente |
| `/project:simplify` | Refactoring del codice corrente |
| `/project:review` | Code review del branch corrente |
| `/project:pr` | Crea PR su GitHub con descrizione generata |

## Release automatiche con semantic-release

Il template include **semantic-release** gia' configurato. Ad ogni push su `main`,
la GitHub Action analizza i commit (Conventional Commits) e automaticamente:

- Calcola la nuova versione (major/minor/patch)
- Genera `CHANGELOG.md`
- Aggiorna la versione nel `package.json`
- Crea tag e GitHub Release

Non serve fare nulla di manuale: basta seguire le convenzioni di commit della Costituzione (regola 12).

| Tipo di commit | Effetto sulla versione |
|---|---|
| `feat(...)` | MINOR (1.0.0 -> 1.1.0) |
| `fix(...)`, `perf(...)`, `refactor(...)` | PATCH (1.0.0 -> 1.0.1) |
| Commit con `BREAKING CHANGE` nel footer | MAJOR (1.0.0 -> 2.0.0) |

Per un dry-run locale: `npm run release:dry`

## FAQ

**Posso usare Codex invece di Claude Code?**
Sì. La `CONSTITUTION.md` e i profili stack si applicano a qualsiasi agente.
Per Codex, la configurazione MCP è diversa — chiedi al maintainer del meta-repo.

**Come aggiorno il setup quando esce una nuova versione?**
Il maintainer crea un task ClickUp quando c'è una nuova release.
Segui le istruzioni nel task — di solito si tratta di rieseguire `/project:setup` che rileva e aggiorna automaticamente.

**Posso modificare la Costituzione per il mio progetto?**
No — la `CONSTITUTION.md` è condivisa e modificabile solo tramite il meta-repo.
Se hai una proposta, aprila come task ClickUp o parla con il maintainer.

**Qualcosa non funziona nel setup — a chi mi rivolgo?**
Apri un task ClickUp nella lista "AI Setup" con:
- Errore esatto (copia il testo)
- Sistema operativo e versione Node.js
- Output di `claude mcp list`
