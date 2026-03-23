---
name: bdd
description: Avvia un ciclo BDD (Given/When/Then) per sviluppo frontend (componenti, pagine, flussi utente)
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:bdd

Avvia un ciclo BDD per la feature o il bugfix descritto dall'utente.
Questa metodologia è pensata per lo sviluppo **frontend**: componenti UI, pagine, flussi utente.

## Procedura

1. **Specifica** — Definisci gli scenari in linguaggio naturale
   - Scrivi uno o più scenari usando il formato Gherkin:
     ```gherkin
     Feature: <nome della feature>

       Scenario: <descrizione del comportamento>
         Given <stato iniziale>
         When <azione dell'utente>
         Then <risultato atteso>
     ```
   - Usa `And` per aggiungere passi aggiuntivi
   - Usa `Scenario Outline` con `Examples` per varianti parametriche
   - Presenta gli scenari allo sviluppatore per conferma prima di procedere

2. **Implementa i test** — Traduci gli scenari in test eseguibili
   - Ogni `Given` prepara lo stato iniziale (render del componente, mock dei dati)
   - Ogni `When` simula l'azione utente (click, input, navigazione)
   - Ogni `Then` verifica il risultato visibile all'utente
   - Mantieni i nomi dei test allineati agli scenari Gherkin

3. **Implementa il codice** — Sviluppa il minimo necessario
   - Implementa componenti e logica per far passare gli scenari
   - Concentrati sul comportamento visibile all'utente, non sui dettagli implementativi

4. **Refactor** — Migliora il codice mantenendo gli scenari verdi
   - Estrai componenti riutilizzabili
   - Migliora i nomi
   - Applica le regole della CONSTITUTION.md

5. **Verifica finale**
   - Esegui i test del progetto:
     - Se esiste `package.json` con script `test`: `npm test`
     - Se esiste `pubspec.yaml`: `flutter test`
     - Altrimenti: chiedi allo sviluppatore quale comando usare
   - Esegui il linter del progetto (se configurato):
     - Se esiste `package.json` con script `lint`: `npm run lint`
     - Se esiste `analysis_options.yaml`: `dart analyze`

## Input atteso
Descrizione della feature o del bug da risolvere: $ARGUMENTS
