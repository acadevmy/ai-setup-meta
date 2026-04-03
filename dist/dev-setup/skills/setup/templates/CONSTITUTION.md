# CONSTITUTION.md

> Documento di governance tecnica. Queste regole si applicano a **tutto il codice prodotto
> dal team**, che sia scritto da uno sviluppatore umano o da un agente AI.
> Nessuna eccezione è ammessa senza una PR approvata che modifichi questo file.

---

## I. Principi fondamentali

### 1. Schema-first
Ogni dato esterno (API response, form input, env variable, parametro di funzione pubblica)
**deve** essere validato con **Zod** prima di essere usato.

```typescript
// ✅ Corretto
const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  role: z.enum(['admin', 'developer', 'viewer']),
});
type User = z.infer<typeof UserSchema>;

// ❌ Vietato — cast non validato
const user = response.data as User;
```

### 2. TypeScript strict — zero `any`
Il flag `strict: true` è obbligatorio in ogni `tsconfig.json`.
L'uso di `any` è **vietato** — usa `unknown` e narrowing esplicito.

```typescript
// ✅ Corretto
function parsePayload(raw: unknown): ParsedPayload {
  return PayloadSchema.parse(raw);
}

// ❌ Vietato
function parsePayload(raw: any): any { ... }
```

### 3. Gestione errori esplicita
Non usare `try/catch` vuoti. Ogni errore deve essere:
- Loggato con contesto sufficiente
- Gestito (fallback, retry, o propagazione tipizzata)
- Mai silenziato

```typescript
// ✅ Corretto
try {
  const result = await fetchUser(id);
  return result;
} catch (error) {
  // Errore nel recupero utente: logghiamo l'id per debug
  logger.error('fetchUser failed', { userId: id, error });
  throw new AppError('USER_NOT_FOUND', { cause: error });
}

// ❌ Vietato
try {
  const result = await fetchUser(id);
  return result;
} catch (_) {}
```

### 4. Funzioni pure e piccole
- Una funzione fa **una cosa sola**
- Lunghezza massima: **40 righe** (esclusi commenti)
- Nessun side effect nascosto nelle funzioni pure
- Se una funzione supera 40 righe, va scomposta

### 5. Nessun magic number o magic string
Ogni valore costante deve avere un nome significativo.

```typescript
// ✅ Corretto
const MAX_RETRY_ATTEMPTS = 3;
const API_TIMEOUT_MS = 5_000;

// ❌ Vietato
await retry(fn, 3);
setTimeout(fn, 5000);
```

---

## II. Struttura e architettura

### 6. Separazione dei layer
```
Controller / Route handler  →  solo parsing request + chiamata service
Service                     →  logica di business
Repository                  →  accesso ai dati
```
I layer non si saltano. Un controller non accede mai direttamente al database.

### 7. Dependency Injection
Usare DI (nativo NestJS, o manuale per progetti Node puri).
Mai istanziare dipendenze pesanti con `new` dentro funzioni.

### 8. Nomi descrittivi
- Variabili e funzioni: `camelCase`, descrittivi, in inglese
- Classi e tipi: `PascalCase`
- Costanti: `UPPER_SNAKE_CASE`
- File: `kebab-case.ts`
- Evitare abbreviazioni non universali (`usr`, `btn`, `mgr`)

---

## III. Testing

### 9. Metodologia di test

La metodologia varia in base al layer:

#### Backend (logica, API, servizi) — TDD
Per ogni nuova feature o bugfix:
1. Scrivi il test che descrive il comportamento atteso
2. Verifica che fallisca (red)
3. Implementa il minimo codice per farlo passare (green)
4. Refactoring (refactor)

#### Frontend (componenti, pagine, flussi utente) — BDD
Per ogni nuova feature o bugfix:
1. Definisci gli scenari in linguaggio naturale (Given/When/Then)
2. Traduci gli scenari in test eseguibili
3. Implementa il codice per far passare gli scenari
4. Refactoring

