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
- **Schedulata (primaria)**: Claude Code Routine `auto-maintain ai-base-setup` su `claude.ai/code/routines`,
  con schedule giornaliero. Gira su infrastruttura cloud Anthropic — nessun launchd, nessuna dipendenza TTY.
  Vedi `AGENTS.md` sezione "Pipeline autonoma di manutenzione" per setup.
- **On-demand**: `/project:auto-maintain` (utile per test o catch-up locali)

## Principi operativi
- **Nessuna interazione utente**: niente `AskUserQuestion`, niente attese.
- **Una PR per esecuzione**: un solo task processato per ciclo, una sola PR aperta.
- **Bail-out conservativo**: in caso di dubbio o errore, ferma e marca il task come `BLOCKED`. Mai PR rumorose.
- **Lingua**: codice e commit in inglese (Conventional Commits), descrizione PR e commenti ClickUp in italiano.
- **ClickUp via MCP**: tutte le operazioni ClickUp usano i tool `mcp__clickup__*` già autenticati. Nessun token da gestire.
- **GitHub via curl + GH_TOKEN**: push e creazione PR usano l'API GitHub REST con il token da `.env.local`.
- **Resumable**: ogni run scrive `.automaint-state.json` dopo ogni step. In caso di interruzione (timeout, errore transitorio), il run successivo riprende dal passo corretto senza perdere il lavoro già fatto.

## File di stato (`.automaint-state.json`)

Traccia il progresso della pipeline tra run diversi. Schema:

```json
{
  "next_step": 5,
  "task_id": "abc123",
  "custom_id": "DE-15244",
  "branch": "chore/DE-15244-slug",
  "task_name": "Titolo task",
  "task_desc": "Descrizione completa...",
  "task_url": "https://app.clickup.com/t/abc123",
  "intent_type": "skill-update",
  "started_at": "2026-05-08T04:11:45+02:00"
}
```

- `next_step`: il prossimo step da eseguire (aggiornato dopo ogni step completato)
- Su completamento: elimina il file
- Su bail-out: aggiungi `"status": "blocked"` — il runner non ritenta

## Prerequisiti
- `CLICKUP_MAINTENANCE_LIST_ID` disponibile come variabile d'ambiente (via `.env.local` in locale, via Routine environment nel cloud)
- `GH_TOKEN` disponibile come variabile d'ambiente (stessa modalità)
- Connector ClickUp autenticato: OAuth via claude.ai nel cloud, MCP locale (`claude mcp list`) in locale
- `git` configurato con accesso in lettura/scrittura al repo
- `curl` e `jq` disponibili nel PATH
- Status `BLOCKED` disponibile nella lista ClickUp di manutenzione
- Branch corrente pulito; lavoro sempre su un branch nuovo creato dalla skill

## Procedura

### Step 0 — Resume detection + Preflight

**Prima di tutto**, controlla se esiste un file di stato da un run precedente:

```bash
STATE_FILE=".automaint-state.json"
if [[ -f "$STATE_FILE" ]]; then
  NEXT_STEP=$(jq -r '.next_step' "$STATE_FILE")
  TASK_ID=$(jq -r '.task_id // ""' "$STATE_FILE")
  CUSTOM_ID=$(jq -r '.custom_id // ""' "$STATE_FILE")
  BRANCH=$(jq -r '.branch // ""' "$STATE_FILE")
  TASK_NAME=$(jq -r '.task_name // ""' "$STATE_FILE")
  TASK_DESC=$(jq -r '.task_desc // ""' "$STATE_FILE")
  TASK_URL=$(jq -r '.task_url // ""' "$STATE_FILE")
  INTENT_TYPE=$(jq -r '.intent_type // ""' "$STATE_FILE")
  echo "[RESUME] Riprendendo da Step $NEXT_STEP — task $CUSTOM_ID branch $BRANCH"
else
  NEXT_STEP=1
  echo "[START] Avvio pipeline da Step 1"
fi
```

