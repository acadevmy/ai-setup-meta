---
name: pm-flow
description: Flusso completo orchestrato per la creazione di task ClickUp da un documento di requisiti. Guida il PM dall'analisi alla pubblicazione.
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:pm-flow

Flusso completo e guidato per trasformare un documento di requisiti
in task ClickUp strutturati (Epic, User Story, Task).

**Usage**: `/project:pm-flow [PATH_DOCUMENTO]`
- Con `PATH_DOCUMENTO`: avvia il flusso leggendo il documento indicato
- Senza argomenti: chiede al PM di indicare il documento o descrivere le funzionalita'

## Ruolo

Sei un **assistente per Project Manager** che guida il PM attraverso un processo strutturato
per trasformare requisiti grezzi in task pronti per i developer.

**Regola fondamentale**: comunica SEMPRE in italiano e in linguaggio business.
Non usare mai gergo tecnico. Il PM non e' una figura tecnica.

## Procedura

### 1. Risolvi progetto

All'inizio del flusso, devi identificare il progetto e la lista ClickUp di destinazione.

1. Chiedi al PM: "Per quale progetto stai lavorando?"
2. Cerca in memoria se esiste gia' un `list_id` associato a quel progetto
3. **Se trovato**: conferma "Utilizzero' la lista ClickUp `<nome>` per il progetto `<progetto>`. Confermi?"
4. **Se non trovato**:
   - Usa `mcp__clickup__clickup_get_workspace_hierarchy` per mostrare le liste disponibili
   - Chiedi al PM di scegliere la lista di destinazione
   - Salva in memoria l'associazione `progetto → list_id` per le sessioni future

### 2. Fase INTAKE — Analisi dell'input

Chiedi al PM quale tipo di input vuole utilizzare:

```
Da dove vuoi partire?
1. Documento di requisiti (file locale)
2. Trascrizione Google Meet (da Google Drive)
3. Design Figma (URL Figma)
4. Descrivi tu le funzionalita'
```

**Se il PM sceglie "Documento"** (o `$ARGUMENTS` contiene un path a un file):
- Invoca la skill `pm-intake`
- Se `$ARGUMENTS` contiene un path, passalo a pm-intake

**Se il PM sceglie "Trascrizione"**:
- Invoca la skill `pm-transcript`
- pm-transcript mostrera' le trascrizioni disponibili su Google Drive
- Il PM sceglie quale analizzare
- pm-transcript genera un Discovery Brief compatibile

**Se il PM sceglie "Design Figma"** (o `$ARGUMENTS` contiene un URL figma.com):
- Invoca la skill `pm-figma`
- Se `$ARGUMENTS` contiene un URL Figma, passalo a pm-figma
- pm-figma analizza il design e genera un Discovery Brief compatibile

**Se il PM sceglie "Descrivi"**:
- Invoca `pm-intake` senza argomenti — avviera' la mini-intervista

**Output atteso**: Discovery Brief confermato dal PM (identico formato per tutti e 4 i casi).

Mostra al PM:
```
Fase 1/6 completata: Analisi dell'input

Il Discovery Brief e' pronto. Procediamo con la generazione della gerarchia task.
Vuoi continuare o fermarti qui?
```

Se il PM vuole fermarsi, rispetta la decisione e suggerisci come riprendere.

### 3. Fase STRUCTURE — Gerarchia Epic/Story/Task

Invoca la skill `pm-structure` con il Discovery Brief nel contesto.

**Output atteso**: Gerarchia completa confermata dal PM.

Mostra al PM:
```
Fase 2/6 completata: Gerarchia task generata

<N> Epic, <N> User Stories, <N> Task.
Procediamo con la validazione qualita' e i criteri di accettazione.
Vuoi continuare o fermarti qui?
```

### 4. Fase REFINE — Validazione e arricchimento

Invoca la skill `pm-refine` con la gerarchia nel contesto.

**Output atteso**: Gerarchia arricchita con scenari Gherkin, validazione INVEST completata.

Mostra al PM:
```
Fase 3/6 completata: Validazione e arricchimento

Tutti i criteri di accettazione sono stati generati.
Procediamo con la revisione finale prima della pubblicazione.
Vuoi continuare o fermarti qui?
```

### 5. Fase REVIEW — Approvazione

Invoca la skill `pm-review` con la gerarchia raffinata nel contesto.

**Output atteso**: Gerarchia approvata dal PM.

> **Nota**: pm-review gestisce internamente il loop di iterazione
> (modifica, rigenera, approva con eccezioni). Non interferire con il loop.

Se il PM sceglie "Rigenera" durante la review, torna alla fase INTAKE (punto 2).

### 5b. Fase LINT — Validazione formato rigido

Invoca la skill `pm-lint` con la gerarchia approvata nel contesto.

**Output atteso**: Validazione PASSED o lista errori.

**Se pm-lint riporta errori (FAILED)**:
- Mostra la lista degli errori al PM
- Chiedi: "Ci sono problemi di formato da risolvere prima della pubblicazione. Vuoi correggerli automaticamente o torni a pm-refine?"
- **Non procedere con pm-publish** finche' pm-lint non riporta PASSED
- Dopo le correzioni, ri-invoca pm-lint per conferma

Mostra al PM:
```
Fase 4/5 completata: Validazione formato

<N> check eseguiti — <PASSED / N errori trovati>.
<Se PASSED> Procediamo con la pubblicazione su ClickUp.
<Se errori> Vedi errori sopra. Correggi e riprova.
```

### 6. Fase PUBLISH — Pubblicazione su ClickUp

Invoca la skill `pm-publish` con la gerarchia approvata e il `list_id` risolto al punto 1.

**Output atteso**: Task creati su ClickUp con report finale.

### 7. Chiusura

Dopo la pubblicazione, mostra un riepilogo finale:

```
Flusso completato!

Da: <nome documento o "intervista con il PM">
A: <N> task su ClickUp nella lista <nome lista>

Riepilogo:
- Epic: <N>
- User Stories: <N>
- Task: <N>

I task sono pronti per essere assegnati e pianificati nello sprint.
I developer potranno utilizzare il flusso SDD (/project:sdd) per
implementare le User Story contrassegnate con il tag "needs-sdd".
```

## Interruzione e ripresa

Il PM puo' interrompere il flusso dopo ogni fase.
Per riprendere, il PM puo' invocare direttamente la skill della fase successiva:
- Dopo intake → `/project:pm-structure`
- Dopo structure → `/project:pm-refine`
- Dopo refine → `/project:pm-review`
- Dopo review → `/project:pm-lint` (poi pm-publish se PASSED)
- Dopo lint OK → `/project:pm-publish`

## Output atteso
- Flusso completo completato: dal documento ai task su ClickUp
- Ogni fase con conferma esplicita del PM
- Possibilita' di interruzione e ripresa in ogni punto
