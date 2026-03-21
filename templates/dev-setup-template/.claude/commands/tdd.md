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
   - Esegui i test del progetto:
     - Se esiste `package.json` con script `test`: `npm test`
     - Se esiste `pytest.ini` o `pyproject.toml` con `[tool.pytest]`: `pytest`
     - Se esiste `go.mod`: `go test ./...`
     - Se esiste `pubspec.yaml`: `flutter test`
     - Se esiste `Cargo.toml`: `cargo test`
     - Altrimenti: chiedi allo sviluppatore quale comando usare
   - Esegui il linter del progetto (se configurato):
     - Se esiste `package.json` con script `lint`: `npm run lint`
     - Se esiste configurazione ruff: `ruff check .`
     - Se esiste `.golangci.yml`: `golangci-lint run`
     - Se esiste `analysis_options.yaml`: `dart analyze`
     - Se esiste `Cargo.toml`: `cargo clippy`

## Input atteso
Descrizione della feature o del bug da risolvere: $ARGUMENTS
