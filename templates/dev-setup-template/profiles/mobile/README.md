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
│           ├── bloc/
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

### Regole React Native

- Expo managed workflow — migrare a bare solo se documentato e approvato
- Usare Expo Router per la navigazione
- Ogni screen ha un test con `@testing-library/react-native`
- La logica di rete vive in hook personalizzati o TanStack Query — mai nei componenti

## File di configurazione inclusi

- `analysis_options.yaml` — regole linting Flutter
