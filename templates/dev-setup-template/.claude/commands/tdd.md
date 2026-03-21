# /project:tdd

Avvia un ciclo TDD per la feature o il bugfix descritto dall'utente.

## Procedura

1. **Red** — Scrivi il test che descrive il comportamento atteso
   - Usa la struttura `describe` / `it` con nomi descrittivi
   - Il test deve fallire per la ragione giusta

2. **Green** — Implementa il minimo codice necessario
   - Solo il codice sufficiente a far passare il test
   - Niente ottimizzazioni premature

3. **Refactor** — Migliora il codice mantenendo i test verdi
   - Elimina duplicazione
   - Migliora i nomi
   - Applica le regole della CONSTITUTION.md

4. **Verifica finale**
   - Esegui tutti i test: `npm test`
   - Esegui il linter: `npm run lint`

## Input atteso
Descrizione della feature o del bug da risolvere: $ARGUMENTS
