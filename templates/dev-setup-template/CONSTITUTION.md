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

### 9. TDD — test prima dell'implementazione
Per ogni nuova feature o bugfix:
1. Scrivi il test che descrive il comportamento atteso
2. Verifica che fallisca (red)
3. Implementa il minimo codice per farlo passare (green)
4. Refactoring (refactor)

### 10. Copertura minima
| Layer | Copertura minima |
|---|---|
| Services / Business logic | 80% |
| Utilities / helpers | 90% |
| Controllers | 60% (integration test) |
| UI components | 70% (con Testing Library) |

### 11. Struttura dei test
```typescript
describe('UserService', () => {
  describe('createUser', () => {
    it('dovrebbe creare un utente con email valida', async () => { ... });
    it('dovrebbe lanciare ValidationError se email non valida', async () => { ... });
    it('dovrebbe lanciare ConflictError se email già esistente', async () => { ... });
  });
});
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

### 22. Flutter — separazione Widget / Logic
- Widget: solo UI e interazioni
- Logica: BLoC, Riverpod, o Provider (scegliere uno per progetto e mantenerlo)
- Nessuna chiamata HTTP diretta nel Widget

### 23. React Native — Expo come baseline
- Partire sempre da Expo managed workflow
- Migrare a bare workflow solo se necessario e documentato

---

## VIII. Agente AI

### 24. L'agente segue questa Costituzione
Claude Code e qualsiasi altro agente AI **devono** rispettare queste regole esattamente
come uno sviluppatore umano. Non esistono eccezioni per "semplicità" o "velocità".

### 25. L'agente non bypassa i hook
I git hook (lint, test) si applicano anche ai commit suggeriti dall'agente.
Mai usare `--no-verify`.

### 26. L'agente non modifica questo file autonomamente
Modifiche a `CONSTITUTION.md` richiedono una PR con approvazione umana esplicita.

---

*Versione: 1.0.0*
*Aggiornato: 2026-03*
*Prossima revisione pianificata: 2026-06*
