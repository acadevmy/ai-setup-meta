---
name: sync-task
description: Sincronizza il contesto di un task ClickUp con il branch corrente
model: sonnet
user-invocable: true
disable-model-invocation: true
---

# /project:sync-task

Sincronizza il contesto di un task ClickUp con il branch corrente tramite il ClickUp Agent.

## Procedura

### 1. Recupera il task tramite ClickUp Agent

Lancia l'agent `clickup` con:
- INTENT: `read`
- PARAMS: `task_id: <$ARGUMENTS>`

Se l'agent restituisce STATUS: error, informa lo sviluppatore e fermati.

Dall'output, estrai tutti i campi del task. La description e' riportata integralmente dall'agent — usala come riferimento completo per il piano di implementazione.

### 2. Analizza il contesto

- Identifica i file rilevanti nel progetto
- Mappa i requisiti del task (dalla description integrale) alle aree del codice

### 3. Suggerisci piano di implementazione

- Elenca i file da creare o modificare
- Proponi l'ordine di implementazione seguendo TDD
- Identifica eventuali dipendenze o blocchi

## Input atteso
ID del task ClickUp o URL: $ARGUMENTS
