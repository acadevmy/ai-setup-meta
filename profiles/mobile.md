# Profilo: Mobile

Stack: **Flutter 3.24+** (Dart 3.4+) e **React Native** con **Expo** (SDK 51+)
State: BLoC/Riverpod (Flutter) — Zustand/Jotai (React Native)
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
- Usare `freezed` per model immutabili e union types
- Usare `json_serializable` per serializzazione — mai parsing manuale
- Ogni chiamata di rete passa per un `Repository` che implementa un'interfaccia `domain`
- Test: minimo unit test per ogni UseCase e BLoC/Notifier

### Dipendenze Flutter (pubspec.yaml)

```yaml
dependencies:
  flutter_bloc: ^8.1.0    # oppure riverpod ^2.5.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0
  dio: ^5.4.0
  get_it: ^7.7.0           # dependency injection

dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.1.0
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
    prefer_final_fields: true
    unnecessary_this: true
    use_key_in_widget_constructors: true
    always_declare_return_types: true
```

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
    "@types/jest": "^29.5.0"
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
