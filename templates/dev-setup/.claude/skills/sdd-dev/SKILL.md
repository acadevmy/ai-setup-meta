---
name: sdd-dev
description: Esegue lo sviluppo seguendo la specifica tecnica approvata, con supporto TDD/BDD o sviluppo diretto
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:sdd-dev

Esegue lo sviluppo di una feature seguendo la specifica tecnica approvata.
Supporta tre modalita': TDD (backend), BDD (frontend), o sviluppo diretto.

**Uso**: `/project:sdd-dev <SPEC_REF> [METHODOLOGY]`
- `SPEC_REF`: path della spec (es. `.specs/DE-123-add-auth.md`) o customId (es. `DE-123`)
- `METHODOLOGY` (opzionale): `tdd`, `bdd`, o `none` (default: chiede allo sviluppatore)

Esempio: `/project:sdd-dev DE-123 tdd`

## Procedura

### 1. Carica la spec

**Se `$ARGUMENTS` contiene un path**:
- Leggi il file al path indicato

**Se `$ARGUMENTS` contiene un customId**:
- Cerca in `.specs/` un file che inizi con il customId (es. `DE-123-*.md`)

Se il file non esiste, informa lo sviluppatore e fermati.

**Verifica status**: Se lo status della spec non e' `approved`, avvisa lo sviluppatore:
```
Attenzione: la spec non e' ancora approvata (status: <status>).
Vuoi procedere comunque con lo sviluppo?
```
Se lo sviluppatore non conferma, fermati.

### 2. Determina la metodologia

Se la metodologia non e' stata specificata in `$ARGUMENTS`, chiedi allo sviluppatore:
```
Metodologia di sviluppo:
1. TDD (Red-Green-Refactor) — consigliato per backend, logica di business, API, servizi
2. BDD (Given/When/Then) — consigliato per frontend, componenti UI, flussi utente
3. Nessuna — sviluppo diretto senza ciclo test-first
```

### 3. Crea il task breakdown

Parsa la sezione "Piano di implementazione" dalla spec.
Per ogni step del piano, crea un task interno con:
- Numero progressivo
- Descrizione dello step
- File coinvolti

Presenta il breakdown allo sviluppatore:
```
Task breakdown da spec:
[ ] 1. <Step 1> — <file coinvolti>
[ ] 2. <Step 2> — <file coinvolti>
...

Vuoi procedere o modificare l'ordine?
```

Attendi conferma prima di iniziare.

### 4. Esegui lo sviluppo

Per ogni step del piano, nell'ordine concordato:

1. **Annuncia** lo step corrente:
   ```
   Step <N>/<totale>: <descrizione>
   ```
2. **Leggi la documentazione** se necessario: utilizza MCP Context7 per recuperare documentazione aggiornata di librerie e framework

3. **Implementa** secondo la metodologia scelta:

   **Se TDD**:
   - **Red** — Scrivi il test che descrive il comportamento atteso
     - Usa la struttura `describe` / `it` con nomi descrittivi
     - Testa un singolo comportamento per test case
     - Il test deve fallire per la ragione giusta
   - **Green** — Implementa il minimo codice necessario per far passare il test
     - Solo il codice sufficiente a far passare il test
     - Niente ottimizzazioni premature
   - **Refactor** — Migliora il codice mantenendo i test verdi
     - Elimina duplicazione
     - Migliora i nomi
     - Applica le regole della CONSTITUTION.md

   **Se BDD**:
   - **Specifica** — Definisci gli scenari in formato Gherkin:
     ```gherkin
     Feature: <nome della feature>

       Scenario: <descrizione del comportamento>
         Given <stato iniziale>
         When <azione dell'utente>
         Then <risultato atteso>
     ```
   - **Test** — Traduci gli scenari in test eseguibili
     - Ogni `Given` prepara lo stato iniziale
     - Ogni `When` simula l'azione utente
     - Ogni `Then` verifica il risultato visibile
   - **Implementa** — Sviluppa il minimo necessario per far passare gli scenari
   - **Refactor** — Migliora il codice applicando la CONSTITUTION.md

   **Se nessuna metodologia**:
   - Implementa direttamente seguendo la spec
   - Scrivi i test dopo l'implementazione (se la strategia di test della spec lo richiede)

4. **Verifica** — Dopo ogni step, esegui test e linter:
   - **Test**:
     - Se esiste `package.json` con script `test`: `npm test`
     - Se esiste `pytest.ini` o `pyproject.toml` con `[tool.pytest]`: `pytest`
     - Se esiste `go.mod`: `go test ./...`
     - Se esiste `pubspec.yaml`: `flutter test`
     - Se esiste `Cargo.toml`: `cargo test`
     - Altrimenti: chiedi allo sviluppatore quale comando usare
   - **Linter**:
     - Se esiste `package.json` con script `lint`: `npm run lint`
     - Se esiste configurazione ruff: `ruff check .`
     - Se esiste `.golangci.yml`: `golangci-lint run`
     - Se esiste `analysis_options.yaml`: `dart analyze`
     - Se esiste `Cargo.toml`: `cargo clippy`

5. **Aggiorna** il task breakdown:
   ```
   [x] 1. <Step 1> — completato
   [x] 2. <Step 2> — completato
   [ ] 3. <Step 3> — in corso
   ...
   ```

### 5. Simplify

A completamento di tutti gli step, esegui la skill `simplify` per:
- Cercare opportunita' di riuso di codice esistente
- Migliorare qualita' e efficienza
- Correggere eventuali problemi trovati
- Se ci sono modifiche, committale: `refactor(<scope>): simplify implementation`

### 6. Riepilogo

Presenta un riepilogo di quanto implementato:
```
Sviluppo completato per spec: <customId> — <titolo>

Step completati: <N>/<totale>
Metodologia: <tdd/bdd/nessuna>
File creati: <lista>
File modificati: <lista>
Test: <esito>
Linter: <esito>
```

## Output atteso
- Codice implementato seguendo la spec approvata
- Test eseguiti e passanti
- Linter eseguito senza errori
- Codice ottimizzato via simplify
- Riepilogo dello sviluppo completato