Se `NEXT_STEP > 1`: salta tutti gli step già completati (branch esiste, task è già IN PROGRESS, ecc.) e vai direttamente allo step indicato.

**Preflight** (esegui sempre, indipendentemente dal resume):

1. Carica le variabili da `.env.local` se il file esiste (in locale); nel cloud le variabili arrivano dall'environment della Routine:
   ```bash
   [[ -f .env.local ]] && { set -a; source .env.local; set +a; }
   ```
2. Verifica `CLICKUP_MAINTENANCE_LIST_ID`: se vuota o assente, stampa "`CLICKUP_MAINTENANCE_LIST_ID` non è configurato." ed esci con successo (no-op).
3. **Solo se `NEXT_STEP == 1`**: verifica `git status --porcelain` pulito. Se sporco: esci con "Working tree non pulito, abort." — In caso di resume (`NEXT_STEP > 1`) il working tree può essere sporco per le modifiche del run precedente: è atteso, prosegui.
4. Verifica `GH_TOKEN`: se assente o vuoto, esci con "GH_TOKEN non configurato."
5. Verifica token GitHub:
   ```bash
   curl -s -H "Authorization: token $GH_TOKEN" https://api.github.com/user | jq -e '.login' > /dev/null
   ```
   Se il comando fallisce (HTTP 401 o campo `.login` assente): esci con "GH_TOKEN non valido o scaduto."

### Step 1 — Selezione task
*(Salta se `NEXT_STEP > 1` — le variabili sono già state ripristinate dallo state file)*

Stampa `[STEP 1 START] Selezione task`.

1. Recupera i task in stato `SPRINT` dalla lista usando il tool MCP:
   ```
   mcp__clickup__clickup_filter_tasks(list_id: CLICKUP_MAINTENANCE_LIST_ID, statuses: ["SPRINT"])
   ```
2. Ordina i task per priorità (valore numerico minore = priorità più alta: 1=urgent, 2=high, 3=normal, 4=low). Seleziona il primo.
3. Se la lista è vuota: stampa "Nessun task in SPRINT, esco." ed esci con successo.
4. Estrai i campi necessari dal task selezionato:
   - `TASK_ID` — id interno ClickUp
   - `CUSTOM_ID` — es. `AI-42`
   - `TASK_NAME` — titolo del task
   - `TASK_DESC` — description del task
   - `TASK_PRIORITY` — valore numerico priorità
   - `TASK_URL` — URL del task su ClickUp
5. Scrivi lo state file:
   ```bash
   python3 -c "
   import json, sys
   print(json.dumps({'next_step': 2, 'task_id': sys.argv[1], 'custom_id': sys.argv[2],
     'branch': '', 'task_name': sys.argv[3], 'task_desc': sys.argv[4],
     'task_url': sys.argv[5], 'started_at': sys.argv[6]}, indent=2))
   " "$TASK_ID" "$CUSTOM_ID" "$TASK_NAME" "$TASK_DESC" "$TASK_URL" "$(date -Iseconds)" > .automaint-state.json
   ```
6. Stampa `[STEP 1 END] task=$CUSTOM_ID`.

### Step 2 — Lock task (SPRINT → IN PROGRESS)
*(Salta se `NEXT_STEP > 2`)*

Stampa `[STEP 2 START] Lock task $CUSTOM_ID`.

1. Aggiorna lo status tramite MCP:
   ```
   mcp__clickup__clickup_update_task(task_id: TASK_ID, status: "IN PROGRESS")
   ```
2. Aggiungi commento tramite MCP:
   ```
   mcp__clickup__clickup_create_task_comment(task_id: TASK_ID, comment_text: "🤖 Avvio elaborazione automatica della pipeline auto-maintain.")
   ```
