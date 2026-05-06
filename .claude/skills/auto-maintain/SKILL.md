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
- Schedulata: launchd `com.devmy.ai-base-setup.auto-maintain` alle 04:00, via
  `scripts/auto-maintain-runner.sh` in un sandbox git worktree (`~/Works/.automaint/ai-base-setup`).
  Log: `logs/auto-maintain.log`. Vedi `AGENTS.md` sezione "Pipeline autonoma di manutenzione" per setup.
- On-demand: `/project:auto-maintain` (utile per test o catch-up)

## Principi operativi
- **Nessuna interazione utente**: niente `AskUserQuestion`, niente attese.
- **Una PR per esecuzione**: un solo task processato per ciclo, una sola PR aperta.
- **Bail-out conservativo**: in caso di dubbio o errore, ferma e marca il task come `BLOCKED`. Mai PR rumorose.
- **Lingua**: codice e commit in inglese (Conventional Commits), descrizione PR e commenti ClickUp in italiano.
- **Nessuna dipendenza da CLI esterne**: tutte le operazioni GitHub e ClickUp usano API REST via `curl`. Non serve `gh` installato né MCP ClickUp configurato.

## Prerequisiti
- `.env.local` con `CLICKUP_MAINTENANCE_LIST_ID`, `CLICKUP_API_TOKEN` e `GH_TOKEN` valorizzati
- `git` configurato con accesso in lettura/scrittura al repo
- `curl` e `jq` disponibili nel PATH
- Status `BLOCKED` disponibile nella lista ClickUp di manutenzione
- Branch corrente pulito; lavoro sempre su un branch nuovo creato dalla skill

## Procedura

### Step 0 — Preflight
1. Carica le variabili da `.env.local`:
   ```bash
   set -a && source .env.local && set +a
   ```
2. Verifica `CLICKUP_MAINTENANCE_LIST_ID`: se vuota o assente, stampa "Nessuna lista di manutenzione configurata, esco." ed esci con successo (no-op).
3. Verifica `git status --porcelain` pulito. Se sporco: esci con "Working tree non pulito, abort."
4. Verifica `GH_TOKEN`: se assente o vuoto, esci con "GH_TOKEN non configurato in .env.local."
5. Verifica `CLICKUP_API_TOKEN`: se assente o vuoto, esci con "CLICKUP_API_TOKEN non configurato in .env.local."
6. Verifica token GitHub:
   ```bash
   curl -s -H "Authorization: token $GH_TOKEN" https://api.github.com/user | jq -e '.login' > /dev/null
   ```
   Se il comando fallisce (HTTP 401 o campo `.login` assente): esci con "GH_TOKEN non valido o scaduto."
7. Verifica token ClickUp:
   ```bash
   curl -s -H "Authorization: $CLICKUP_API_TOKEN" https://api.clickup.com/api/v2/user | jq -e '.user.id' > /dev/null
   ```
   Se fallisce: esci con "CLICKUP_API_TOKEN non valido o scaduto."

### Step 1 — Selezione task
1. Recupera i task in stato `SPRINT` dalla lista:
   ```bash
   TASKS_RESPONSE=$(curl -s \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     "https://api.clickup.com/api/v2/list/$CLICKUP_MAINTENANCE_LIST_ID/task?statuses[]=SPRINT&order_by=priority&reverse=false")
   ```
2. Estrai il task a priorità più alta (valore numerico minore: 1=urgent, 2=high, 3=normal, 4=low):
   ```bash
   TASK=$(echo "$TASKS_RESPONSE" | jq '[.tasks[]] | sort_by(.priority.priority // 4) | first')
   ```
3. Se `TASK` è `null` o la lista è vuota: stampa "Nessun task in SPRINT, esco." ed esci con successo.
4. Estrai i campi necessari:
   ```bash
   TASK_ID=$(echo "$TASK" | jq -r .id)
   CUSTOM_ID=$(echo "$TASK" | jq -r .custom_id)
   TASK_NAME=$(echo "$TASK" | jq -r .name)
   TASK_DESC=$(echo "$TASK" | jq -r .description)
   TASK_PRIORITY=$(echo "$TASK" | jq -r .priority.priority)
   TASK_URL=$(echo "$TASK" | jq -r .url)
   ```

### Step 2 — Lock task (SPRINT → IN PROGRESS)
1. Aggiorna lo status:
   ```bash
   curl -s -X PUT \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"status": "IN PROGRESS"}' \
     "https://api.clickup.com/api/v2/task/$TASK_ID"
   ```
2. Aggiungi commento:
   ```bash
   curl -s -X POST \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"comment_text": "🤖 Avvio elaborazione automatica della pipeline auto-maintain."}' \
     "https://api.clickup.com/api/v2/task/$TASK_ID/comment"
   ```
3. Se la chiamata di update restituisce un errore HTTP: esci con `STATUS: error` (no bail-out con tag, il task è ancora in SPRINT).

### Step 3 — Branch
1. `git checkout main && git pull --ff-only`
2. Calcola `slug` dal `name` del task: lowercase, kebab-case, max 50 caratteri, solo `[a-z0-9-]`.
3. `git checkout -b chore/<custom_id>-<slug>` (es. `chore/AI-42-add-mcp-helper-skill`)

### Step 4 — Classifica intent del task
Analizza `TASK_DESC` per dedurre il tipo di modifica. Tipi supportati:

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
1. Applica le modifiche guidate da `TASK_DESC` usando Edit/Write.
2. Per ogni file modificato/creato segui le convenzioni del meta-repo:
   - Lingua: codice in inglese, commenti in italiano, .md in italiano
   - Frontmatter skill: `name`, `description`, `user-invocable` quando appropriato
   - Frontmatter agent: `name`, `description`, `tools`, `model`, `permissionMode`
   - Niente segreti, niente token, niente API key in chiaro
