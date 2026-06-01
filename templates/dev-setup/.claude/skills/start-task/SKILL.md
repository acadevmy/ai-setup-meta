---
name: start-task
description: Esegue l'intero flusso Spec-Driven Development (SDD) end-to-end in modalita' autonoma. Sostituisce ogni checkpoint umano (discovery, approvazione spec/plan, scelta metodologia, OK finale, apertura MR) con agenti AI. Invocare questa skill significa attivare l'auto-mode — non esistono flag.
model: opus
user-invocable: true
disable-model-invocation: true
---

# /project:start-task

Esegue l'intero flusso Spec-Driven Development (SDD) per un task ClickUp in modalita'
**completamente autonoma**: dalla selezione del task all'apertura della MR/PR, senza
alcuna `AskUserQuestion` rivolta all'umano.

**Invocare `start-task` equivale ad attivare l'auto-mode**: non e' un flag, e' il
comportamento intrinseco della skill. La modalita' interattiva resta disponibile via
l'orchestratore `sdd` (che non viene modificato).

**Usage**: `/project:start-task [TASK_ID]`
- Con `TASK_ID` (es. `DE-123`): elabora quel task
- Senza argomenti: prende il prossimo task in `SPRINT` dalla lista `CLICKUP_SETUP_LIST_ID`

## CRITICAL — Comportamento in auto-mode

- **Nessuna `AskUserQuestion` puo' essere invocata**: ogni decisione passa per un agent
  (`sdd-discovery-responder`, `sdd-approver`, `sdd-methodology-picker`) o per una regola
  deterministica documentata
- **Lo Stop hook silenzioso non si applica**: in auto-mode non c'e' attesa umana, quindi
  il pattern "STOP dopo AskUserQuestion" non e' previsto. Se lo Stop hook segnala lavoro
  incompleto, completa effettivamente il lavoro o esegui il bail-out
- **Bound dei loop**: ogni loop ha un limite massimo di iterazioni (vedi tabella sotto).
  Superato il bound senza convergenza → bail-out
- **Skill SDD non modificabili**: questa skill orchestra le skill `sdd-spec`, `sdd-dev`,
  `verify`, `simplify`, `review` ma **non puo' modificarne il comportamento interno**.
  Le skill interattive (`sdd-discovery`, `sdd-plan`) **NON vanno invocate**: i loro output
  vengono prodotti dagli agent dedicati di questa skill

| Loop | Bound massimo |
|---|---|
| Domande di discovery (Q/A tra intervistatore e responder) | 12 |
| Iterazioni di revisione spec (`sdd-approver` su `MODE: spec`) | 3 |
| Iterazioni di revisione plan (`sdd-approver` su `MODE: plan`) | 3 |
| Rientri da `verify` fail | 3 |

## Flusso completo

### 1. Selezione del task

**Se `$ARGUMENTS` contiene un TASK_ID**:
- Lancia l'agent `clickup` con:
  - INTENT: `read`
  - PARAMS: `task_id: <TASK_ID>`
- Se l'agent restituisce STATUS: error → bail-out con motivo

**Se `$ARGUMENTS` e' vuoto**:
- Leggi `CLICKUP_SETUP_LIST_ID` dal file `.env` nella root del progetto
- Se la variabile non e' configurata → bail-out (`Configurare CLICKUP_SETUP_LIST_ID in .env`)
- Lancia l'agent `clickup` con:
  - INTENT: `filter`
  - PARAMS: `list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`
- Se l'agent restituisce STATUS: error → bail-out con motivo
- Se la lista e' vuota → stop pulito ("Nessun task in SPRINT")
- Ordina i risultati per `priority` (1=urgent ... 4=low) e prendi il **primo**
- Lancia l'agent `clickup` con INTENT: `read` per recuperare il contenuto completo del task scelto

Dall'output estrai: `custom_id`, `name`, `description`, `priority`, `task_id`, `url`.

### 2. Creazione del branch

Determina il tipo dal titolo/descrizione del task:
- Feature → `feat/`
- Bug → `fix/`
- Manutenzione → `chore/`

**Base branch**: usa il default del repository (in ordine: `main`, `master`, `develop` —
prendi il primo che esiste). Nessuna `AskUserQuestion`.

```bash
git checkout <base-branch>
git pull origin <base-branch>
git checkout -b <type>/<customId>-<short-description>
```

Esempio: `feat/DE-123-add-user-auth`.

Se la creazione del branch fallisce → bail-out.

### 3. Update stato task

Lancia l'agent `clickup` con:
- INTENT: `update`
- PARAMS: `task_id: <task_id>, status: IN PROGRESS`