### 10. Copertura minima
| Layer | Copertura minima |
|---|---|
| Services / Business logic | 80% |
| Utilities / helpers | 90% |
| Controllers | 60% (integration test) |
| UI components | 70% (con Testing Library) |

### 11. Struttura dei test

#### Backend — TDD
```typescript
describe('UserService', () => {
  describe('createUser', () => {
    it('dovrebbe creare un utente con email valida', async () => { ... });
    it('dovrebbe lanciare ValidationError se email non valida', async () => { ... });
    it('dovrebbe lanciare ConflictError se email già esistente', async () => { ... });
  });
});
```

#### Frontend — BDD
```gherkin
Feature: Login utente

  Scenario: Login con credenziali valide
    Given l'utente è nella pagina di login
    When inserisce email e password validi
    And clicca il pulsante "Accedi"
    Then viene reindirizzato alla dashboard
```

---

## IV. Git e workflow

### 12. Conventional Commits (obbligatorio)
```
<tipo>(<scope>): <descrizione in inglese, imperativo, minuscolo>

[corpo opzionale in italiano]

[footer opzionale: BREAKING CHANGE, closes #issue]
```

Tipi ammessi: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`

```
feat(auth): add refresh token rotation
fix(api): handle 429 rate limit response correctly
chore(deps): upgrade zod to 3.23
```

### 13. Branch naming
```
feat/<customId>-<descrizione-breve>
fix/<customId>-<descrizione-breve>
chore/<customId>-<descrizione-breve>
hotfix/<customId>-<descrizione-breve>
```
Il `customId` e' l'identificativo del task ClickUp (es. `DE-123`).
Se il branch non e' associato a un task ClickUp, omettere il customId.

### 14. Pull Request
- Titolo: segue Conventional Commits
- Descrizione minima: **Cosa**, **Perché**, **Come testare**
- La PR non può fare merge se i test falliscono
- La PR non può fare merge se ESLint riporta errori
- Almeno **1 review** richiesta prima del merge

### 15. Commit atomici
Un commit = una modifica logica coerente.
Non committare lavoro a metà, debug temporanei, o `console.log` dimenticati.

---

## V. Sicurezza

### 16. Zero segreti nel codice
- API key, token, password: **solo in variabili d'ambiente**
- File `.env` **non tracciato** da git (verificare `.gitignore`)
- Fornire sempre un `.env.example` con i nomi delle variabili ma senza valori

### 17. Validazione input
Ogni input esterno è potenzialmente malevolo. Validare sempre con Zod,
sanitizzare prima di usare in query o template string.

### 18. Dependency audit
```bash
npm audit
```
Eseguire ad ogni aggiunta di dipendenza. Non aggiungere package con vulnerabilità
note di livello `high` o `critical` senza approvazione esplicita.

---

## VI. Frontend (Next.js / Angular / React)

### 19. Componenti piccoli e riutilizzabili
- Un componente fa **una cosa sola**
- Props tipizzate con TypeScript (no `any`, no cast)
- Nessuna logica di business nel componente — delegare a hook o service

### 20. ShadCN/UI come base
I componenti UI si costruiscono **sopra** ShadCN/UI, non da zero.
Modifiche ai componenti ShadCN avvengono nel layer di customizzazione,
non direttamente nei file generati.

### 21. Tailwind — utility-first, niente CSS custom
- Usare classi Tailwind
- Evitare file CSS custom se non strettamente necessario
- Varianti e temi: tramite `tailwind.config.ts`, non inline

---

## VII. Mobile (Flutter / React Native)

### 22. Flutter — composizione Widget
- Widget: solo UI e interazioni — nessuna logica di business, nessuna chiamata HTTP
- Preferire `StatelessWidget` a helper function per pezzi di UI riutilizzabili
  (le function non partecipano al lifecycle dei widget)
- Usare `const` constructor su ogni widget che lo consente — Flutter salta il rebuild
- Tenere i widget piccoli e focalizzati: scomporre `build()` in sotto-widget
  in base a cosa cambia indipendentemente
- Usare `Key` esplicite (`ValueKey`, `ObjectKey`) per liste, elementi riordinabili
  e widget con stato locale
- Non usare `setState()` per stato applicativo condiviso — solo per stato
  strettamente locale al widget

### 23. Flutter — state management
- Scegliere **un** pattern per progetto e mantenerlo: Riverpod (preferito) o BLoC
- Riverpod: usare `ref.watch()` in `build()`, `ref.read()` solo nei callback
- Riverpod: preferire `@riverpod` code generation e `AsyncNotifier` per stato async
- Usare `AsyncValue` (`when`, `guard`) per stati loading/error/data — mai tracciare
  manualmente booleani `isLoading`/`hasError`
- Preferire `ConsumerWidget`/`ConsumerStatefulWidget` quando l'intero widget
  dipende da un provider
- Lo stato passato attraverso i provider **deve** essere immutabile — mai mutare
  in-place, sempre restituire una nuova istanza

### 24. Dart — type safety
`dynamic` e' **vietato** — come `any` in TypeScript. Usare `Object` e narrowing.

```dart
// ✅ Corretto
sealed class AuthState {}
class Authenticated extends AuthState {
  final User user;
  Authenticated(this.user);
}
class Unauthenticated extends AuthState {}

