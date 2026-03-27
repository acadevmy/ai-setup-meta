---
name: sdd-spec
description: Genera una specifica tecnica e un piano di implementazione per un task ClickUp seguendo l'approccio Spec-Driven Development
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-spec

Genera una specifica tecnica completa e un piano di implementazione per un task.
Questa skill analizza il task, il contesto del progetto e produce un documento spec strutturato
nella directory `.specs/`.

**Uso**: `/project:sdd-spec [TASK_ID]`
- Con `TASK_ID` (es. `DE-123`): recupera il task da ClickUp e genera la spec
- Senza argomenti: usa il contesto gia' presente nella conversazione (quando invocata dall'orchestratore `sdd`)

## Procedura

### 1. Recupera il contesto del task

**Se `$ARGUMENTS` contiene un TASK_ID**:
- Lancia l'agent `clickup` con:
  - INTENT: `read`
  - PARAMS: `task_id: <TASK_ID fornito>`
- Se l'agent restituisce STATUS: error, informa lo sviluppatore e fermati
- Estrai: `custom_id`, `name`, `description`, `priority`, `task_id`, `url`

**Se `$ARGUMENTS` e' vuoto**:
- Usa il contesto del task gia' disponibile nella conversazione (passato dall'orchestratore)
- Se non c'e' contesto disponibile, chiedi allo sviluppatore di fornire un TASK_ID

### 2. Analizza il progetto

- Leggi `CONSTITUTION.md` per comprendere i vincoli tecnici applicabili
- Leggi `REGISTRY.md` per conoscere componenti esistenti, pattern adottati e decisioni architetturali
- Identifica i file rilevanti nel progetto in base ai requisiti del task
- Controlla `.specs/` per verificare che non esista gia' una spec per lo stesso task

### 3. Discovery (condizionale)

**Se e' presente un Discovery Summary nel contesto della conversazione** (passato dall'orchestratore `sdd` o da un'invocazione precedente di `/project:sdd-discovery`):
- Usa il Discovery Summary come base per la generazione della spec
- Non ripetere l'intervista

**Se NON e' presente un Discovery Summary**:
- Invoca `/project:sdd-discovery` passando il contesto del task
- Attendi il completamento della discovery prima di procedere alla generazione

Non procedere alla generazione finche' non e' disponibile un Discovery Summary.

### 4. Crea la directory specs

Se `.specs/` non esiste nella root del progetto:
```bash
mkdir -p .specs
```

### 5. Genera il documento spec

Crea il file `.specs/<customId>-<slug>.md` dove `<slug>` e' una versione breve e kebab-case del titolo del task.

Il documento deve seguire questo formato:

```markdown
# Spec: <Titolo Task> [<customId>]

> Status: draft
> Task: <URL del task ClickUp>
> Branch: <nome del branch, se gia' creato>
> Created: <data odierna YYYY-MM-DD>
> Approved: pending

## Contesto
<Perche' questo task esiste. Background e motivazione estratti dalla description
del task ClickUp e dall'intervista con lo sviluppatore.>

## Requisiti
<Requisiti estratti dalla description del task ClickUp, strutturati come bullet points.
Ogni requisito deve essere verificabile.>

- REQ-1: <requisito>
- REQ-2: <requisito>
- ...

## Decisioni tecniche
<Decisioni architetturali e tecniche prese per questa implementazione.
Includi: approccio scelto, pattern da usare, librerie, motivazioni.
Fai riferimento ai pattern gia' presenti in REGISTRY.md dove applicabile.>

## Impatto
- **File da creare**: <lista dei nuovi file con path relativo>
- **File da modificare**: <lista dei file esistenti da modificare con path relativo>
- **Dipendenze**: <nuove dipendenze da installare, oppure "nessuna">

## Piano di implementazione
<Sequenza ordinata di step per implementare la soluzione.
Ogni step deve essere atomico e verificabile.>

1. <Step 1> — <descrizione dettagliata>
2. <Step 2> — <descrizione dettagliata>
...

## Strategia di test
<Approccio di testing consigliato (TDD/BDD/nessuno) con motivazione.
Elenco dei test case principali da implementare.>

- Test 1: <descrizione>
- Test 2: <descrizione>
- ...

## Note
<Rischi, domande aperte, considerazioni aggiuntive, riferimenti utili.>
```

**Linee guida per la generazione**:
- I requisiti devono essere estratti fedelmente dalla description del task ClickUp
- Le decisioni tecniche devono rispettare la CONSTITUTION.md
- Il piano di implementazione deve essere ordinato per dipendenze (prima le basi, poi le feature)
- Riutilizza componenti e pattern gia' presenti in REGISTRY.md
- I test case devono coprire i requisiti elencati

### 6. Mostra la spec

Presenta la spec completa allo sviluppatore e conferma il path del file:
```
Spec generata: .specs/<customId>-<slug>.md
Status: draft

<contenuto della spec>
```

## Output atteso
- File spec creato in `.specs/<customId>-<slug>.md` con status `draft`
- Spec mostrata integralmente allo sviluppatore
