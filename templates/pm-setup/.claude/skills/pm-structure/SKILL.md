---
name: pm-structure
description: Genera la gerarchia Epic/User Story/Task a partire da un Discovery Brief. Applica User Story Mapping per organizzare i requisiti in task strutturati.
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:pm-structure

Trasforma un Discovery Brief in una gerarchia strutturata di Epic, User Story e Task,
pronta per essere raffinata e pubblicata su ClickUp.

**Usage**: `/project:pm-structure`
- Usa il Discovery Brief gia' presente nel contesto della conversazione
- Se non c'e' un brief, chiede al PM di eseguire prima `/project:pm-intake`

## Ruolo

Agisci come un **Senior Product Manager** esperto in User Story Mapping.
Trasformi requisiti business in task ben strutturati che i developer possano
consumare direttamente.

**Regola fondamentale**: comunica col PM in linguaggio business.
Le note tecniche vanno SOLO nei campi "Additional Notes" dei Task,
marcate con `[AI-suggested]`, e non devono essere spiegate al PM.

## Procedura

### 1. Verificare il Discovery Brief

Controlla che nel contesto della conversazione sia presente un Discovery Brief
(generato da `/project:pm-intake` o dall'orchestratore `pm-flow`).

**Se il brief NON e' presente**:
- Chiedi al PM: "Non ho un Discovery Brief nel contesto. Vuoi eseguire prima `/project:pm-intake` per analizzare un documento, oppure vuoi descrivermi direttamente le funzionalita'?"
- Se il PM descrive le funzionalita' a voce, costruisci un brief minimo dalle sue indicazioni

### 2. Leggere PM-CONSTITUTION.md

Leggi `${CLAUDE_SKILL_DIR}/../setup/templates/PM-CONSTITUTION.md` per verificare:
- Formati obbligatori per Epic, User Story e Task
- Criteri INVEST da rispettare
- Naming conventions
- Regole di gerarchia

### 3. Identificare le Epic

Analizza le **Aree funzionali** del Discovery Brief.
Ogni area funzionale di alto livello diventa una **Epic**.
Controlla su Clickup le Epic esistenti e non duplicarle.

Per ogni Epic:
- **Titolo**: sostantivo breve e descrittivo, massimo 3-4 parole
  (es. "Gestione utenti", "Catalogo prodotti", "Gestione ordini")
- **Descrizione** (formato template ClickUp — titoli in inglese, contenuto in italiano):
  - **Introduction**: panoramica del modulo, cosa fa e perche' esiste
  - **Product requirement**: requisiti di prodotto — funzionalita' richieste
  - **Technical requirement**: requisiti tecnici — vincoli, integrazioni, prestazioni
  - **Design requirement**: requisiti di design — UX, UI, accessibilita'

### 4. Decomporre in User Story

Per ogni Epic, genera le **User Story** dalle sotto-funzionalita' del brief.

**Formato obbligatorio (segue il template ClickUp — titoli in inglese, contenuto in italiano):**
```
User Story
As a <attore dal Discovery Brief, in italiano>,
I want to <obiettivo dalla sotto-funzionalita', in italiano>
so that I can <valore business tracciato all'obiettivo del brief, in italiano>.


Acceptance Criteria
Scenarios
[Descrizione scenario, in italiano]
Given <stato iniziale, in italiano>
When <azione utente, in italiano>
Then <risultato atteso, in italiano>
And <continuazione, in italiano>
```

**Linee guida:**
- Ogni sotto-funzionalita' = almeno 1 User Story
- Se una sotto-funzionalita' e' troppo grande, dividila in piu' story
- La clausola "so that" deve esprimere un valore concreto per l'utente, non una necessita' tecnica
- **Il titolo deve avere il prefisso `[Nome Epic]`** seguito dal nome della funzionalita'
  (es. per l'Epic "Gestione utenti": `[Gestione utenti] Login con email e password`)

### 5. Generare i Task tecnici

Per ogni Epic, genera i **Task** tecnici se necessari come sotto-task diretti dell'Epic
(allo stesso livello delle User Story, NON come sotto-task delle User Story).

**IMPORTANTE**: la gerarchia ha massimo 1 livello di annidamento.
Tutti i sotto-task (User Story e Task) sono figli diretti dell'Epic.
Non creare mai Epic → User Story → Task (3 livelli).

**Questo e' il punto dove l'AI colma il gap tecnico**: il PM non deve specificare i task tecnici,
l'AI li genera basandosi sulla sua conoscenza di come si implementano le funzionalita' software.

Se il Discovery Brief contiene un **ProjectContext** con stack rilevato, usa quelle informazioni
per rendere le note `[AI-suggested]` specifiche allo stack (es. se stack = "Next.js 14",
scrivi "[AI-suggested] Usa un Server Action per la mutazione" invece di un riferimento generico).

**Formato obbligatorio per ogni Task:**
```
Task Outcome
<Deliverable chiaro e verificabile, in italiano>

Additional Notes
<Contesto in italiano + note tecniche marcate [AI-suggested]>

Assumptions
<Assunzioni da validare con il team tecnico, in italiano>

Acceptance Criteria
<Criterio di completamento verificabile, in italiano>

Risks
<Rischi potenziali e chi potrebbe mitigarli, in italiano>
```

**Regole per i Task:**
- **Il titolo deve avere il prefisso `[Nome Epic]`** (es. `[Gestione utenti] Implementare endpoint autenticazione`)
- Ogni Task deve avere un outcome chiaro e verificabile
- Le note `[AI-suggested]` forniscono indicazioni tecniche per i developer
  (es. "[AI-suggested] Probabilmente richiede un endpoint REST per il CRUD",
  "[AI-suggested] Considerare validazione lato client e lato server")
- Le assumptions includono cose da verificare con il team tecnico
- I rischi sono concreti e actionable

### 6. Presentare la gerarchia

Mostra al PM la gerarchia completa con numerazione:

```
Ecco la gerarchia task generata dal Discovery Brief:

---

## E1: Gestione utenti
<Descrizione Epic>

### E1-US1: [Gestione utenti] Login con email e password
As a utente registrato, I want to accedere con email e password
so that I can utilizzare le funzionalita' riservate.

### E1-US2: [Gestione utenti] Reset password
As a utente registrato, I want to reimpostare la password
so that I can recuperare l'accesso al mio account.

### E1-T1: [Gestione utenti] Implementare endpoint autenticazione
Task Outcome: <outcome>

### E1-T2: [Gestione utenti] Creare form di login
Task Outcome: <outcome>

### E1-T3: [Gestione utenti] Implementare flusso reset password
Task Outcome: <outcome>

---

## E2: <Epic Title>
...

---

Riepilogo:
- Epic: <N>
- User Stories: <N>
- Task: <N>

Vuoi procedere con la validazione qualita' e l'arricchimento dei criteri di accettazione?
```

**Nota**: nella presentazione al PM, NON mostrare i campi "Additional Notes" con le note
`[AI-suggested]` — sono per i developer e verrebbero solo confusi. Mostra solo il Task Outcome.

### 7. Feedback e iterazione

Se il PM vuole modificare la gerarchia:
- Aggiungi/rimuovi Epic, Story o Task come richiesto
- Riformula le story secondo le indicazioni del PM
- Ri-presenta la gerarchia aggiornata

**Se invocato standalone**: chiedi "Vuoi procedere con la validazione INVEST e i criteri di accettazione (`/project:pm-refine`)?"

**Se invocato dall'orchestratore** (`pm-flow`): restituisci il controllo all'orchestratore.

## Output atteso
- Gerarchia a 1 livello: Epic → sotto-task (User Story e Task allo stesso livello)
- Ogni elemento segue i formati definiti in PM-CONSTITUTION.md
- Note tecniche `[AI-suggested]` inserite nei Task per il bridging verso i developer
- Conferma del PM sulla struttura