final message = switch (state) {
  Authenticated(:final user) => 'Ciao ${user.name}',
  Unauthenticated() => 'Non autenticato',
};

// ❌ Vietato
dynamic result = fetchData();
final user = response as User; // cast non sicuro
```

- Abilitare `strict-casts: true` e `strict-raw-types: true` in `analysis_options.yaml`
- Usare `sealed class` per union types ed enumerazioni complesse — garantisce
  exhaustive check nel `switch`
- Usare pattern matching (`switch` expression con destructuring) invece di catene
  `if/else` o check `is`
- Evitare `as` cast — preferire `case` pattern o `is` check con promozione
- Usare class modifier con intenzione: `final` per classi non estendibili,
  `sealed` per gerarchie chiuse, `base` per sole estensioni

### 25. Flutter — immutabilita'
- Tutti i modelli e le classi di stato **devono** essere immutabili:
  campi `final` + `const` constructor
- Annotare con `@immutable` (da `package:meta`) tutti i value object e le classi di stato
- Usare `freezed` per data class — fornisce `copyWith`, `==`, `hashCode`, `toString`,
  serializzazione JSON
- Usare `json_serializable` per serializzazione tipizzata — mai parsing manuale
- Preferire `final` per variabili locali (lint `prefer_final_locals`)
- Usare `const` ovunque possibile: constructor, collection, valori

### 26. Flutter — architettura
Tre layer obbligatori con **dependency rule** (le dipendenze puntano solo verso l'interno):

```
Presentation (widget + provider/controller)
     ↓
Domain (entity + use case + interfacce repository)
     ↑
Data (implementazioni repository + data source + DTO)
```

- Il layer Domain non ha **nessun** import di framework (no Flutter, no Dio, no package esterni)
- Ogni UseCase incapsula una singola operazione di business con un metodo `call()` o `execute()`
- I DTO sono separati dalle entity di dominio — il mapping avviene al confine del layer Data
- Struttura feature-first obbligatoria:
  ```
  lib/
  ├── features/
  │   └── <feature>/
  │       ├── data/           # repository impl, datasource, DTO
  │       ├── domain/         # entity, use case, interfacce repository
  │       └── presentation/   # widget, provider/bloc, page
  ├── core/                   # utility condivise, tema, routing
  └── main.dart
  ```

### 27. Flutter — performance
- Nessun lavoro pesante in `build()` — no I/O, no computazioni costose
- Usare `const` widget aggressivamente — Flutter salta il rebuild delle istanze const
- Usare `ListView.builder` / `GridView.builder` per liste lunghe — mai
  `ListView(children: [...])` con molti elementi
- Usare `RepaintBoundary` per isolare sotto-alberi che ridipingono frequentemente
  (animazioni, indicatori di scroll)
- Non usare `Opacity` per nascondere widget — usare `Visibility` o rendering condizionale
- Profilare con Flutter DevTools (`flutter run --profile`) prima di ottimizzare —
  misurare, non indovinare

### 28. Flutter — gestione errori
- Usare il pattern `sealed class Result<T>` con sottotipi `Success<T>` e `Failure<T>`
  per operazioni del layer domain

```dart
// ✅ Corretto
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

