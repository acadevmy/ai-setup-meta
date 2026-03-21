# /project:sync-task

Sincronizza il contesto di un task ClickUp con il branch corrente.

## Procedura

1. **Recupera il task**
   - Usa il MCP ClickUp per recuperare i dettagli del task
   - Leggi titolo, descrizione, acceptance criteria, e allegati

2. **Analizza il contesto**
   - Identifica i file rilevanti nel progetto
   - Mappa i requisiti del task alle aree del codice

3. **Suggerisci piano di implementazione**
   - Elenca i file da creare o modificare
   - Proponi l'ordine di implementazione seguendo TDD
   - Identifica eventuali dipendenze o blocchi

## Input atteso
ID del task ClickUp o URL: $ARGUMENTS
