# Profile: Mobile

Stack: **Flutter 3.47+** (Dart 3.13+) and **React Native** with **Expo** (SDK 57+)
State: Riverpod (preferred) / BLoC (Flutter) — Zustand/Jotai (React Native)
Testing: flutter_test (Flutter) — Jest + React Native Testing Library (RN)

> Versions verified on pub.dev and npm on 2026-09-08. When bumping them,
> re-check the peer ranges: they are the constraint that decides whether the
> install succeeds on the first try.

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
  flutter_riverpod: ^3.4.0   # alternative: flutter_bloc ^9.1.0
  riverpod_annotation: ^4.0.0
  freezed_annotation: ^3.1.0
  json_annotation: ^4.12.0
  dio: ^5.11.0
  go_router: ^18.0.0
  get_it: ^9.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^4.0.0
  custom_lint: ^0.8.0
  riverpod_lint: ^3.1.0
  bloc_test: ^10.0.0      # if using BLoC
  freezed: ^4.0.0
  json_serializable: ^6.14.0
  build_runner: ^2.16.0
  flutter_lints: ^6.0.0
  mocktail: ^1.0.5
```

Riverpod 3 and freezed 4 are **breaking majors** over the 2.x this profile used
to declare: on an existing project do not raise the pins inside an unrelated PR
(CONSTITUTION §50, scoped Boy Scout Rule). `flutter_riverpod` 3.x pairs with
`riverpod_annotation`/`riverpod_generator` 4.x and `riverpod_lint` 3.x — the
three numbers differ by upstream choice, not by mistake.

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
   - create features with the three layers `presentation/domain/data`
     (CONSTITUTION §32 — dependency rule: dependencies point only inward)
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
    "expo": "~57.0.0",
    "expo-router": "~57.0.0",
    "react": "^19.2.0",
    "react-native": "^0.87.0",
    "zod": "^4.5.0",
    "zustand": "^5.0.0",
    "@tanstack/react-query": "^5.102.0"
  },
  "devDependencies": {
    "typescript": "^5.9.3",
    "eslint": "^9.39.0",
    "eslint-config-expo": "^57.0.0",
    "typescript-eslint": "^8.70.0",
    "@eslint/js": "^9.39.0",
    "globals": "^17.12.0",
    "prettier": "^3.9.0",
    "prettier-plugin-tailwindcss": "^0.8.0",
    "jest": "^30.5.0",
    "jest-expo": "~57.0.0",
    "@testing-library/react-native": "^14.0.0",
    "@types/jest": "^30.0.0",
    "semantic-release": "^25.0.0",
    "@semantic-release/changelog": "^7.0.0",
    "@semantic-release/git": "^11.0.0",
    "@semantic-release/npm": "^13.1.0",
    "@semantic-release/github": "^12.0.0",
    "@semantic-release/gitlab": "^13.3.0",
    "conventional-changelog-conventionalcommits": "^10.4.0"
  }
}
```

**Notes on the pins**

- `react-query` **does not exist** past 3.x: the package has been called
  `@tanstack/react-query` since 2022. This profile's old `react-query: ^5.0.0`
  was unresolvable and made the install fail.
- `expo`, `expo-router` and `jest-expo` track the SDK number and must be raised
  together (`npx expo install --fix` realigns them).
- `eslint` stays on **9.x** for the same reason as the web-frontend profile
  (the React plugins' peer ceiling).
- Of the two VCS-specific semantic-release plugins keep **only the one for your provider**.

### ESLint (flat config)

```javascript
// eslint.config.mjs
import expoConfig from 'eslint-config-expo/flat.js';

import base from './eslint.config.base.mjs';

const config = [...base, ...expoConfig];

export default config;
```

### Jest

The config is `jest.config.mjs` (with `jest.config.ts` Jest demands `ts-node`)
and uses the `jest-expo` preset:

```javascript
// jest.config.mjs
export default {
  preset: 'jest-expo',
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  // Without collectCoverageFrom the threshold is computed only over files the
  // tests touch, and CONSTITUTION §12 gates nothing.
  collectCoverageFrom: ['src/**/*.{ts,tsx}', '!src/**/*.spec.{ts,tsx}', '!src/**/*.d.ts'],
  coverageThreshold: { global: { lines: 70, functions: 70, branches: 60 } },
};
```

### React Native rules

- Expo managed workflow — migrate to bare only if documented and approved
- Use Expo Router for navigation
- Every screen has a test with `@testing-library/react-native`
- Network logic lives in custom hooks or TanStack Query — never in components