### 4. Discovery autonoma a due agenti

Sostituisce l'intervista interattiva di `sdd-discovery`. **Non invocare `/project:sdd-discovery`**:
quella skill apre `AskUserQuestion` ed e' incompatibile con l'auto-mode.

Esegui un loop tra **due ruoli interni a questa skill**:

**Ruolo A — Intervistatore** (gestito dalla skill, non come agent separato)
- Adotta il framework di `sdd-discovery`: 4 fasi `Core Value` → `Happy Path` → `Edge Cases` → `Constraints`
- Per ogni fase, formula una domanda alla volta con 2-4 opzioni preformulate (closed-first)
- Massimo 10-12 domande complessive (bound del loop)

**Ruolo B — Responder** (delegato all'agent `sdd-discovery-responder`)
- Per ogni domanda, lancia l'agent `sdd-discovery-responder` con:
  - `TASK_CONTEXT`: campi estratti allo Step 1
  - `PHASE`: fase corrente
  - `QUESTION`: domanda formulata dall'intervistatore
  - `OPTIONS`: opzioni preformulate (incluso "Da definire" quando ha senso)
  - `HISTORY`: tutte le Q/A gia' scambiate
- L'agent restituisce un blocco `---DISCOVERY-ANSWER---` con `CHOICE`, `ANSWER`,
  `RATIONALE`, `GRAY_AREA`

**Convergenza**:
- Termina quando tutte e 4 le fasi sono coperte con risposte non ambigue **oppure**
  al raggiungimento del bound (12 Q/A)
- Se al bound restano fasi scoperte → bail-out

**Output**: ricostruisci il Discovery Summary nel formato identico a quello di
`sdd-discovery` (sezioni `Core Value`, `Happy Path`, `Edge Cases and Error Handling`,
`Constraints and Preferences`, `Existing Components to Reuse`, `Gray Areas`) e tienilo
in contesto per lo step successivo.

### 5. Generazione spec

Invoca `/project:sdd-spec` passando: `TASK_CONTEXT` (custom_id, name, description, url,
branch) + Discovery Summary prodotto allo Step 4.

La skill `sdd-spec` non e' interattiva e produce `.specs/<customId>-<slug>.md` con
status `draft`.

### 6. Approvazione spec da agent (loop bounded)

Sostituisce `sdd-plan` (interattivo, vietato in auto-mode).

Inizializza `ITERATION = 1`, `MAX_ITERATIONS = 3`.

Loop:
1. Lancia l'agent `sdd-approver` con:
   - `SPEC_PATH`: path della spec generata
   - `MODE`: `spec`
   - `DISCOVERY_SUMMARY`: il summary prodotto allo Step 4
   - `ITERATION`, `MAX_ITERATIONS`
2. Se `STATUS: approved` → esci dal loop, aggiorna il frontmatter della spec:
   - `Status: draft` → `Status: approved`
   - `Approved: <YYYY-MM-DD>`
3. Se `STATUS: changes-requested`:
   - Applica i `CHANGES_REQUESTED` direttamente al file della spec (Edit/Write)
   - `ITERATION += 1`
   - Se `ITERATION > MAX_ITERATIONS` → bail-out con elenco delle violazioni residue
   - Altrimenti torna al punto 1
4. Se `STATUS: error` → bail-out

### 7. Approvazione plan da agent (loop bounded)

Stesso meccanismo dello Step 6 ma con `MODE: plan`. Bound: 3 iterazioni.

Al termine, la spec resta in stato `approved`.

### 8. Scelta della metodologia da agent

Lancia l'agent `sdd-methodology-picker` con:
- `SPEC_PATH`: path della spec approvata
- `TASK_CONTEXT`: campi del task

L'agent restituisce `METHODOLOGY` (`tdd` | `bdd` | `none`) e `RATIONALE`. Traccia la
scelta nel log della skill (non modificare la spec — la metodologia si passa a `sdd-dev`).

### 9. Sviluppo

Invoca `/project:sdd-dev` passando:
- `SPEC_REF`: path della spec approvata
- `METHODOLOGY`: la metodologia scelta dall'agent allo Step 8

`sdd-dev` esegue il piano. Non richiede input umano in auto-mode (la skill ha gia' la
metodologia esplicita e la spec approvata).

### 10. Quality gate automatici

Eseguili nell'ordine:

1. **simplify** — invoca la skill `simplify` (se presente). In auto-mode, accetta
   automaticamente le modifiche proposte e committale come
   `refactor(<scope>): simplify implementation`
2. **verify** — invoca `/project:verify`
   - Se `STATUS: pass` → procedi
   - Se `STATUS: pass-with-warnings` → procedi loggando i warning
   - Se `STATUS: fail` → rientra a Step 9 (sviluppo) con il dettaglio dei requirement
     mancanti. Bound: 3 rientri totali. Superato il bound → bail-out
3. **review** — invoca `/project:review`
   - Se `STATUS: pass` o `pass-with-warnings` → procedi
   - Se `STATUS: fail` con violazioni auto-risolvibili (es. `any` sostituibili con un
     tipo concreto evidente dalla spec) → applicale e re-invoca `review` (max 1 rientro)
   - Se `STATUS: fail` con violazioni non auto-risolvibili → bail-out

### 11. Push + apertura MR/PR

Push del branch:
```bash
git push -u origin <branch-name>
```

Invoca la skill VCS-ops attiva (`github-ops` per remote GitHub, `gitlab-ops` per remote
GitLab — self-identify). Titolo e body:

- **Titolo**: Conventional Commits con customId
  - es. `feat(auth): add refresh token rotation [DE-123]`
- **Body**: include sezioni **What / Why / How to test** + link al task ClickUp + link
  alla spec. Su GitLab segue il template `.gitlab/merge_request_templates/Default.md`
  quando presente (vedi `gitlab-ops`)

Nessuna `AskUserQuestion` prima dell'apertura: l'autorizzazione e' implicita
nell'invocazione di `start-task`.

### 12. Chiusura

1. Lancia l'agent `clickup` con:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: CODE REVIEW`
   - Fallback: se `CODE REVIEW` non esiste nella lista, usa `IN REVIEW`
2. Aggiorna il frontmatter della spec: `Status: approved` → `Status: implemented`

## Bail-out

Si attiva quando uno step fallisce o un loop non converge entro il bound.

Procedura:
1. **Non** eliminare il branch locale (utile per debug umano)
2. Lancia l'agent `clickup` con:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: BLOCKED`
3. Lancia l'agent `clickup` con:
   - INTENT: `comment`
   - PARAMS: `task_id: <task_id>, text: "⛔ Pipeline start-task (auto-mode) bloccata.\n\n**Step fallito**: <numero>\n**Motivo**: <descrizione>\n**Branch locale**: <branch>\n\nAzioni suggerite:\n- <suggerimento>"`
4. Esci con errore riportando `task_id`, `custom_id`, branch, motivo

Recovery (lato umano): risolto il blocco, riporta il task in `SPRINT`. Una nuova
invocazione di `start-task` ripeschera' il task.

## Output atteso

- Branch creato con customId nel nome
- Spec in `.specs/` con status `implemented`
- Codice implementato seguendo la spec approvata
- Codice ottimizzato (simplify), verificato vs spec (verify), CONSTITUTION-compliant (review)
- `REGISTRY.md` aggiornato con le nuove entry
- Task ClickUp: `SPRINT` → `IN PROGRESS` → `CODE REVIEW`
- MR/PR aperta (GitHub o GitLab a seconda del provider) con riferimenti a task e spec
- Nessuna `AskUserQuestion` invocata durante l'intero flusso

## Vincoli — riassunto

- **NON modificare** le skill SDD (`sdd`, `sdd-discovery`, `sdd-spec`, `sdd-plan`,
  `sdd-dev`, `verify`, `simplify`, `review`, `tdd`, `bdd`)
- **NON invocare** in auto-mode le skill interattive (`sdd-discovery`, `sdd-plan`):
  i loro output sono prodotti rispettivamente dal loop discovery dello Step 4 e
  dall'agent `sdd-approver`
- L'auto-mode e' il comportamento di default e unico di `start-task`. La modalita'
  interattiva e' coperta da `/project:sdd` (immutato)

## Note sulle varianti (Claude / Codex / Gemini)

Gli agent `sdd-discovery-responder`, `sdd-approver` e `sdd-methodology-picker` richiedono
il supporto a sub-agent isolati. **Questa skill funziona pienamente in Claude Code**, che
supporta i sub-agent nativamente.

Per le varianti che non supportano sub-agent isolati (es. Codex / Gemini al momento della
generazione), gli agent vengono eseguiti come prompt strutturati nello stesso contesto:
il formato di output `---DISCOVERY-ANSWER---`, `---APPROVAL-RESULT---`,
`---METHODOLOGY-CHOICE---` resta lo stesso, e i builder dedicati (`build-codex.sh`,
`build-gemini.sh`) decidono come distribuire questi agent. Verifica i limiti specifici
nel README della variante.
