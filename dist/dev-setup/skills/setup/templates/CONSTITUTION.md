# CONSTITUTION.md

> Technical governance document. These rules apply to **all code produced
> by the team**, whether written by a human developer or an AI agent.
> No exceptions are allowed without an approved PR that modifies this file.

---

## I. Core Principles

### 1. Schema-first
Every external datum (API response, form input, env variable, public function parameter)
**must** be validated with **Zod** before being used.

```typescript
// ✅ Correct
const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  role: z.enum(['admin', 'developer', 'viewer']),
});
type User = z.infer<typeof UserSchema>;

// ❌ Forbidden — unvalidated cast
const user = response.data as User;
```

### 2. TypeScript strict — zero `any`
The `strict: true` flag is mandatory in every `tsconfig.json`.
The use of `any` is **forbidden** — use `unknown` and explicit narrowing.

```typescript
// ✅ Correct
function parsePayload(raw: unknown): ParsedPayload {
  return PayloadSchema.parse(raw);
}

// ❌ Forbidden
function parsePayload(raw: any): any { ... }
```

### 3. Explicit error handling
Do not use empty `try/catch` blocks. Every error must be:
- Logged with sufficient context
- Handled (fallback, retry, or typed propagation)
- Never silenced

```typescript
// ✅ Correct
try {
  const result = await fetchUser(id);
  return result;
} catch (error) {
  // Error fetching user: logging the id for debug purposes
  logger.error('fetchUser failed', { userId: id, error });
  throw new AppError('USER_NOT_FOUND', { cause: error });
}

// ❌ Forbidden
try {
  const result = await fetchUser(id);
  return result;
} catch (_) {}
```

### 4. Pure and small functions
- A function does **one thing only**
- Maximum length: **40 lines** (excluding comments)
- No hidden side effects in pure functions
- If a function exceeds 40 lines, it must be decomposed

### 5. Clean Code
- **DRY**: do not duplicate logic — extract shared behavior into functions or modules
- **KISS**: prefer the simplest solution that works; readability beats cleverness
- **No premature abstractions**: do not extract helpers, interfaces or generics for single-use code.
  Wait for the second concrete use before abstracting
- **No unrequested flexibility**: do not add configuration options, feature flags or extension
  points that were not asked for. Hypothetical future needs are not a requirement
- **No defensive code for impossible cases**: validate at system boundaries (external input, APIs).
  Do not add guards for conditions that cannot occur given the surrounding code
- **Boy Scout Rule (scoped)**: within a file you are already editing, fix trivial decay you
  encounter (unused imports, obvious typos in comments, dead local variables). Do **not** refactor
  adjacent code, rename symbols, or restyle unrelated sections as a side effect — surgical changes
  always win over spontaneous cleanup. Larger cleanup requires its own PR

### 6. No magic numbers or magic strings
Every constant value must have a meaningful name.

```typescript
// ✅ Correct
const MAX_RETRY_ATTEMPTS = 3;
const API_TIMEOUT_MS = 5_000;

// ❌ Forbidden
await retry(fn, 3);
setTimeout(fn, 5000);
```

---

## II. Structure and Architecture

### 7. Layer separation
```
Controller / Route handler  →  request parsing only + service call
Service                     →  business logic
Repository                  →  data access
```
Layers must not be skipped. A controller never accesses the database directly.

### 8. Dependency Injection
Use DI (native NestJS, or manual for pure Node projects).
Never instantiate heavy dependencies with `new` inside functions.

### 9. SOLID principles
- **Single Responsibility**: each class/module has one reason to change
- **Open/Closed**: extend behavior via composition or abstraction, not by modifying existing code
- **Liskov Substitution**: subtypes must be usable in place of their base type without breaking behavior
- **Interface Segregation**: prefer small, focused interfaces over large general-purpose ones
- **Dependency Inversion**: depend on abstractions, not on concrete implementations

### 10. Descriptive names
- Variables and functions: `camelCase`, descriptive, in English
- Classes and types: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Files: `kebab-case.ts`
- Avoid non-universal abbreviations (`usr`, `btn`, `mgr`)

---

## III. Testing

### 11. Testing methodology

