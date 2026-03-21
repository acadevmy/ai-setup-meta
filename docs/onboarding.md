# Onboarding sviluppatori — AI-Native Setup

Guida per configurare l'ambiente AI-native sul proprio computer.
Tempo stimato: **30–45 minuti** (prima installazione).

## Prerequisiti

| Strumento | Versione minima | Installazione |
|---|---|---|
| Node.js | 20.x LTS | [nodejs.org](https://nodejs.org) |
| git | 2.40+ | preinstallato su macOS/Linux |
| Claude Code | ultima | `npm install -g @anthropic-ai/claude-code` |
| Account Claude | Piano Pro o Max | [claude.ai](https://claude.ai) |

## Passo 1 — Clonare il template

```bash
# Clona il repo template (non questo meta-repo)
git clone git@github.com:YOUR_ORG/dev-setup-template.git nome-progetto
cd nome-progetto
```

## Passo 2 — Eseguire lo script di init

```bash
bash init.sh
```

Lo script ti chiederà di:
1. Inserire il tuo nome (per personalizzare `AGENT.md`)
2. Selezionare il profilo stack del progetto:
   - `1` Web Frontend (Next.js / Angular / React)
   - `2` Backend (Node.js / NestJS)
   - `3` Mobile (Flutter / React Native)
   - `4` Full Stack (Web + Backend)
3. Inserire le API key necessarie (le trovi su Notion > AI Setup)

## Passo 3 — Verificare la configurazione

```bash
# Verifica Claude Code
claude --version

# Verifica MCP (dovrebbero apparire tutti e 4)
claude mcp list

# Verifica git hooks
cat .husky/pre-commit
```

## Passo 4 — Primo avvio

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

## FAQ

**Posso usare Codex invece di Claude Code?**
Sì. La `CONSTITUTION.md` e i profili stack si applicano a qualsiasi agente.
Per Codex, la configurazione MCP è diversa — chiedi al maintainer del meta-repo.

**Come aggiorno il setup quando esce una nuova versione?**
Il maintainer crea un task ClickUp quando c'è una nuova release.
Segui le istruzioni nel task — di solito si tratta di fare pull e rieseguire `init.sh`.

**Posso modificare la Costituzione per il mio progetto?**
No — la `CONSTITUTION.md` è condivisa e modificabile solo tramite il meta-repo.
Se hai una proposta, aprila come task ClickUp o parla con il maintainer.

**Qualcosa non funziona nel setup — a chi mi rivolgo?**
Apri un task ClickUp nella lista "AI Setup" con:
- Errore esatto (copia il testo)
- Sistema operativo e versione Node.js
- Output di `claude mcp list`
