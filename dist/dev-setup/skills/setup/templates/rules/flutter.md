---
paths:
  - "**/*.dart"
---

# Flutter / Dart

## Type safety

`dynamic` is the Dart `any`: use `Object?` and narrow. `analysis_options.yaml`
turns on `strict-casts` and `strict-raw-types`, so the analyzer catches most of
it, and `avoid_dynamic_calls` catches the rest.

Closed hierarchies are `sealed`, which makes the `switch` exhaustive and removes
the `default` branch that would otherwise swallow a new case:

```dart
sealed class AuthState {}
class Authenticated extends AuthState {
  final User user;
  const Authenticated(this.user);
}
class Unauthenticated extends AuthState {}

final message = switch (state) {
  Authenticated(:final user) => 'Hello ${user.name}',
  Unauthenticated() => 'Not authenticated',
};
```

Prefer pattern matching over `if/else` chains and `is` checks; prefer a `case`
pattern over an `as` cast. Class modifiers say what a type is for: `final` for
non-extendable, `sealed` for closed, `base` for extension-only.

## Immutability

Models and state classes are immutable — `final` fields, `const` constructor,
`@immutable` from `package:meta`. `freezed` generates `copyWith`, `==`,
`hashCode` and `toString`; `json_serializable` generates the parsing. Hand-written
`fromJson` drifts from the model within two sprints.

State that travels through a provider is never mutated in place; you return a new
instance. Local variables are `final` (`prefer_final_locals`), and `const` goes
everywhere it is accepted.

## Widgets

- UI and interaction only. No HTTP call, no business rule, no I/O in `build()`.
- A reusable piece is a `StatelessWidget`, not a helper function — a function has
  no place in the widget lifecycle and cannot be `const`.
- `const` constructors let Flutter skip the rebuild entirely. Use them.
- Decompose `build()` by what changes independently, not by line count.
- Explicit `Key`s (`ValueKey`, `ObjectKey`) on list items, reorderable elements
  and anything carrying local state.
- `setState()` is for state strictly local to the widget. Shared state goes
  through the state manager.

## State management

One pattern per project — Riverpod preferred, BLoC accepted — and it does not
change halfway through. With Riverpod: `ref.watch()` in `build()`, `ref.read()`
only inside callbacks; `@riverpod` code generation with `AsyncNotifier` for async
state; `AsyncValue` (`when`, `guard`) instead of hand-tracked `isLoading` and
`hasError` booleans. Reach for `ConsumerWidget` / `ConsumerStatefulWidget` when
the whole widget depends on a provider.

## Architecture

Three layers, dependencies pointing inward:

```
Presentation (widget + provider/controller)
     ↓
Domain (entity + use case + repository interfaces)
     ↑
Data (repository implementations + data source + DTO)
```

Domain imports no framework — not Flutter, not Dio, not a package. A UseCase is
one business operation with a `call()` or `execute()`. DTOs are separate from
entities and map at the Data boundary.

```
lib/
├── features/<feature>/{data,domain,presentation}/
├── core/                   # shared utilities, theme, routing
└── main.dart
```

## Errors

Repositories return `Result<T>` instead of throwing across a layer boundary:

```dart
sealed class Result<T> { const Result(); }
class Success<T> extends Result<T> { final T data; const Success(this.data); }
class Failure<T> extends Result<T> { final AppException exception; const Failure(this.exception); }

Future<Result<User>> getUser(String id);
```

Exceptions are domain-typed (`AuthException`, `NetworkException`). Catching bare
`Exception` or `Object` without doing something specific with it hides the bug.
Riverpod's `AsyncValue` carries the error state to the UI; every branch of a
match on a sealed error type is handled.

## Performance

`ListView.builder` / `GridView.builder` for anything long — never a `ListView`
with a materialised `children` list. `RepaintBoundary` around subtrees that
repaint on their own (animations, scroll indicators). `Visibility` or a
conditional, not `Opacity`, to hide a widget. Profile with DevTools
(`flutter run --profile`) before optimising: measure, do not guess.

## Analyzer

`dart analyze` runs clean — zero warnings, not "zero errors". The baseline lives
in `analysis_options.yaml`:

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
    always_declare_return_types: true
    unawaited_futures: true
    cancel_subscriptions: true
    always_use_package_imports: true
    use_key_in_widget_constructors: true
    directives_ordering: true
```

## Files and imports

Files and directories are `snake_case`; the file is named after its main class
(`UserRepository` → `user_repository.dart`). One public class per file, the
exception being a sealed class with its subtypes. Imports are always `package:`,
never relative — `directives_ordering` keeps `dart:` before `package:`.
