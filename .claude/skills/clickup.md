# Skill: ClickUp Operations

Operazioni ClickUp tramite MCP. Usare per leggere task, aggiornare stati,
creare notifiche al team.

## Pre-condizioni
- MCP ClickUp configurato via OAuth: `claude mcp add clickup https://mcp.clickup.com/mcp`
- Ogni sviluppatore si autentica con il proprio account ClickUp (supporta anche guest)
- Ogni operazione lavora su una specifica `list_id` — non serve un `TEAM_ID` globale

## Stati del workflow

```
SPRINT  →  IN PROGRESS  →  IN REVIEW / CODE REVIEW  →  DONE
```

| Stato | Significato |
|---|---|
| SPRINT | Task pianificato nello sprint corrente, pronto per essere preso |
| IN PROGRESS | Sviluppo in corso |
| IN REVIEW / CODE REVIEW | PR aperta, in attesa di review |
| DONE | Completato e mergiato |

## Operazioni disponibili

### Recuperare il prossimo task da lavorare
```
Usa il MCP ClickUp per recuperare i task con:
  - Filtro stato: SPRINT
  - Ordinamento: per priorità (1 = urgent, 2 = high, 3 = normal, 4 = low)
  - Prendi il primo task con priorità più alta

Il task restituito contiene il campo `custom_id` (es. DE-123) che va usato
nel nome del branch.
```

### Leggere un task
```
Usa il MCP ClickUp per recuperare i dettagli di un task dato il suo ID.
Output: titolo, descrizione, stato, assegnatari, custom fields, custom_id
```

### Aggiornare lo stato di un task
```
Usa il MCP ClickUp per aggiornare lo stato.
Input: task ID, nuovo stato

Transizioni valide:
  SPRINT       → IN PROGRESS        (quando si inizia a lavorare)
  IN PROGRESS  → IN REVIEW          (quando la PR è aperta)
  IN PROGRESS  → CODE REVIEW        (alternativa a IN REVIEW)
  IN REVIEW    → DONE               (dopo merge)
  CODE REVIEW  → DONE               (dopo merge)
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

## Casi d'uso tipici nel meta-repo

**Release notification**: dopo `/project:release`, creare un task per ogni
sviluppatore con le istruzioni di aggiornamento.

**Setup tracking**: tracciare l'adozione del nuovo template da parte del team.
