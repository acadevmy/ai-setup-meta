# Profilo: Mobile

Stack: **Flutter 3.24+** (Dart 3.4+) e **React Native** con **Expo** (SDK 51+)
State: Riverpod (preferito) / BLoC (Flutter) — Zustand/Jotai (React Native)
Testing: flutter_test (Flutter) — Jest + React Native Testing Library (RN)

---

## Flutter

### Struttura progetto (obbligatoria)

```
lib/
├── features/
│   └── <feature>/
│       ├── data/
│       │   ├── datasources/
│       │   └── repositories/
│       ├── domain/
│       │   ├── entities/
│       │   ├── repositories/  # interfacce
│       │   └── usecases/
│       └── presentation/
│           ├── bloc/          # o riverpod notifiers
│           ├── pages/
│           └── widgets/
├── core/
│   ├── error/
│   ├── network/
│   └── utils/
└── main.dart
```

### Regole Flutter

- Widget solo UI: nessuna logica di business, nessuna chiamata HTTP
- Separazione layer: `presentation -> application -> domain -> data` con repository come gateway ai datasource
- Organizzazione feature-first: ogni feature contiene i layer necessari, evitare cartelle generiche "shared" non governate
- Usare `freezed` per model immutabili e union types
- Usare `json_serializable` per serializzazione — mai parsing manuale
- Riverpod: preferire code generation con `@riverpod` e `AsyncNotifier` per stato async/mutazioni
- Evitare `setState` per stato applicativo condiviso; usare provider scoped e `ref.watch/ref.read/ref.listen/ref.select`
- Ottimizzare rebuild con `const`, key corrette, widget piccoli e specializzati
- Ogni chiamata di rete passa per un `Repository` che implementa un'interfaccia `domain`
- Test: minimo unit test per ogni UseCase/Notifier + widget test per screen critiche

### Dipendenze Flutter (pubspec.yaml)

```yaml
dependencies:
  flutter_riverpod: ^2.5.0   # alternativa: flutter_bloc ^8.1.0
  riverpod_annotation: ^2.3.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0
  dio: ^5.4.0
  go_router: ^14.0.0
  get_it: ^7.7.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.4.0
  custom_lint: ^0.6.0
  riverpod_lint: ^2.3.0
  bloc_test: ^9.1.0       # se si usa BLoC
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  build_runner: ^2.4.0
  flutter_lints: ^4.0.0
  mocktail: ^1.0.0
```

### Configurazione linting Flutter (analysis_options.yaml)

```yaml
include: package:flutter_lints/flutter.yaml
linter:
  rules:
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
    prefer_final_fields: true
    unnecessary_this: true
    use_key_in_widget_constructors: true
    always_declare_return_types: true
```

### Flusso completo Flutter (ad-hoc)

1. **Bootstrap**
   - `flutter create <app_name>`
   - aggiungere dipendenze (`flutter_riverpod`, `freezed_annotation`, `json_annotation`, `dio`, ecc.)
2. **Codegen setup**
   - aggiungere `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`
   - aggiungere `part '*.g.dart'` / `part '*.freezed.dart'` nei file modello/provider
3. **Architettura**
   - creare feature con layer `presentation/application/domain/data`
   - mantenere i datasource nel layer `data` e non in UI
4. **Stato e mutazioni**
   - usare `@riverpod` + `AsyncNotifier` per fetch/mutazioni
   - usare `AsyncValue` in UI per `loading/data/error`
5. **Qualita'**
   - `dart format .`
   - `dart analyze`
   - `flutter test`
   - `dart run build_runner build --delete-conflicting-outputs`
6. **Performance**
   - validare rebuild e frame pacing con Flutter DevTools (`flutter run --profile`)
   - introdurre `ref.select` dove servono subscription granulari

### Validazione dati in Flutter

- Per Flutter **non usare Zod**.
- Usare:
  - `freezed` per contratti dati immutabili e union state
  - `json_serializable` per serializzazione tipizzata
  - validazione input a livello domain/use-case (oggetti valore, guard clauses)

---

## React Native (Expo)

### Struttura progetto

```
src/
├── features/
│   └── <feature>/
│       ├── components/
│       ├── hooks/
│       ├── screens/
│       ├── store/        # Zustand slice
│       └── __tests__/
├── shared/
│   ├── components/
│   ├── hooks/
│   └── utils/
└── app/                  # Expo Router
    └── (tabs)/
```

### Dipendenze React Native

```json
{
  "dependencies": {
    "expo": "~51.0.0",
    "expo-router": "~3.5.0",
    "zod": "^3.23.0",
    "zustand": "^4.5.0",
    "react-query": "^5.0.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "@testing-library/react-native": "^12.5.0",
    "@types/jest": "^29.5.0",
    "semantic-release": "^24.0.0",
    "@semantic-release/changelog": "^6.0.3",
    "@semantic-release/git": "^10.0.1",
    "@semantic-release/github": "^10.0.0",
    "conventional-changelog-conventionalcommits": "^8.0.0"
  }
}
```

### Regole React Native

- Expo managed workflow — migrare a bare solo se documentato e approvato
- Usare Expo Router per la navigazione
- Ogni screen ha un test con `@testing-library/react-native`
- La logica di rete vive in hook personalizzati o TanStack Query — mai nei componenti

---

## Comandi slash aggiuntivi (entrambi i framework)

- `/project:new-screen` — scaffolda schermata con test (Flutter o RN)
- `/project:new-feature` — scaffolda feature completa con struttura layer