// Nel repository:
Future<Result<User>> getUser(String id);
```

- I metodi del Repository restituiscono `Result<T>` — mai lanciare eccezioni
  attraverso i confini dei layer
- Definire eccezioni tipizzate per dominio (`AuthException`, `NetworkException`)
- Non catturare `Exception` o `Object` generici senza gestione specifica
- Usare `AsyncValue` in Riverpod per propagare stati di errore alla UI
- Gestire sempre tutti i branch nel pattern matching sui tipi di errore sealed —
  nessun `default` che inghiotte errori

### 29. Flutter — linting e analisi statica
Configurazione minima obbligatoria in `analysis_options.yaml`:

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

- **Zero warning in CI**: l'analisi statica (`dart analyze`) deve passare senza warning
- Usare sempre import `package:` — mai import relativi (`../`)

### 30. Flutter — testing
Piramide dei test: molti unit > widget test > pochi integration test.

| Layer | Copertura minima | Strumento |
|---|---|---|
| UseCase / Notifier | 80% | `flutter_test` + `mocktail` |
| Repository | 80% | `flutter_test` + `mocktail` |
| Screen / Widget | 70% | `flutter_test` + `WidgetTester` |
| Flussi critici | E2E | `integration_test` |

- Unit test per ogni UseCase e Notifier — testare la logica in isolamento
- Widget test per ogni screen e componente riutilizzabile — usare `pumpWidget` + `find` + `expect`
- Golden test per regressione visiva su widget design-critical (`matchesGoldenFile`)
- Usare `mocktail` per mock delle dipendenze esterne (repository, API)
- Naming file test: `<source_file>_test.dart` in struttura `test/` speculare a `lib/`
- Ogni test deve essere indipendente — nessuno stato mutabile condiviso tra test

### 31. Dart — naming e organizzazione file
- File: `snake_case.dart` (es. `user_repository.dart`, `auth_provider.dart`)
- Directory: `snake_case` (es. `data_sources/`, `use_cases/`)
- Una classe pubblica per file (eccezione: tipi strettamente accoppiati come sealed class + sottotipi)
- Il nome del file corrisponde alla classe principale: `UserRepository` → `user_repository.dart`
- Import: sempre `package:`, mai relativi (`../`)
- Ordine import: `dart:` → `package:` → relativi (forzato da lint `directives_ordering`)

### 32. React Native — Expo come baseline
- Partire sempre da Expo managed workflow
- Migrare a bare workflow solo se necessario e documentato
- Usare Expo Router per la navigazione
- Logica di rete in hook personalizzati o TanStack Query — mai nei componenti

---

## VIII. Agente AI

### 33. L'agente segue questa Costituzione
Claude Code e qualsiasi altro agente AI **devono** rispettare queste regole esattamente
come uno sviluppatore umano. Non esistono eccezioni per "semplicità" o "velocità".

### 34. L'agente non bypassa i hook
I git hook (lint, test) si applicano anche ai commit suggeriti dall'agente.
Mai usare `--no-verify`.

### 35. L'agente non modifica questo file autonomamente
Modifiche a `CONSTITUTION.md` richiedono una PR con approvazione umana esplicita.

---

*Versione: 1.1.0*
*Aggiornato: 2026-04*
*Prossima revisione pianificata: 2026-07*
