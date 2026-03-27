---
name: sdd
description: Avvia il flusso Spec-Driven Development completo (spec, approvazione, sviluppo, review, PR)
model: opus
user-invocable: true
disable-model-invocation: true
---

# /project:sdd

Avvia il flusso Spec-Driven Development (SDD) completo per un task ClickUp.
A differenza di `/project:start-task` che va direttamente allo sviluppo, questo flusso
produce prima una **specifica tecnica** e un **piano di implementazione**, li discute
con lo sviluppatore, e solo dopo l'approvazione procede con lo sviluppo.

**Uso**: `/project:sdd [TASK_ID]`
- Con `TASK_ID` (es. `DE-123`): recupera direttamente quel task da ClickUp
- Senza argomenti: mostra i task disponibili in SPRINT e chiede quale prendere

## Flusso completo

### 1. Selezione del task

**Se e' stato fornito un TASK_ID** (argomento `$ARGUMENTS`):
- Lancia l'agent `clickup` con:
  - INTENT: `read`
  - PARAMS: `task_id: <TASK_ID fornito>`
- Se l'agent restituisce STATUS: error, informa lo sviluppatore e fermati

**Se NON e' stato fornito un TASK_ID**:
- Leggi `CLICKUP_SETUP_LIST_ID` dal file `.env` nella root del progetto
- Se la variabile non e' configurata, informa lo sviluppatore di compilare `.env` e fermati
- Lancia l'agent `clickup` con:
  - INTENT: `filter`
  - PARAMS: `list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`
- Se l'agent restituisce STATUS: error, informa lo sviluppatore e fermati
- Chiedi allo sviluppatore quanti task vuole visualizzare (default: 5)
- Dai risultati, prendi i primi N task ordinati per priorita' (1 = urgent, ..., 4 = low)
- Presentali allo sviluppatore:
  ```
  Task disponibili (SPRINT):
  1. [DE-123] Titolo task 1 (Priorita': Urgent)
  2. [DE-124] Titolo task 2 (Priorita': Alta)
  3. [DE-125] Titolo task 3 (Priorita': Normale)
  ...
  ```
- Chiedi allo sviluppatore quale task vuole prendere in carico
- Lancia l'agent `clickup` con INTENT: `read` per recuperare il contenuto completo del task scelto

Dall'output dell'agent, estrai:
- `custom_id` (es. DE-123)
- `name` (titolo)
- `description` (descrizione — riportata integralmente dall'agent)
- `priority`
- `task_id` (per aggiornamenti successivi)
- `url` (link al task)

### 2. Crea il branch di lavoro

Determina il tipo di branch dal titolo/descrizione del task:
- Feature → `feat/`
- Bug → `fix/`
- Manutenzione → `chore/`

Crea il branch con il customId:
```bash
git checkout main
git pull origin main
git checkout -b <tipo>/<customId>-<descrizione-breve>
```

Esempio: `feat/DE-123-add-user-auth`

### 3. Aggiorna lo stato del task

Lancia l'agent `clickup` con:
- INTENT: `update`
- PARAMS: `task_id: <task_id>, status: IN PROGRESS`

### 4. Mostra il brief

Presenta un riepilogo:
```
Task:     DE-123 — Titolo del task
Priorita': Alta
Branch:   feat/DE-123-add-user-auth
Stato:    IN PROGRESS

Descrizione:
<contenuto della descrizione del task — come restituito dall'agent>
```

### 5. Discovery — Intervista strutturata

Invoca `/project:sdd-discovery` passando il contesto del task (custom_id, name, description, priority, url).

La skill condurra' un'intervista interattiva con lo sviluppatore per raccogliere
requisiti completi, edge cases, vincoli e preferenze. Al termine produrra' un
**Discovery Summary** strutturato che verra' usato come input per la generazione della spec.

Attendi il completamento della discovery prima di procedere.

### 6. Genera la specifica tecnica

Invoca `/project:sdd-spec` passando il contesto del task (custom_id, name, description, url, branch) e il Discovery Summary prodotto allo step precedente.

La spec verra' generata in `.specs/<customId>-<slug>.md` con status `draft`.

### 7. Revisione e approvazione della spec

Invoca `/project:sdd-plan` per presentare la spec allo sviluppatore.

Questo e' un **checkpoint di supervisione**: il flusso si ferma finche' lo sviluppatore
non approva esplicitamente la spec. Lo sviluppatore puo':
- Discutere e commentare la soluzione proposta
- Richiedere modifiche alla spec
- Approvare e procedere

### 8. Scelta della metodologia di sviluppo

Dopo l'approvazione della spec, chiedi allo sviluppatore:
```
Metodologia di sviluppo:
1. TDD (Red-Green-Refactor) — consigliato per backend, logica di business, API, servizi
2. BDD (Given/When/Then) — consigliato per frontend, componenti UI, flussi utente
3. Nessuna — sviluppo diretto senza ciclo test-first
```

### 9. Sviluppo

Invoca `/project:sdd-dev` passando il path della spec e la metodologia scelta.

Lo sviluppo seguira' il piano di implementazione definito nella spec approvata.

### 10. Chiusura — Qualita', review e PR

Quando lo sviluppo e' completato:

1. **Commit** con Conventional Commits (includi il customId):
   ```
   feat(auth): add refresh token rotation [DE-123]
   ```

2. **Simplify** — Esegui la skill `simplify` per rivedere il codice modificato:
   - Cerca opportunita' di riuso di codice esistente
   - Migliora qualita' e efficienza
   - Correggi eventuali problemi trovati
   - Se ci sono modifiche, committale: `refactor(<scope>): simplify implementation`

3. **Review** — Esegui `/project:review` per:
   - Verificare conformita' alla CONSTITUTION.md (tramite Review Agent)
   - Verificare qualita' del codice
   - Aggiornare automaticamente `REGISTRY.md` con le nuove entry

4. **Riepilogo** — Mostra allo sviluppatore un riepilogo completo:
   ```
   Riepilogo implementazione: DE-123 — Titolo del task

   Spec: .specs/DE-123-<slug>.md
   Metodologia: <tdd/bdd/nessuna>
   File creati: <lista>
   File modificati: <lista>
   Test: <passanti/falliti>
   Review: <esito>
   REGISTRY: <aggiornato/invariato>
   ```

5. **Attendi OK** — Lo sviluppatore deve confermare che la soluzione e' completa e corretta.
   Se lo sviluppatore richiede modifiche, applica le correzioni e torna al punto 1 di questo step.

6. **Push** del branch:
   ```bash
   git push -u origin <branch-name>
   ```

7. **Apri PR** con `gh pr create`:
   - Titolo: segue Conventional Commits con customId (es. `feat(auth): add refresh token rotation [DE-123]`)
   - Body: include sezioni Cosa / Perche' / Come testare + link al task ClickUp + link alla spec

8. **Aggiorna stato** — Lancia l'agent `clickup` con:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: CODE REVIEW`
   - Se lo stato `CODE REVIEW` non e' disponibile, usa `IN REVIEW`

9. **Aggiorna spec** — Cambia lo status della spec da `approved` a `implemented` nel file `.specs/<customId>-<slug>.md`

## Output atteso
- Branch creato con customId nel nome
- Spec tecnica in `.specs/` (status: implemented)
- Codice implementato seguendo la spec approvata
- Codice ottimizzato (simplify) e conforme alla CONSTITUTION (review)
- `REGISTRY.md` aggiornato con le nuove entry
- Task spostato: SPRINT → IN PROGRESS → CODE REVIEW
- PR aperta su GitHub con riferimento al task ClickUp e alla spec
