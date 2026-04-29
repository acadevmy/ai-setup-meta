---
name: auto-maintain
description: Pipeline autonoma di manutenzione del meta-repo. Pesca un task ClickUp dalla lista dedicata, implementa le modifiche e apre una PR.
user-invocable: true
disable-model-invocation: false
permissionMode: dontAsk
---

# /project:auto-maintain

Esegue un ciclo completo di manutenzione del meta-repo `ai-base-setup` in modo
autonomo, partendo da un task ClickUp e arrivando a una Pull Request pronta
per la review umana.

## Quando viene invocata
- Schedulata: routine cron `0 4 * * *` (vedi `AGENTS.md` sezione "Pipeline autonoma di manutenzione")
- On-demand: `/project:auto-maintain` (utile per test o catch-up)

## Principi operativi
- **Nessuna interazione utente**: niente `AskUserQuestion`, niente attese.
- **Una PR per esecuzione**: un solo task processato per ciclo, una sola PR aperta.
- **Bail-out conservativo**: in caso di dubbio o errore, ferma e marca il task come `auto-blocked`. Mai PR rumorose.
- **Lingua**: codice e commit in inglese (Conventional Commits), descrizione PR e commenti ClickUp in italiano.

## Prerequisiti
- `.env.local` con `CLICKUP_MAINTENANCE_LIST_ID` valorizzato
- MCP `clickup` configurato (`claude mcp list` deve mostrarlo)
- `gh` autenticato (`gh auth status` ok)
- Status `BLOCKED` disponibile nella lista ClickUp di manutenzione (usato dal bail-out)
- Branch corrente pulito; lavoro sempre su un branch nuovo creato dalla skill

## Procedura

### Step 0 — Preflight
1. Carica `CLICKUP_MAINTENANCE_LIST_ID` da `.env.local` con:
   ```bash
   set -a && source .env.local && set +a
   ```
2. Se la variabile è vuota o assente: stampa "Nessuna lista di manutenzione configurata, esco." ed esci con successo (no-op).
3. Verifica `git status --porcelain` pulito. Se sporco: esci con messaggio "Working tree non pulito, abort."
4. Verifica `gh auth status`. Se ko: esci con errore "gh non autenticato."

### Step 1 — Selezione task
1. Invoca subagent `clickup`:
   ```
   INTENT: next-task
   PARAMS:
     list_id: $CLICKUP_MAINTENANCE_LIST_ID
   ```
2. Se `STATUS: error` (lista vuota): stampa "Nessun task in SPRINT, esco." ed esci con successo.
3. Se `STATUS: success`: estrai `task_id`, `custom_id`, `name`, `description`, `priority`, `url` dal blocco DATA.

### Step 2 — Lock task (SPRINT → IN PROGRESS)
1. Invoca subagent `clickup`:
   ```
   INTENT: update
   PARAMS:
     task_id: <task_id>
     status: IN PROGRESS
     comment: "🤖 Avvio elaborazione automatica della pipeline auto-maintain."
   ```
2. Se errore: esci con `STATUS: error` (no bail-out con tag, perché il task è ancora in SPRINT).

### Step 3 — Branch
1. `git checkout main && git pull --ff-only`
2. Calcola `slug` dal `name` del task: lowercase, kebab-case, max 50 caratteri, solo `[a-z0-9-]`.
3. `git checkout -b chore/<custom_id>-<slug>` (es. `chore/AI-42-add-mcp-helper-skill`)

### Step 4 — Classifica intent del task
Analizza il `description` del task per dedurre il tipo di modifica. Tipi supportati:

| Tipo | Indicatori | File target tipici |
|---|---|---|
| `skill-update` | "skill", "comando /project:" | `templates/<dom>/.claude/skills/`, `shared/skills/` |
| `mcp-update` | "MCP", "server context", "claude mcp add" | `templates/<dom>/.mcp.json`, doc relativa |
| `profile-update` | "profilo", "stack", "Next.js/Angular/Flutter" | `templates/<dom>/profiles/` |
| `agent-update` | "agent", "subagent" | `templates/<dom>/.claude/agents/`, `shared/agents/` |
| `constitution-update` | "constitution", "regola", "vincolo" | `CONSTITUTION.md` (root) |
| `manifest-update` | "manifest", "shared_agents", "copy_constitution" | `templates/<dom>/manifest.json` |
| `docs-update` | "AGENTS.md", "README", "documentazione" | `AGENTS.md`, `README.md`, `docs/` |

Se nessun tipo è deducibile con confidenza ragionevole: **bail-out** (vedi sezione "Bail-out").