3. Se la chiamata MCP restituisce un errore: esci con `STATUS: error` (no bail-out con tag, il task è ancora in SPRINT).
4. Aggiorna `next_step` a 3 nello state file:
   ```bash
   python3 -c "import json; s=json.load(open('.automaint-state.json')); s['next_step']=3; print(json.dumps(s,indent=2))" > .tmp && mv .tmp .automaint-state.json
   ```
5. Stampa `[STEP 2 END]`.

### Step 3 — Branch
*(Salta se `NEXT_STEP > 3` — il branch esiste già)*

Stampa `[STEP 3 START] Creazione branch`.

1. Assicurati di essere su `main` aggiornato. Nel cloud (Routine) il repo è già clonato sul branch default — esegui `git pull --ff-only origin main` se non sei già all'ultima versione. In locale: `git checkout main && git pull --ff-only origin main`.
2. Calcola `slug` dal `name` del task: lowercase, kebab-case, max 50 caratteri, solo `[a-z0-9-]`.
3. `git checkout -b chore/<custom_id>-<slug>` (es. `chore/AI-42-add-mcp-helper-skill`)
4. Aggiorna `branch` e `next_step` a 4 nello state file:
   ```bash
   python3 -c "import json, sys; s=json.load(open('.automaint-state.json')); s['next_step']=4; s['branch']=sys.argv[1]; print(json.dumps(s,indent=2))" "$BRANCH" > .tmp && mv .tmp .automaint-state.json
   ```
5. Stampa `[STEP 3 END] branch=$BRANCH`.

### Step 4 — Classifica intent del task
*(Salta se `NEXT_STEP > 4` — `INTENT_TYPE` è già nello state file)*

Stampa `[STEP 4 START] Classificazione intent`.

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

Aggiorna `intent_type` e `next_step` a 5 nello state file:
```bash
python3 -c "import json, sys; s=json.load(open('.automaint-state.json')); s['next_step']=5; s['intent_type']=sys.argv[1]; print(json.dumps(s,indent=2))" "$INTENT_TYPE" > .tmp && mv .tmp .automaint-state.json
```

Stampa `[STEP 4 END] intent=$INTENT_TYPE`.

### Step 5 — Apply changes
*(In caso di resume a Step 5: il working tree può contenere modifiche parziali del run precedente — rileggi i file e applica le modifiche in modo idempotente, non duplicare cambiamenti già presenti)*

Stampa `[STEP 5 START] Apply changes`.

1. Applica le modifiche guidate da `TASK_DESC` usando Edit/Write.
2. Per ogni file modificato/creato segui le convenzioni del meta-repo:
   - Lingua: codice in inglese, commenti in italiano, .md in italiano
   - Frontmatter skill: `name`, `description`, `user-invocable` quando appropriato
   - Frontmatter agent: `name`, `description`, `tools`, `model`, `permissionMode`
   - Niente segreti, niente token, niente API key in chiaro
3. Se il task richiede aggiornamenti coerenti in più file (es. nuovo agent shared → riferimento nel manifest): includili nello stesso commit logico.
4. Se durante l'implementazione emergono ambiguità non risolvibili da `TASK_DESC`: **bail-out**.
5. Aggiorna `next_step` a 6 nello state file:
   ```bash
   python3 -c "import json; s=json.load(open('.automaint-state.json')); s['next_step']=6; print(json.dumps(s,indent=2))" > .tmp && mv .tmp .automaint-state.json
   ```
6. Stampa `[STEP 5 END]`.

### Step 6 — Validate
*(Salta se `NEXT_STEP > 6`)*

Stampa `[STEP 6 START] Validazione`.

1. Esegui `/project:validate`.
2. Se la validazione fallisce: **bail-out** con dettagli.
3. (Opzionale) Se sono stati toccati script `.sh`, esegui `bash -n <file>` come syntax check.
4. Aggiorna `next_step` a 7 nello state file:
   ```bash
   python3 -c "import json; s=json.load(open('.automaint-state.json')); s['next_step']=7; print(json.dumps(s,indent=2))" > .tmp && mv .tmp .automaint-state.json
   ```
