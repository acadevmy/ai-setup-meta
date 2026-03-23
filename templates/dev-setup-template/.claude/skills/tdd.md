---
name: tdd
description: Avvia un ciclo TDD (Red-Green-Refactor) per sviluppo backend (logica, API, servizi)
model: opus
user-invocable: true
disable-model-invocation: false
---

# /project:tdd

Avvia un ciclo TDD classico per la feature o il bugfix descritto dall'utente.
Questa metodologia è pensata per lo sviluppo **backend**: logica di business, API, servizi, data layer.

## Procedura

1. **Red** — Scrivi il test che descrive il comportamento atteso
   - Usa la struttura `describe` / `it` con nomi descrittivi
   - Testa un singolo comportamento per test case
   - Il test deve fallire per la ragione giusta

2. **Green** — Implementa il minimo codice necessario
   - Solo il codice sufficiente a far passare il test
   - Niente ottimizzazioni premature

3. **Refactor** — Migliora il codice mantenendo i test verdi
   - Elimina duplicazione
   - Migliora i nomi
   - Applica le regole della CONSTITUTION.md

4. **Ripeti** — Passa al prossimo comportamento
   - Un ciclo Red-Green-Refactor per ogni comportamento
   - Procedi dal caso più semplice al più complesso

5. **Verifica finale**
   - Esegui i test del progetto:
     - Se esiste `package.json` con script `test`: `npm test`
     - Se esiste `pytest.ini` o `pyproject.toml` con `[tool.pytest]`: `pytest`
     - Se esiste `go.mod`: `go test ./...`
     - Se esiste `pubspec.yaml`: `flutter test` (per package Dart backend)
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