### Step 5 — Apply changes
1. Applica le modifiche guidate dalla `description` del task usando Edit/Write.
2. Per ogni file modificato/creato segui le convenzioni del meta-repo:
   - Lingua: codice in inglese, commenti in italiano, .md in italiano
   - Frontmatter skill: `name`, `description`, `user-invocable` quando appropriato
   - Frontmatter agent: `name`, `description`, `tools`, `model`, `permissionMode`
   - Niente segreti, niente token, niente API key in chiaro
3. Se il task richiede aggiornamenti coerenti in più file (es. nuovo agent shared → riferimento nel manifest del template): includili nello stesso commit logico.
4. Se durante l'implementazione emergono ambiguità non risolvibili dal task description: **bail-out**.

### Step 6 — Validate
1. Esegui `/project:validate` (se la skill è disponibile come comando, altrimenti invoca via Bash).
2. Se la validazione fallisce: **bail-out** con dettagli.
3. (Opzionale) Se sono stati toccati script `.sh`, esegui `bash -n <file>` come syntax check.

### Step 7 — Commit
1. Stage solo i file effettivamente modificati: `git add <path1> <path2> ...` (mai `git add -A`).
2. Messaggio Conventional Commits in inglese, una commit logica:
   ```
   <type>(<scope>): <imperative description>

   Refs: <custom_id>
   ```
   Esempi:
   - `feat(skills): add mcp-helper skill for context7 onboarding`
   - `chore(profiles): bump nx workspace to v20.5`
   - `fix(constitution): clarify rule 17 on atomic commits`

### Step 8 — Push + PR
1. `git push -u origin <branch>`
2. `gh pr create` con:
   - **Title** (inglese, Conventional Commits, custom_id in coda):
     ```
     <type>(<scope>): <description> [<custom_id>]
     ```
   - **Body** (italiano), heredoc con questa struttura **fissa**:
     ```markdown
     ## 🤖 PR generata automaticamente

     **Task ClickUp**: [<custom_id>](<task_url>)
     **Tipo modifica**: <tipo dedotto allo Step 4>
     **Priorità task**: <priority>

     ### Cosa cambia
     <bullet list di cosa è stato modificato concretamente>

     ### Perché
     <motivazione presa dal task description, parafrasata in modo conciso>

     ### Come testare
     <istruzioni di verifica concrete, es.:
      - eseguire `/project:validate`
      - ispezionare i file <path>
      - rigenerare un template con `/project:generate-setup <dominio>`>

     ### File toccati
     - <path1>
     - <path2>

     ---
     ⚠️ Questa PR è stata generata da un agente autonomo. Verifica con attenzione prima del merge.
     ```
   - **Label**: una tra `skill`, `profile`, `constitution`, `template`, `release` in base al tipo dello Step 4.
3. Cattura `pr_url` dall'output di `gh pr create`.

### Step 9 — Move task (IN PROGRESS → CODE REVIEW)
1. Invoca subagent `clickup`:
   ```
   INTENT: update
   PARAMS:
     task_id: <task_id>
     status: CODE REVIEW
     comment: "🤖 PR aperta: <pr_url>"
   ```
2. Stampa riepilogo finale all'operatore (custom_id, branch, pr_url).

## Bail-out

Si attiva quando uno step fallisce o quando l'agente non è in condizione di proseguire con sufficiente confidenza. Può accadere da qualsiasi stato in cui il task si trovi (SPRINT se fallisce lo Step 2, IN PROGRESS se fallisce uno step successivo).

Procedura di bail-out:

1. **Non** eliminare il branch locale (utile per debug umano), se è già stato creato.
2. Sposta il task in stato `BLOCKED` tramite subagent `clickup`:
   ```
   INTENT: update
   PARAMS:
     task_id: <task_id>
     status: BLOCKED
     comment: |
       ⛔ Pipeline auto-maintain bloccata.

       **Step fallito**: <numero e nome step>
       **Motivo**: <descrizione concreta>
       **Branch locale**: <branch_name se creato, altrimenti "non creato">

       Azioni suggerite:
       - <suggerimento 1>
       - <suggerimento 2>
   ```
3. Esci con codice di errore non zero e messaggio finale che riporta `task_id`, `custom_id`, branch (se creato), motivo.

Recovery (lato umano): una volta risolto il blocco, l'operatore rimette il task in `SPRINT` (o `IN PROGRESS` se vuole riprendere manualmente). La pipeline lo ripeschera' al prossimo ciclo.

## Convenzioni di sicurezza
- Non committare mai `.env.local` o file con segreti
- Non eseguire mai `git push --force` o `--no-verify`
- Non operare mai direttamente su `main`
- Non chiudere o cancellare task ClickUp: solo update di status + commenti
- Non aggiungere/rimuovere reviewer GitHub automaticamente (delega all'umano)