5. Esegui il comand `sh` `build-plugin.sh`
6. Stampa `[STEP 6 END]`.

### Step 7 — Commit
*(Salta se `NEXT_STEP > 7`)*

Stampa `[STEP 7 START] Commit`.

1. Stage solo i file effettivamente modificati: `git add <path1> <path2> ...` (mai `git add -A`).
2. Messaggio Conventional Commits in inglese:
   ```
   <type>(<scope>): <imperative description>

   Refs: <custom_id>
   ```
3. Aggiorna `next_step` a 8 nello state file:
   ```bash
   python3 -c "import json; s=json.load(open('.automaint-state.json')); s['next_step']=8; print(json.dumps(s,indent=2))" > .tmp && mv .tmp .automaint-state.json
   ```
4. Stampa `[STEP 7 END]`.

### Step 8 — Push + PR
*(Salta se `NEXT_STEP > 8`)*

Stampa `[STEP 8 START] Push + PR`.
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
6. Aggiorna `next_step` a 9 nello state file:
   ```bash
   python3 -c "import json; s=json.load(open('.automaint-state.json')); s['next_step']=9; print(json.dumps(s,indent=2))" > .tmp && mv .tmp .automaint-state.json
   ```
7. Stampa `[STEP 8 END] pr=$PR_URL`.

### Step 9 — Move task (IN PROGRESS → CODE REVIEW)
Stampa `[STEP 9 START] ClickUp update`.

1. Aggiorna lo status tramite MCP:
   ```
   mcp__clickup__clickup_update_task(task_id: TASK_ID, status: "CODE REVIEW")
   ```
2. Aggiungi commento con link PR tramite MCP:
   ```
   mcp__clickup__clickup_create_task_comment(task_id: TASK_ID, comment_text: "🤖 PR aperta: <PR_URL>")
   ```
3. Elimina il file di stato — la pipeline è completata:
   ```bash
   rm -f .automaint-state.json
   ```
4. Stampa riepilogo finale: `custom_id`, branch, `pr_url`.
5. Stampa `[STEP 9 END] DONE`.

## Bail-out

Si attiva quando uno step fallisce o quando l'agente non può proseguire con sufficiente confidenza.

Procedura:

1. **Non** eliminare il branch locale (utile per debug umano), se è già stato creato.
2. Sposta il task in stato `BLOCKED` tramite MCP:
   ```
   mcp__clickup__clickup_update_task(task_id: TASK_ID, status: "BLOCKED")
   ```
3. Aggiungi commento con dettagli del blocco tramite MCP:
   ```
   mcp__clickup__clickup_create_task_comment(task_id: TASK_ID, comment_text: "⛔ Pipeline auto-maintain bloccata.\n\n**Step fallito**: <numero e nome>\n**Motivo**: <descrizione>\n**Branch locale**: <branch o 'non creato'>\n\nAzioni suggerite:\n- <suggerimento 1>\n- <suggerimento 2>")
   ```
4. Marca il file di stato come bloccato (impedisce il retry automatico del runner):
   ```bash
   python3 -c "import json; s=json.load(open('.automaint-state.json')); s['status']='blocked'; print(json.dumps(s,indent=2))" > .tmp && mv .tmp .automaint-state.json
   ```
5. Esci con errore riportando `task_id`, `custom_id`, branch (se creato), motivo.

Recovery (lato umano): una volta risolto il blocco, rimetti il task in `SPRINT`. La pipeline lo ripescherà al prossimo ciclo.

## Convenzioni di sicurezza
- Non committare mai `.env.local` o file con segreti
- Non eseguire mai `git push --force` o `--no-verify`
- Non operare mai direttamente su `main`
- Non chiudere o cancellare task ClickUp: solo update di status + commenti
- Non aggiungere/rimuovere reviewer GitHub automaticamente (delega all'umano)
- Non loggare mai il valore di `GH_TOKEN` nell'output
