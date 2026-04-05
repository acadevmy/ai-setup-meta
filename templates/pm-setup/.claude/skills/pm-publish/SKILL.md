---
name: pm-publish
description: Pubblica la gerarchia approvata di Epic/User Story/Task su ClickUp via MCP. Gestisce tipi custom, gerarchia padre-figlio e delay per template.
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:pm-publish

Pubblica la gerarchia approvata di Epic, User Story e Task su ClickUp,
creando i task con i tipi custom corretti e mantenendo la gerarchia padre-figlio.

**Usage**: `/project:pm-publish`
- Usa la gerarchia approvata presente nel contesto della conversazione (da pm-review)
- Se non c'e' una gerarchia approvata, chiede al PM di completare prima le fasi precedenti

## Procedura

### 1. Verificare la gerarchia approvata

Controlla che nel contesto della conversazione sia presente una gerarchia
approvata dal PM (da `/project:pm-review`).

**Se la gerarchia NON e' presente o NON e' approvata**:
- Chiedi al PM: "Non ho una gerarchia approvata. Vuoi eseguire prima la revisione (`/project:pm-review`)?"
- Non procedere finche' la gerarchia non e' approvata

### 2. Risolvere il progetto e la lista ClickUp

Il setup e' installato globalmente — non esiste un `.env` per progetto.
La mappa `progetto → list_id` e' nella memoria del modello.

1. **Chiedi al PM** per quale progetto sta lavorando (se non gia' specificato nel flusso)
2. **Cerca in memoria** se esiste gia' un `list_id` associato a quel progetto
3. **Se non trovato in memoria**:
   - Usa `mcp__clickup__clickup_get_workspace_hierarchy` per recuperare la gerarchia del workspace
   - Presenta al PM le liste disponibili in formato leggibile
   - Chiedi al PM di scegliere la lista di destinazione
   - **Salva in memoria** l'associazione `progetto → list_id` per le sessioni future
4. **Conferma con il PM**: "Pubblichero' i task nella lista `<nome lista>` (`<list_id>`). Confermi?"

### 3. Recuperare i tag disponibili

Prima di creare i task, recupera la lista dei tag esistenti nello space ClickUp.

**Non creare mai tag nuovi.** Usa solo tag gia' presenti nello space.

Se nessun tag esistente e' appropriato per un task, non assegnare tag
piuttosto che crearne uno nuovo.

### 4. Creare le Epic

Per ogni Epic nella gerarchia approvata:

1. **Crea il task** con `mcp__clickup__clickup_create_task`:
   - `name`: titolo breve della Epic (es. "User Management")
   - `list_id`: il list_id risolto al punto 2
   - `task_type`: `"Epic"`
   - `tags`: solo tag gia' esistenti nello space (recuperati al punto 3), se appropriati
   - `priority`: la priorita' assegnata in pm-refine (se presente)

2. **Attendi 1 secondo** — ClickUp applica un template al tipo custom "Epic"

3. **Aggiorna la descrizione** con `mcp__clickup__clickup_update_task`:
   - `markdown_description`: descrizione ad alto livello della Epic

4. **Salva il `task_id`** restituito — servira' come `parent` per i sotto-task

### 5. Creare i sotto-task (User Story e Task)

La gerarchia ha **massimo 1 livello di annidamento**: tutti i sotto-task
sono figli diretti dell'Epic. Non creare mai sotto-task di sotto-task.

Per ogni **User Story** nella gerarchia approvata:

1. **Crea il task** con `mcp__clickup__clickup_create_task`:
   - `name`: prefisso `[Nome Epic]` + nome funzionalita' (es. "[User Management] Login with email and password")
   - `list_id`: il list_id risolto al punto 2
   - `task_type`: `"User Story"`
   - `parent`: il `task_id` della **Epic padre** (sempre l'Epic, mai un'altra US)
   - `tags`: solo tag gia' esistenti nello space, se appropriati
   - `priority`: la priorita' assegnata in pm-refine

2. **Attendi 1 secondo** — ClickUp applica un template al tipo custom "User Story"

3. **Aggiorna la descrizione** con `mcp__clickup__clickup_update_task`:
   - `markdown_description`:
     ```markdown
     ## User Story
     Come <ruolo>, voglio <obiettivo> in modo da <motivazione>.

     ## Criteri di accettazione
     Scenario: <descrizione scenario>
     Dato <stato iniziale>
     Quando <azione utente>
     Allora <risultato atteso>
     E <continuazione>
     ```

Per ogni **Task** nella gerarchia approvata:

1. **Crea il task** con `mcp__clickup__clickup_create_task`:
   - `name`: prefisso `[Nome Epic]` + verbo + deliverable (es. "[User Management] Implement auth endpoint")
   - `list_id`: il list_id risolto al punto 2
   - `parent`: il `task_id` della **Epic padre** (sempre l'Epic, mai una US)
   - `tags`: solo tag gia' esistenti nello space, se appropriati
   - `priority`: la priorita' assegnata in pm-refine
   - `markdown_description`: inserisci subito (nessun template custom da attendere)
     ```markdown
     ## Risultato atteso
     <deliverable chiaro e verificabile>

     ## Note aggiuntive
     <contesto>
     - [AI-suggested] <nota tecnica per i developer>

     ## Assunzioni
     - <assunzione da validare>

     ## Criteri di accettazione
     Il task e' completato quando...
     <criterio di completamento>

     ## Rischi
     - <rischio e possibile mitigazione>
     ```

> **Nota**: i Task usano il tipo standard di ClickUp (nessun `task_type`).
> La descrizione viene inserita direttamente nella creazione, senza delay.
> Tutti i sotto-task (US e Task) sono figli diretti dell'Epic — mai annidati tra loro.

### 7. Impostare le dipendenze

Per ogni dipendenza identificata in pm-refine:

- Usa `mcp__clickup__clickup_add_task_dependency` per collegare i task
- Il task bloccante (`depends_on`) deve essere completato prima del task bloccato

### 8. Report finale

Presenta al PM un report completo della pubblicazione:

```
Pubblicazione completata su ClickUp!

Lista: <nome lista> (<list_id>)
Progetto: <nome progetto>

Task creati:

Epic: <Epic Title> — <URL>
  User Story: <Story Title> — <URL>
    Task: <Task Title> — <URL>
    Task: <Task Title> — <URL>
  User Story: <Story Title> — <URL>
    Task: <Task Title> — <URL>

Epic: <Epic Title> — <URL>
  ...

Riepilogo:
- Epic create: <N>
- User Story create: <N>
- Task creati: <N>
- Dipendenze impostate: <N>
- Tag applicati: <tag dallo space utilizzati, se presenti>

Tutti i task sono pronti per essere assegnati e pianificati nello sprint!
```

### 9. Gestione errori

Se la creazione di un task fallisce:
- **NON fermarti**: segna l'errore e procedi con il task successivo
- Alla fine, presenta un report degli errori:
  ```
  Attenzione: <N> task non sono stati creati. Errori:
  - <task title>: <messaggio di errore>
  ```
- Suggerisci al PM come risolvere (es. "Verifica che la lista esista e che tu abbia i permessi")

## Output atteso
- Task creati su ClickUp con gerarchia a 1 livello (Epic → sotto-task)
- Tipi custom applicati (Epic, User Story)
- Tag e dipendenze impostati
- Report finale con URL di tutti i task creati