The methodology varies by layer:

#### Backend (logic, API, services) — TDD
For every new feature or bugfix:
1. Write the test that describes the expected behavior
2. Verify it fails (red)
3. Implement the minimum code to make it pass (green)
4. Refactoring (refactor)

#### Frontend (components, pages, user flows) — BDD
For every new feature or bugfix:
1. Define scenarios in natural language (Given/When/Then)
2. Translate scenarios into executable tests
3. Implement the code to make scenarios pass
4. Refactoring

### 12. Minimum coverage
| Layer | Minimum coverage |
|---|---|
| Services / Business logic | 80% |
| Utilities / helpers | 90% |
| Controllers | 60% (integration test) |
| UI components | 70% (with Testing Library) |

### 13. Test structure

#### Backend — TDD
```typescript
describe('UserService', () => {
  describe('createUser', () => {
    it('should create a user with a valid email', async () => { ... });
    it('should throw ValidationError if email is invalid', async () => { ... });
    it('should throw ConflictError if email already exists', async () => { ... });
  });
});
```

#### Frontend — BDD
```gherkin
Feature: User login

  Scenario: Login with valid credentials
    Given the user is on the login page
    When they enter a valid email and password
    And click the "Sign In" button
    Then they are redirected to the dashboard
```

---

## IV. Git and Workflow

