# /project:start-task

Prende un task specifico o il prossimo task dalla lista ClickUp e avvia il flusso di sviluppo.

**Uso**: `/project:start-task [TASK_ID]`
- Con `TASK_ID` (es. `DE-123`): recupera direttamente quel task da ClickUp
- Senza argomenti: cerca il prossimo task nella lista ClickUp

## Flusso completo

### 1. Recupera il task tramite ClickUp Agent

**Se e' stato fornito un TASK_ID** (argomento `$ARGUMENTS`):
- Lancia l'agent `clickup` con:
  - INTENT: `read`
  - PARAMS: `task_id: <TASK_ID fornito>`
- Se l'agent restituisce STATUS: error, informa lo sviluppatore e fermati

**Se NON e' stato fornito un TASK_ID**:
- Leggi `CLICKUP_SETUP_LIST_ID` dal file `.env` nella root del progetto
- Se la variabile non e' configurata, informa lo sviluppatore di compilare `.env` e fermati
- Lancia l'agent `clickup` con:
  - INTENT: `next-task`
  - PARAMS: `list_id: <CLICKUP_SETUP_LIST_ID>`
- Se l'agent restituisce STATUS: error (nessun task in SPRINT), informa lo sviluppatore e fermati

Dall'output dell'agent, estrai:
- `custom_id` (es. DE-123)
- `name` (titolo)
- `description` (descrizione/brief — riportata integralmente dall'agent)
- `priority`
- `task_id` (per aggiornamenti successivi)

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

### 4. Mostra il brief allo sviluppatore
Presenta un riepilogo:
```
Task:     DE-123 — Titolo del task
Priorita': Alta
Branch:   feat/DE-123-add-user-auth
Stato:    IN PROGRESS

Descrizione:
<contenuto della descrizione del task — come restituito dall'agent>
```

### 5. Avvia lo sviluppo
Procedi con il flusso TDD (regola 9 della Costituzione):
1. Analizza i requisiti dal brief
2. Scrivi i test che descrivono il comportamento atteso
3. Verifica che falliscano (red)
4. Implementa il minimo codice per farli passare (green)
5. Refactoring (refactor)

### 6. Al termine — Qualita', review e PR
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

4. **Push** del branch:
   ```bash
   git push -u origin <branch-name>
   ```

5. **Apri PR** con `gh pr create`:
   - Titolo: segue Conventional Commits con customId
   - Body: include sezioni Cosa / Perche' / Come testare + link al task ClickUp

6. **Aggiorna stato** — Lancia l'agent `clickup` con:
   - INTENT: `update`
   - PARAMS: `task_id: <task_id>, status: IN REVIEW`

## Output atteso
- Branch creato con customId nel nome
- Codice ottimizzato (simplify) e conforme alla CONSTITUTION (review)
- `REGISTRY.md` aggiornato con le nuove entry
- Task spostato: SPRINT → IN PROGRESS → IN REVIEW
- PR aperta su GitHub con riferimento al task ClickUp
