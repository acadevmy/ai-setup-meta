# Profile: Mobile

Stack: **Flutter 3.24+** (Dart 3.4+) and **React Native** with **Expo** (SDK 51+)
State: Riverpod (preferred) / BLoC (Flutter) — Zustand/Jotai (React Native)
Testing: flutter_test (Flutter) — Jest + React Native Testing Library (RN)

---

## Flutter

### Project structure (mandatory)

```
lib/
├── features/
│   └── <feature>/
│       ├── data/
│       │   ├── datasources/
│       │   └── repositories/
│       ├── domain/
│       │   ├── entities/
│       │   ├── repositories/  # interfaces
│       │   └── usecases/
│       └── presentation/
│           ├── bloc/          # or riverpod notifiers
│           ├── pages/
│           └── widgets/
├── core/
│   ├── error/
│   ├── network/
│   └── utils/
└── main.dart
```

### Flutter rules

> Complete rules are in the **CONSTITUTION.md** (section VIII, rules 28-37).
> Here is the operational summary for the mobile profile.

- Widgets are UI only: no business logic, no HTTP calls
- Prefer `StatelessWidget` over helper functions for reusable UI
- Use `const` constructor on every widget that allows it
- Layer separation: `presentation -> domain -> data` with dependency rule (dependencies point only inward)
- The Domain layer does not import external frameworks (no Flutter, no Dio)
- Feature-first organization: each feature contains its required layers, avoid ungoverned generic "shared" folders
- Use `freezed` for immutable models and union types
- Use `json_serializable` for serialization — never manual parsing
- `dynamic` is forbidden — use `Object` and narrowing with pattern matching
- Use `sealed class` for union types (Result, State, Event) with exhaustive switch
- Riverpod: prefer code generation with `@riverpod` and `AsyncNotifier` for async state/mutations
- Riverpod: `ref.watch()` in `build()`, `ref.read()` only in callbacks
- Avoid `setState` for shared application state; use scoped providers
- Optimize rebuilds with `const`, correct keys, small and specialized widgets
- `ListView.builder` for long lists — never `ListView(children: [...])` with many elements
- Every network call goes through a `Repository` that implements a domain interface
- Repositories return `Result<T>` (sealed) — never throw exceptions across layers
- Error handling: domain-typed exceptions, `AsyncValue` for errors in UI
- Linting: `strict-casts: true`, `strict-raw-types: true`, zero warnings in CI
- Imports: always `package:`, never relative (`../`)
- Testing: unit test for every UseCase/Notifier + widget test for screens + golden test for visual regression

### Flutter dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter_riverpod: ^2.5.0   # alternative: flutter_bloc ^8.1.0
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
  bloc_test: ^9.1.0       # if using BLoC
  freezed: ^2.5.0
  json_serializable: ^6.8.0
  build_runner: ^2.4.0
  flutter_lints: ^4.0.0
  mocktail: ^1.0.0
```

### Flutter linting configuration (analysis_options.yaml)

> Complete configuration in the **CONSTITUTION.md** (rule 35).

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    missing_return: error
    must_be_immutable: error

linter:
  rules:
    avoid_dynamic_calls: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
    prefer_final_fields: true
    prefer_final_locals: true
    unnecessary_this: true
    use_key_in_widget_constructors: true
    always_declare_return_types: true
    unawaited_futures: true
    cancel_subscriptions: true
    always_use_package_imports: true
```

### Complete Flutter workflow (ad-hoc)

1. **Bootstrap**
   - `flutter create <app_name>`
   - add dependencies (`flutter_riverpod`, `freezed_annotation`, `json_annotation`, `dio`, etc.)
2. **Codegen setup**
   - add `build_runner`, `freezed`, `json_serializable`, `riverpod_generator`
   - add `part '*.g.dart'` / `part '*.freezed.dart'` in model/provider files
3. **Architecture**
   - create features with `presentation/application/domain/data` layers
   - keep datasources in the `data` layer, not in UI
4. **State and mutations**
   - use `@riverpod` + `AsyncNotifier` for fetch/mutations
   - use `AsyncValue` in UI for `loading/data/error`
5. **Quality**
   - `dart format .`
   - `dart analyze`
   - `flutter test`
   - `dart run build_runner build --delete-conflicting-outputs`
6. **Performance**
   - validate rebuilds and frame pacing with Flutter DevTools (`flutter run --profile`)
   - introduce `ref.select` where granular subscriptions are needed

### Data validation in Flutter

- For Flutter **do not use Zod**.
- Use:
  - `freezed` for immutable data contracts and union states
  - `json_serializable` for typed serialization
  - input validation at the domain/use-case level (value objects, guard clauses)

---

## React Native (Expo)

### Project structure

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

### React Native dependencies

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

### React Native rules

- Expo managed workflow — migrate to bare only if documented and approved
- Use Expo Router for navigation
- Every screen has a test with `@testing-library/react-native`
- Network logic lives in custom hooks or TanStack Query — never in components

---

## Additional slash commands (both frameworks)

- `/project:new-screen` — scaffolds a screen with tests (Flutter or RN)
- `/project:new-feature` — scaffolds a complete feature with layer structure
