# Skill: ClickUp Operations

Operazioni ClickUp tramite MCP. Usare per leggere task, aggiornare stati,
creare notifiche al team.

## Pre-condizioni
- MCP ClickUp configurato (`CLICKUP_API_KEY`, `CLICKUP_TEAM_ID` in `.env.local`)

## Operazioni disponibili

### Leggere un task
```
Usa il MCP ClickUp per recuperare i dettagli di un task dato il suo ID.
Output: titolo, descrizione, stato, assegnatari, custom fields
```

### Aggiornare lo stato di un task
```
Stati disponibili (verificare con il workspace reale):
  - TO DO
  - IN PROGRESS
  - IN REVIEW
  - DONE

Usa il MCP ClickUp per aggiornare lo stato.
Input: task ID, nuovo stato
```

### Creare un task
```
Usa il MCP ClickUp per creare un nuovo task.
Campi obbligatori:
  - list_id: ID lista di destinazione
  - name: titolo del task
  - description: descrizione (markdown supportato)
Campi opzionali:
  - assignees: lista di user ID
  - priority: 1 (urgent) / 2 (high) / 3 (normal) / 4 (low)
  - due_date: timestamp Unix
```

### Recuperare task "Next Up"
```
Usa il MCP ClickUp per recuperare il prossimo task da lavorare.
Filtri: stato = TO DO, assegnato all'utente corrente, priorità più alta
```

## Casi d'uso tipici nel meta-repo

**Release notification**: dopo `/project:release`, creare un task per ogni
sviluppatore con le istruzioni di aggiornamento.

**Setup tracking**: tracciare l'adozione del nuovo template da parte del team.