3. Se il task richiede aggiornamenti coerenti in più file (es. nuovo agent shared → riferimento nel manifest): includili nello stesso commit logico.
4. Se durante l'implementazione emergono ambiguità non risolvibili da `TASK_DESC`: **bail-out**.

### Step 6 — Validate
1. Esegui `/project:validate`.
2. Se la validazione fallisce: **bail-out** con dettagli.
3. (Opzionale) Se sono stati toccati script `.sh`, esegui `bash -n <file>` come syntax check.

### Step 7 — Commit
1. Stage solo i file effettivamente modificati: `git add <path1> <path2> ...` (mai `git add -A`).
2. Messaggio Conventional Commits in inglese:
   ```
   <type>(<scope>): <imperative description>

   Refs: <custom_id>
   ```

### Step 8 — Push + PR
1. Ricava il path `org/repo` dal remote:
   ```bash
   REPO_PATH=$(git remote get-url origin | sed 's/.*github\.com[:/]\(.*\)\.git$/\1/')
   ```
2. Push via HTTPS con token (funziona indipendentemente dal protocollo configurato sul remote):
   ```bash
   git push "https://$GH_TOKEN@github.com/$REPO_PATH.git" "HEAD:refs/heads/$BRANCH"
   ```
3. Costruisci il JSON della PR con `jq` (evita problemi di escaping con stringhe multiriga):
   ```bash
   PR_JSON=$(jq -n \
     --arg title "$PR_TITLE" \
     --arg body "$PR_BODY" \
     --arg head "$BRANCH" \
     '{title: $title, body: $body, head: $head, base: "main"}')
   ```
   Formato del titolo (inglese, Conventional Commits):
   ```
   <type>(<scope>): <description> [<custom_id>]
   ```
   Formato del body (italiano), struttura fissa:
   ```markdown
   ## 🤖 PR generata automaticamente

   **Task ClickUp**: [<custom_id>](<task_url>)
   **Tipo modifica**: <tipo dedotto allo Step 4>
   **Priorità task**: <priority>

   ### Cosa cambia
   <bullet list di cosa è stato modificato concretamente>

   ### Perché
   <motivazione presa da TASK_DESC, parafrasata in modo conciso>

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
4. Crea la PR:
   ```bash
   PR_RESPONSE=$(curl -s -X POST \
     -H "Authorization: token $GH_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$PR_JSON" \
     "https://api.github.com/repos/$REPO_PATH/pulls")
   PR_URL=$(echo "$PR_RESPONSE" | jq -r .html_url)
   PR_NUMBER=$(echo "$PR_RESPONSE" | jq -r .number)
   ```
   Se `PR_URL` è `null`: **bail-out** con il body della risposta come dettaglio.
5. Aggiungi label (una tra `skill`, `profile`, `constitution`, `template`, `release`):
   ```bash
   curl -s -X POST \
     -H "Authorization: token $GH_TOKEN" \
     -H "Content-Type: application/json" \
     -d "{\"labels\": [\"$LABEL\"]}" \
     "https://api.github.com/repos/$REPO_PATH/issues/$PR_NUMBER/labels"
   ```

### Step 9 — Move task (IN PROGRESS → CODE REVIEW)
1. Aggiorna lo status:
   ```bash
   curl -s -X PUT \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"status": "CODE REVIEW"}' \
     "https://api.clickup.com/api/v2/task/$TASK_ID"
   ```
2. Aggiungi commento con link PR:
   ```bash
   COMMENT_JSON=$(jq -n --arg text "🤖 PR aperta: $PR_URL" '{comment_text: $text}')
   curl -s -X POST \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$COMMENT_JSON" \
     "https://api.clickup.com/api/v2/task/$TASK_ID/comment"
   ```
3. Stampa riepilogo finale: `custom_id`, branch, `pr_url`.

## Bail-out

Si attiva quando uno step fallisce o quando l'agente non può proseguire con sufficiente confidenza.

Procedura:

1. **Non** eliminare il branch locale (utile per debug umano), se è già stato creato.
2. Sposta il task in stato `BLOCKED`:
   ```bash
   curl -s -X PUT \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"status": "BLOCKED"}' \
     "https://api.clickup.com/api/v2/task/$TASK_ID"
   ```
3. Aggiungi commento con dettagli del blocco:
   ```bash
   BAIL_COMMENT=$(jq -n \
     --arg text "⛔ Pipeline auto-maintain bloccata.\n\n**Step fallito**: <numero e nome>\n**Motivo**: <descrizione>\n**Branch locale**: <branch o 'non creato'>\n\nAzioni suggerite:\n- <suggerimento 1>\n- <suggerimento 2>" \
     '{comment_text: $text}')
   curl -s -X POST \
     -H "Authorization: $CLICKUP_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$BAIL_COMMENT" \
     "https://api.clickup.com/api/v2/task/$TASK_ID/comment"
   ```
4. Esci con errore riportando `task_id`, `custom_id`, branch (se creato), motivo.

Recovery (lato umano): una volta risolto il blocco, rimetti il task in `SPRINT`. La pipeline lo ripescherà al prossimo ciclo.

## Convenzioni di sicurezza
- Non committare mai `.env.local` o file con segreti
- Non eseguire mai `git push --force` o `--no-verify`
- Non operare mai direttamente su `main`
- Non chiudere o cancellare task ClickUp: solo update di status + commenti
- Non aggiungere/rimuovere reviewer GitHub automaticamente (delega all'umano)
- Non loggare mai il valore di `GH_TOKEN` o `CLICKUP_API_TOKEN` nell'output
