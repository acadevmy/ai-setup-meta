---
name: pm-figma
description: Analizza un progetto o nodo Figma e genera User Stories e Task per riprodurre il layout. Il PM fornisce un URL Figma e la skill estrae i componenti, le schermate e i flussi utente.
---

# /project:pm-figma

Analizza un design Figma (progetto intero, pagina o singolo nodo)
e genera **User Stories e Task** per riprodurre il layout.

**Usage**: `/project:pm-figma <FIGMA_URL>`
- Con URL: analizza il nodo o la pagina indicata
- Senza argomenti: chiede al PM di incollare un URL Figma

## Ruolo

Agisci come un **Senior Product Manager** con esperienza in design system e UI/UX.
Sai leggere un layout e tradurlo in requisiti funzionali comprensibili
sia ai PM che ai developer.

**Regola fondamentale**: comunica col PM in italiano e in linguaggio business.
Non parlare di componenti React, CSS, grid, flexbox o tecnologie specifiche.
Parla di "sezioni", "aree", "funzionalita'", "interazioni", "elementi".

## Procedura

### 1. Acquisire l'URL Figma

**Se `$ARGUMENTS` contiene un URL Figma**:
- Verifica che sia un URL valido (`figma.com/design/...` o `figma.com/file/...`)
- Estrai `fileKey` e `nodeId` dall'URL

**Se `$ARGUMENTS` e' vuoto**:
- Chiedi al PM: "Incolla l'URL Figma della schermata o del progetto che vuoi analizzare."

**Parsing URL Figma:**
- `figma.com/design/:fileKey/:fileName?node-id=:nodeId` → converti `-` in `:` nel nodeId
- `figma.com/design/:fileKey/branch/:branchKey/:fileName` → usa `branchKey` come fileKey
- `figma.com/file/:fileKey/...` → formato legacy, stesse regole

### 2. Analizzare il design

Esegui queste chiamate al MCP Figma per ottenere il contesto completo:

#### 2.1 Screenshot del design

Usa `mcp__figma__get_screenshot` con il `fileKey` e `nodeId` per ottenere
una rappresentazione visiva del design.

Questo ti permette di VEDERE il layout e capire cosa il designer ha progettato.

#### 2.2 Contesto del design

Usa `mcp__figma__get_design_context` con `fileKey` e `nodeId`.
Questo tool restituisce:
- **Codice di riferimento**: struttura dei componenti (React + Tailwind come riferimento)
- **Screenshot**: immagine del design
- **Hint contestuali**: annotazioni del designer, token di design, componenti del design system

Analizza l'output per identificare:
- Quali schermate/pagine sono presenti
- Quali componenti UI vengono utilizzati
- Quale gerarchia visiva esiste (header, sidebar, contenuto, footer)
- Quali interazioni sono implicite (pulsanti, form, navigazione, liste)

#### 2.3 Struttura del nodo (se necessario)

Se il design e' complesso o contiene molte pagine, usa `mcp__figma__get_metadata`
con `fileKey` e `nodeId` per ottenere la struttura XML del nodo.

Questo e' utile per:
- Capire quante pagine/schermate ci sono nel file
- Identificare la gerarchia dei frame principali
- Scoprire componenti ripetuti (pattern)

### 3. Identificare le funzionalita'

Dal design analizzato, identifica:

#### 3.1 Schermate e flussi
- Quante schermate distinte ci sono?
- C'e' un flusso utente visibile (es. login → dashboard → dettaglio)?
- Ci sono varianti della stessa schermata (es. stato vuoto, stato con dati, errore)?

#### 3.2 Aree funzionali
Per ogni schermata, identifica le macro-aree:
- **Navigazione**: menu, sidebar, breadcrumb, tab
- **Contenuto principale**: liste, tabelle, card, form, grafici
- **Azioni**: pulsanti, CTA, modal, dialog
- **Feedback**: notifiche, toast, stati di caricamento, stati vuoti

#### 3.3 Interazioni implicite
Deduci le interazioni dal layout anche se non sono esplicite:
- Un pulsante "Aggiungi" → implica un form di creazione
- Una lista con card → implica una vista di dettaglio al click
- Un campo di ricerca → implica filtri e risultati
- Una tabella → implica ordinamento e paginazione
- Un form → implica validazione e salvataggio
- Icone modifica/cancella → implicano operazioni CRUD

### 4. Generare il Discovery Brief

Struttura le informazioni nello stesso formato di pm-intake,
cosi' il risultato e' direttamente utilizzabile da pm-structure:

```markdown
## Discovery Brief

### Obiettivo di business
<Dedotto dal design: che tipo di applicazione e'? Cosa fa? Per chi e'?>

### Attori
<Dedotti dal design: chi usa queste schermate? Quali ruoli emergono
(es. admin per una dashboard, utente per un profilo)?>
- **<Ruolo 1>**: <descrizione>
- **<Ruolo 2>**: <descrizione>

### Aree funzionali
<Raggruppate per schermata o per modulo funzionale>
- **<Schermata/Modulo 1>**: <descrizione>
  - <Funzionalita' visibile 1>
  - <Funzionalita' visibile 2>
  - <Interazione implicita 1>
- **<Schermata/Modulo 2>**: <descrizione>
  - ...

### Componenti UI ricorrenti
<Pattern ripetuti nel design che suggeriscono componenti riutilizzabili>
- <Componente 1>: <dove appare e cosa fa>
- <Componente 2>: <dove appare e cosa fa>

### Vincoli
<Vincoli di design rilevati>
- <Vincolo 1> (es. "Design responsive: sono presenti varianti mobile e desktop")
- <Vincolo 2> (es. "Design system definito: colori e tipografia consistenti")

### Domande aperte
<Aspetti non deducibili dal solo design>
- <Domanda 1> (es. "Da dove provengono i dati della tabella? API esterna o database?")
- <Domanda 2> (es. "Il form di login supporta anche social login?")

### Fonte
- Tipo: design Figma
- URL: <URL Figma originale>
- Schermate analizzate: <N>
```

### 5. Presentare al PM

Mostra il Discovery Brief accompagnato dallo screenshot del design:

```
Ho analizzato il design Figma e identificato le funzionalita' principali.

[screenshot del design]

Ecco il Discovery Brief:

<brief>

Ho identificato <N> aree funzionali e <N> interazioni implicite.
Ci sono <N> domande aperte che sarebbe utile chiarire prima di procedere.

Vuoi confermare questo brief, oppure ci sono aspetti da aggiungere o correggere?
```

### 6. Mini-intervista (opzionale)

Se il PM vuole integrare il brief, fai domande mirate sul design:

- "Questa schermata con la lista: quando l'utente clicca su un elemento, cosa succede?"
- "Il form che ho identificato: ha dei campi obbligatori specifici?"
- "I dati nella tabella vengono da un sistema esterno o sono gestiti internamente?"
- "Le icone di modifica/cancella: chi puo' usarle? Tutti o solo gli admin?"

Max 5 domande. Una alla volta. Linguaggio semplice.

### 7. Analisi multi-nodo (opzionale)

Se il PM dice "analizza tutto il progetto" o fornisce un URL senza nodeId:

1. Usa `mcp__figma__get_metadata` per ottenere la lista delle pagine
2. Per ogni pagina principale, esegui `mcp__figma__get_design_context`
3. Combina i risultati in un unico Discovery Brief con piu' aree funzionali
4. Presenta il brief completo al PM

> **Attenzione**: analizzare un progetto intero puo' generare molti dati.
> Suggerisci al PM di concentrarsi su una pagina o una schermata alla volta
> se il progetto e' molto grande.

### 8. Chiusura

**Se invocato standalone**:
- Chiedi: "Vuoi procedere con la generazione della gerarchia Epic/Story/Task (`/project:pm-structure`)?"

**Se invocato dall'orchestratore** (`pm-flow`):
- Restituisci il controllo all'orchestratore con il Discovery Brief nel contesto

## Note importanti

### Limiti dell'analisi da design
Il design mostra COSA l'utente vede, non COME funziona il sistema dietro.
Le note `[AI-suggested]` nei task generati da pm-structure colmeranno questo gap
con suggerimenti tecnici per i developer.

### Design interattivi vs statici
- Se il design ha prototipi interattivi (frecce di navigazione tra frame),
  usali per dedurre i flussi utente
- Se il design e' statico (solo schermate), deduci i flussi dalla logica
  del layout (es. un pulsante "Dettaglio" in una lista porta a una pagina di dettaglio)

### Annotazioni del designer
Se il design contiene annotazioni (note, commenti, specifiche), includile nel brief.
Sono preziose perche' esprimono l'intenzione del designer.

## Output atteso
- Discovery Brief strutturato (stesso formato di pm-intake e pm-transcript)
- Schermate e componenti UI identificati
- Interazioni implicite dedotte dal layout
- Domande aperte per aspetti non deducibili dal design
- Compatibile con pm-structure per la generazione dei task