### 14. Conventional Commits (mandatory)
```
<type>(<scope>): <description in English, imperative, lowercase>

[optional body]

[optional footer: BREAKING CHANGE, closes #issue]
```

Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`

```
feat(auth): add refresh token rotation
fix(api): handle 429 rate limit response correctly
chore(deps): upgrade zod to 3.23
```

### 15. Branch naming
```
feat/<customId>-<short-description>
fix/<customId>-<short-description>
chore/<customId>-<short-description>
hotfix/<customId>-<short-description>
```
The `customId` is the ClickUp task identifier (e.g. `DE-123`).
If the branch is not associated with a ClickUp task, omit the customId.

### 16. Pull Request
- Title: follows Conventional Commits
- Minimum description: **What**, **Why**, **How to test**
- The PR cannot be merged if tests fail
- The PR cannot be merged if ESLint reports errors
- At least **1 review** required before merge

### 17. Atomic commits
One commit = one coherent logical change.
Do not commit half-finished work, temporary debug code, or forgotten `console.log` statements.

---

## V. Security

### 18. Zero secrets in code
- API keys, tokens, passwords: **only in environment variables**
- `.env` file **not tracked** by git (verify `.gitignore`)
- Always provide a `.env.example` with variable names but without values

### 19. Input validation
Every external input is potentially malicious. Always validate with Zod,
sanitize before using in queries or template strings.

### 20. Dependency audit
```bash
npm audit
```
Run on every dependency addition. Do not add packages with known vulnerabilities
at `high` or `critical` level without explicit approval.

---

## VI. Frontend (Next.js / Angular / React)

### 21. Small and reusable components
- A component does **one thing only**
- Props typed with TypeScript (no `any`, no casts)
- No business logic in the component — delegate to hooks or services

### 22. ShadCN/UI as the base
UI components are built **on top of** ShadCN/UI, not from scratch.
Modifications to ShadCN components happen in the customization layer,
not directly in the generated files.

### 23. Tailwind — utility-first, no custom CSS
- Use Tailwind classes
- Avoid custom CSS files unless strictly necessary
- Variants and themes: via `tailwind.config.ts`, not inline

---

## VII. Frontend (Nuxt 3 / Vue 3)

### 24. Composition API only
- `<script setup lang="ts">` è obbligatorio — no Options API
- Props e emits tipizzati con `defineProps<T>()` e `defineEmits<E>()`
- No business logic nel template — estrai in composables (`composables/useXxx.ts`)

### 25. Data fetching with `useFetch` / `useAsyncData`
- Usa `useFetch` / `useAsyncData` / `$fetch` — **mai** fetch dentro `onMounted` o `watch`
- Fornisci una `key` esplicita quando il fetch è condizionale o parametrizzato
- Non chiamare backend esterni direttamente dai componenti — passa sempre da `server/api/*`
  (proxy con validazione Zod lato server)

### 26. Global state with Pinia
- Stato condiviso solo in Pinia stores (`stores/*.ts`), registrati via `@pinia/nuxt`
- No `provide/inject` ad-hoc per stato condiviso tra componenti distanti
- Getters e actions con tipi di ritorno espliciti — nessun `any` implicito

### 27. SSR awareness and Nuxt auto-imports
- Il default è SSR: gatta ogni API browser-only con `import.meta.client` o `<ClientOnly>`
- Componenti multi-word (`UserCard.vue`, non `Card.vue`) per evitare conflitti con elementi HTML
- Auto-imports di Nuxt attivi: non importare manualmente `ref`, `computed`, `useRoute`,
  `useFetch`, `navigateTo`, ecc.
- Per i test usa `@nuxt/test-utils` (`environment: 'nuxt'` in Vitest) in modo che gli
  auto-imports funzionino

---

## VIII. Mobile (Flutter / React Native)

### 28. Flutter — Widget composition
- Widgets: UI and interactions only — no business logic, no HTTP calls
- Prefer `StatelessWidget` over helper functions for reusable UI pieces
  (functions do not participate in the widget lifecycle)
- Use `const` constructor on every widget that allows it — Flutter skips the rebuild
- Keep widgets small and focused: decompose `build()` into sub-widgets
  based on what changes independently
- Use explicit `Key`s (`ValueKey`, `ObjectKey`) for lists, reorderable elements,
  and widgets with local state
- Do not use `setState()` for shared application state — only for state
  strictly local to the widget

### 29. Flutter — state management
- Choose **one** pattern per project and stick with it: Riverpod (preferred) or BLoC
- Riverpod: use `ref.watch()` in `build()`, `ref.read()` only in callbacks
- Riverpod: prefer `@riverpod` code generation and `AsyncNotifier` for async state
- Use `AsyncValue` (`when`, `guard`) for loading/error/data states — never manually track
  `isLoading`/`hasError` booleans
- Prefer `ConsumerWidget`/`ConsumerStatefulWidget` when the entire widget
  depends on a provider
- State passed through providers **must** be immutable — never mutate
  in-place, always return a new instance

### 30. Dart — type safety
`dynamic` is **forbidden** — like `any` in TypeScript. Use `Object` and narrowing.

```dart
// ✅ Correct
sealed class AuthState {}
class Authenticated extends AuthState {
  final User user;
  Authenticated(this.user);
}
class Unauthenticated extends AuthState {}

final message = switch (state) {
  Authenticated(:final user) => 'Hello ${user.name}',
  Unauthenticated() => 'Not authenticated',
};

// ❌ Forbidden
dynamic result = fetchData();
final user = response as User; // unsafe cast
```

- Enable `strict-casts: true` and `strict-raw-types: true` in `analysis_options.yaml`
- Use `sealed class` for union types and complex enumerations — guarantees
  exhaustive check in `switch`
- Use pattern matching (`switch` expression with destructuring) instead of
  `if/else` chains or `is` checks
- Avoid `as` casts — prefer `case` pattern or `is` check with promotion
- Use class modifiers with intention: `final` for non-extendable classes,
  `sealed` for closed hierarchies, `base` for extension-only classes

### 31. Flutter — immutability
- All models and state classes **must** be immutable:
  `final` fields + `const` constructor
- Annotate with `@immutable` (from `package:meta`) all value objects and state classes
- Use `freezed` for data classes — provides `copyWith`, `==`, `hashCode`, `toString`,
  JSON serialization
- Use `json_serializable` for typed serialization — never manual parsing
- Prefer `final` for local variables (lint `prefer_final_locals`)
- Use `const` wherever possible: constructors, collections, values

### 32. Flutter — architecture
Three mandatory layers with **dependency rule** (dependencies point only inward):

```
Presentation (widget + provider/controller)
     ↓
Domain (entity + use case + repository interfaces)
     ↑
Data (repository implementations + data source + DTO)
```

- The Domain layer has **no** framework imports (no Flutter, no Dio, no external packages)
- Each UseCase encapsulates a single business operation with a `call()` or `execute()` method
- DTOs are separate from domain entities — mapping occurs at the Data layer boundary
- Mandatory feature-first structure:
  ```
  lib/
  ├── features/
  │   └── <feature>/
  │       ├── data/           # repository impl, datasource, DTO
  │       ├── domain/         # entity, use case, repository interfaces
  │       └── presentation/   # widget, provider/bloc, page
  ├── core/                   # shared utilities, theme, routing
  └── main.dart
  ```

### 33. Flutter — performance
- No heavy work in `build()` — no I/O, no expensive computations
- Use `const` widgets aggressively — Flutter skips rebuilds of const instances
- Use `ListView.builder` / `GridView.builder` for long lists — never
  `ListView(children: [...])` with many elements
- Use `RepaintBoundary` to isolate subtrees that repaint frequently
  (animations, scroll indicators)
- Do not use `Opacity` to hide widgets — use `Visibility` or conditional rendering
- Profile with Flutter DevTools (`flutter run --profile`) before optimizing —
  measure, don't guess

### 34. Flutter — error handling
- Use the `sealed class Result<T>` pattern with `Success<T>` and `Failure<T>` subtypes
  for domain layer operations

```dart
// ✅ Correct
sealed class Result<T> {
  const Result();
}
class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}
class Failure<T> extends Result<T> {
  final AppException exception;
  const Failure(this.exception);
}

// In the repository:
Future<Result<User>> getUser(String id);
```

- Repository methods return `Result<T>` — never throw exceptions
  across layer boundaries
- Define domain-typed exceptions (`AuthException`, `NetworkException`)
- Do not catch generic `Exception` or `Object` without specific handling
- Use `AsyncValue` in Riverpod to propagate error states to the UI
- Always handle all branches in pattern matching on sealed error types —
  no `default` that swallows errors

### 35. Flutter — linting and static analysis
Minimum mandatory configuration in `analysis_options.yaml`:

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
```

- **Zero warnings in CI**: static analysis (`dart analyze`) must pass without warnings
- Always use `package:` imports — never relative imports (`../`)

### 36. Flutter — testing
Test pyramid: many unit > widget tests > few integration tests.

| Layer | Minimum coverage | Tool |
|---|---|---|
| UseCase / Notifier | 80% | `flutter_test` + `mocktail` |
| Repository | 80% | `flutter_test` + `mocktail` |
| Screen / Widget | 70% | `flutter_test` + `WidgetTester` |
| Critical flows | E2E | `integration_test` |

- Unit tests for every UseCase and Notifier — test logic in isolation
- Widget tests for every screen and reusable component — use `pumpWidget` + `find` + `expect`
- Golden tests for visual regression on design-critical widgets (`matchesGoldenFile`)
- Use `mocktail` for mocking external dependencies (repositories, APIs)
- Test file naming: `<source_file>_test.dart` in a `test/` structure mirroring `lib/`
- Every test must be independent — no shared mutable state between tests

### 37. Dart — naming and file organization
- Files: `snake_case.dart` (e.g. `user_repository.dart`, `auth_provider.dart`)
- Directories: `snake_case` (e.g. `data_sources/`, `use_cases/`)
- One public class per file (exception: tightly coupled types such as sealed class + subtypes)
- The file name matches the main class: `UserRepository` → `user_repository.dart`
- Imports: always `package:`, never relative (`../`)
- Import order: `dart:` → `package:` → relative (enforced by lint `directives_ordering`)

### 38. React Native — Expo as baseline
- Always start from the Expo managed workflow
- Migrate to bare workflow only if necessary and documented
- Use Expo Router for navigation
- Network logic in custom hooks or TanStack Query — never in components

---

## IX. AI Agent

### 39. The agent follows this Constitution
Claude Code and any other AI agent **must** comply with these rules exactly
as a human developer would. No exceptions exist for "simplicity" or "speed".

### 40. The agent does not bypass hooks
Git hooks (lint, test) also apply to commits suggested by the agent.
Never use `--no-verify`.

### 41. The agent does not modify this file autonomously
Changes to `CONSTITUTION.md` require a PR with explicit human approval.

---

*Version: 1.2.0*
*Updated: 2026-04*
*Next planned review: 2026-07*
