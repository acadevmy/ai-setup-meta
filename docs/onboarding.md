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

## Passo 1 — Creare il progetto

Crea un nuovo repo (o usa uno esistente) e posizionati nella root:

```bash
# Nuovo progetto
gh repo create YOUR_ORG/nome-progetto --private --clone
cd nome-progetto

# Oppure, progetto esistente
cd /path/to/progetto-esistente
```

## Passo 2 — Configurare autenticazione e MCP (account personale)

Ogni sviluppatore deve usare i **propri account personali**.
Non condividere mai token o credenziali con altri membri del team.

1. **GitHub** — autenticazione via `gh` CLI (non serve PAT manuale):
   ```bash
   gh auth login
   ```
   Si apre il browser: accedi con il tuo account GitHub e autorizza.
   Le operazioni git e GitHub useranno la tua identita'. GitHub non usa MCP ma `gh` CLI + `git`.

2. Copia il template MCP nella tua configurazione locale:
   ```bash
   cp mcp/mcp.json.example mcp/mcp.json
   ```

3. **ClickUp** — autenticazione OAuth (non serve API key):
   La configurazione e' gia' nel `mcp.json.example`. Al primo utilizzo, `mcp-remote`
   apre il browser per l'autenticazione OAuth con il tuo account ClickUp.
   Funziona anche per utenti guest.

4. **Figma** (opzionale) — genera il tuo token personale:
   | Servizio | Dove generarlo |
   |---|---|
   | Figma | [figma.com/developers/api](https://www.figma.com/developers/api#access-tokens) |

   Configura la variabile d'ambiente nel tuo `~/.zshrc` (o `~/.bashrc`):
   ```bash
   export FIGMA_ACCESS_TOKEN="figd_il_tuo_token"
   ```
   Poi ricarica il terminale: `source ~/.zshrc`

5. **Context7** — nessuna configurazione necessaria:
   Gia' incluso nel `mcp.json.example`, funziona senza token.

## Passo 3 — Eseguire il setup agent

```bash
# Clona il repo di distribuzione e copia skill + agents nel progetto
gh repo clone YOUR_ORG/dev-setup-template .tmp-ai-setup && \
  cp -r .tmp-ai-setup/.claude/skills .claude/skills && \
  cp -r .tmp-ai-setup/.claude/agents .claude/agents && \
  rm -rf .tmp-ai-setup

# Avvia Claude Code ed esegui il setup
claude
# poi digita: /project:setup
```

L'agente analizza il progetto e opera in tre modalita':
- **GREENFIELD** — progetto nuovo: setup completo con quality tools (husky, commitlint, prettier, eslint), profilo stack, MCP, semantic-release
- **EXISTING** — progetto con codice esistente: innesta solo il workflow AI (CONSTITUTION, AGENTS.md, CLAUDE.md, skills, MCP) senza toccare il tooling
- **UPDATE** — setup gia' presente: aggiorna solo i file necessari alla nuova versione

## Passo 4 — Verificare la configurazione

```bash
# Verifica Claude Code
claude --version

# Verifica MCP (dovrebbero apparire 3: clickup, figma, context7)
claude mcp list

# Verifica git hooks (solo per progetti greenfield)
cat .husky/pre-commit
```

## Passo 5 — Primo avvio

```bash
claude
```

Al primo avvio Claude Code legge automaticamente `CLAUDE.md` (che importa `AGENTS.md`) e `CONSTITUTION.md`.
Puoi subito usare i comandi slash disponibili per il tuo stack.

## Comandi slash disponibili (dopo il setup)

| Comando | Descrizione |
|---|---|
| `/project:start-task` | Prende un task da ClickUp e avvia il flusso di sviluppo (TDD o BDD) |
| `/project:tdd` | Ciclo Red-Green-Refactor per codice backend |
| `/project:bdd` | Ciclo Given/When/Then per codice frontend |
| `/project:review` | Code review del branch corrente con verifica CONSTITUTION |
| `/project:sync-task` | Sincronizza lo stato del task con ClickUp |

## Release automatiche con semantic-release

Per i progetti **greenfield**, il setup agent configura automaticamente **semantic-release**
con GitHub Actions. Ad ogni push su `main`, la CI analizza i commit (Conventional Commits) e:

- Calcola la nuova versione (major/minor/patch)
- Genera `CHANGELOG.md`
- Aggiorna la versione nel `package.json`
- Crea tag e GitHub Release

Non serve fare nulla di manuale: basta seguire le convenzioni di commit della Costituzione.

| Tipo di commit | Effetto sulla versione |
|---|---|
| `feat(...)` | MINOR (1.0.0 -> 1.1.0) |
| `fix(...)`, `perf(...)`, `refactor(...)` | PATCH (1.0.0 -> 1.0.1) |
| Commit con `BREAKING CHANGE` nel footer | MAJOR (1.0.0 -> 2.0.0) |

> **Nota**: per progetti **existing**, semantic-release non viene configurato automaticamente.
> Se lo desideri, chiedi al setup agent di aggiungerlo.

## FAQ

**Posso usare Codex invece di Claude Code?**
Sì. La `CONSTITUTION.md` e i profili stack si applicano a qualsiasi agente.
Per Codex, la configurazione MCP è diversa — chiedi al maintainer del meta-repo.

**Come aggiorno il setup quando esce una nuova versione?**
Il maintainer crea un task ClickUp quando c'è una nuova release.
Segui le istruzioni nel task — di solito si tratta di rieseguire `/project:setup` che rileva e aggiorna automaticamente.

**Posso modificare la Costituzione per il mio progetto?**
No — la `CONSTITUTION.md` e' gestita centralmente nel template del meta-repo e distribuita a tutti i progetti.
Se hai una proposta di modifica, aprila come task ClickUp o parla con il maintainer.

**Qualcosa non funziona nel setup — a chi mi rivolgo?**
Apri un task ClickUp nella lista "AI Setup" con:
- Errore esatto (copia il testo)
- Sistema operativo e versione Node.js
- Output di `claude mcp list`
