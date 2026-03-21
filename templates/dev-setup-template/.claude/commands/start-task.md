# /project:start-task

Prende il prossimo task da ClickUp e avvia il flusso di sviluppo.

## Flusso completo

### 1. Recupera il prossimo task da ClickUp
Usa il MCP ClickUp per cercare i task con:
- **Stato**: `SPRINT`
- **Ordinamento**: per priorita' (1 = urgent, 2 = high, 3 = normal, 4 = low)
- Prendi il **primo task** con priorita' piu' alta

Se non ci sono task in stato SPRINT, informa lo sviluppatore e fermati.

Recupera dal task:
- `custom_id` (es. DE-123)
- `name` (titolo)
- `description` (descrizione/brief)
- `priority`

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
Usa il MCP ClickUp per spostare il task in stato **IN PROGRESS**.

### 4. Mostra il brief allo sviluppatore
Presenta un riepilogo:
```
Task:     DE-123 — Titolo del task
Priorita': Alta
Branch:   feat/DE-123-add-user-auth
Stato:    IN PROGRESS

Descrizione:
<contenuto della descrizione del task>
```

### 5. Avvia lo sviluppo
Procedi con il flusso TDD (regola 9 della Costituzione):
1. Analizza i requisiti dal brief
2. Scrivi i test che descrivono il comportamento atteso
3. Verifica che falliscano (red)
4. Implementa il minimo codice per farli passare (green)
5. Refactoring (refactor)

### 6. Al termine — Apri PR e aggiorna stato
Quando lo sviluppo e' completato:

1. **Commit** con Conventional Commits (includi il customId):
   ```
   feat(auth): add refresh token rotation [DE-123]
   ```

2. **Push** del branch:
   ```bash
   git push -u origin <branch-name>
   ```

3. **Apri PR** con `gh pr create`:
   - Titolo: segue Conventional Commits con customId
   - Body: include sezioni Cosa / Perche' / Come testare + link al task ClickUp

4. **Aggiorna stato** del task su ClickUp a **IN REVIEW** (o **CODE REVIEW**)

## Output atteso
- Branch creato con customId nel nome
- Task spostato: SPRINT → IN PROGRESS → IN REVIEW
- PR aperta su GitHub con riferimento al task ClickUp
