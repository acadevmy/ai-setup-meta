# Guida sviluppatore — Dal setup al primo task

Guida pratica per lo sviluppatore che ha appena completato l'onboarding
e vuole iniziare a lavorare con il workflow AI-native.

> **Prerequisito**: aver completato tutti i passi descritti in [onboarding.md](onboarding.md).

---

## 1. Panoramica del workflow

Il flusso di lavoro quotidiano segue questo ciclo:

```
Task su ClickUp (TO DO)
       │
       ▼
/project:start-task DE-123
  → crea branch feat/DE-123-descrizione
  → task passa a IN PROGRESS
  → mostra il brief del task
       │
       ▼
Scrivi codice con Claude Code
  → backend: ciclo TDD (Red → Green → Refactor)
  → frontend: ciclo BDD (Given/When/Then)
       │
       ▼
Commit con Conventional Commits
  feat(auth): add login endpoint [DE-123]
       │
       ▼
/project:review
  → verifica CONSTITUTION
  → aggiorna REGISTRY.md
       │
       ▼
Push + Pull Request
       │
       ▼
/project:sync-task
  → task passa a IN REVIEW
       │
       ▼
Merge → semantic-release (se greenfield)
```

---

## 2. Configurazione rapida (checklist)

Prima di iniziare, verifica che tutto sia a posto:

```bash
# Claude Code installato e funzionante
claude --version

# Autenticazione GitHub attiva
gh auth status

# MCP servers connessi (clickup, context7 e opzionalmente figma)
claude mcp list

# AGENTS.md, CLAUDE.md e CONSTITUTION.md presenti nella root del progetto
ls AGENTS.md CLAUDE.md CONSTITUTION.md
```

Se manca qualcosa, torna alla guida di [onboarding.md](onboarding.md).

---

## 3. Avviare il primo task

### 3.1 Prendi un task da ClickUp

Apri Claude Code nella root del tuo progetto:

```bash
claude
```

Poi lancia il comando con l'ID del task ClickUp:

```
/project:start-task DE-123
```

Claude Code:
1. Recupera i dettagli del task da ClickUp (titolo, descrizione, acceptance criteria)
2. Crea il branch seguendo la convenzione: `feat/DE-123-descrizione-breve`
3. Aggiorna lo stato del task su ClickUp a **IN PROGRESS**
4. Ti mostra un riepilogo del task e propone un piano di implementazione

> **Senza ID?** Puoi lanciare `/project:start-task` senza argomenti — Claude Code
> ti mostrera' i task assegnati a te nello sprint corrente.

### 3.2 Sviluppa con TDD o BDD

Il tipo di ciclo dipende dal layer su cui lavori:

| Layer | Metodologia | Comando | Coverage minimo |
|---|---|---|---|
| Backend (services, utils) | TDD — Red/Green/Refactor | `/project:tdd` | 80% services, 90% utils |
| Frontend (componenti UI) | BDD — Given/When/Then | `/project:bdd` | 70% componenti |
| Controller/API | TDD | `/project:tdd` | 60% controllers |

**Esempio — ciclo TDD per un servizio backend:**

```
/project:tdd
```

Claude Code ti guidera' attraverso:

1. **RED** — Scrive il test che fallisce (descrive il comportamento atteso)
2. **GREEN** — Scrive il codice minimo per far passare il test
3. **REFACTOR** — Migliora il codice mantenendo i test verdi

Ad ogni passo ti chiede conferma prima di procedere.

**Esempio — ciclo BDD per un componente frontend:**

```
/project:bdd
```

Claude Code ti guidera' attraverso:

1. **Scenario** — Definisce Given/When/Then in linguaggio naturale
2. **Test** — Scrive il test con Testing Library
3. **Implementazione** — Crea il componente che soddisfa lo scenario

### 3.3 Scrivi commit atomici

Ogni commit deve seguire le **Conventional Commits** con l'ID del task:

```
feat(auth): add JWT token validation [DE-123]
fix(users): handle empty email in registration [DE-123]
test(auth): add integration tests for login flow [DE-123]
refactor(auth): extract token service from controller [DE-123]
```

I git hooks (configurati dal setup agent) validano automaticamente:
- **commitlint** — formato del messaggio di commit
- **prettier** — formattazione del codice
- **eslint** — qualita' del codice

Se un hook fallisce, correggi e ricommita. Non usare mai `--no-verify`.

### 3.4 Lancia la review

Quando hai finito di sviluppare:

```
/project:review
```

Claude Code esegue:
1. Verifica conformita' alla **CONSTITUTION.md**
2. Controlla qualita' del codice (duplicazioni, complessita', sicurezza)
3. Aggiorna il **REGISTRY.md** con i nuovi componenti/servizi/pattern

### 3.5 Push e Pull Request

```bash
git push -u origin feat/DE-123-descrizione-breve
gh pr create
```

La PR deve avere:
- **Titolo**: formato Conventional Commits (`feat(scope): descrizione`)
- **Descrizione**: Cosa / Perche' / Come testare
- **Almeno 1 review** approvata prima del merge
- **Test verdi** in CI

### 3.6 Sincronizza il task

Dopo aver aperto la PR:

```
/project:sync-task
```

Claude Code aggiorna lo stato su ClickUp (es. IN REVIEW) e aggiunge il link alla PR.

---

## 4. Regole fondamentali

Queste regole vengono dalla `CONSTITUTION.md` — sono obbligatorie per tutto il codice,
sia scritto da te che da Claude Code.

### TypeScript

- `strict: true` sempre attivo — niente `any`, mai
- Validare tutti i dati esterni con **Zod** (schema-first)
- Funzioni pure, massimo 40 righe, una responsabilita'
- Costanti con nome: niente numeri o stringhe magiche

### Architettura

- Separazione a layer: **Controller → Service → Repository**
- Niente scorciatoie (il controller non parla direttamente al DB)
- Dependency Injection: mai `new` per dipendenze pesanti dentro le funzioni

### Naming

| Tipo | Convenzione | Esempio |
|---|---|---|
| Variabili e funzioni | camelCase | `getUserById` |
| Classi e interfacce | PascalCase | `UserService` |
| Costanti | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |

### Sicurezza

- **Zero segreti nel codice** — solo `.env` (gitignored)
- Validare ogni input con Zod + sanitizzare prima di DB o template
- `npm audit` ad ogni aggiunta di dipendenza

### Git

- **Mai push diretto su main** — sempre branch + PR
- **Commit atomici** — un cambio logico per commit
- **Conventional Commits** obbligatori con task ID

---

## 5. Comandi slash — reference rapido

| Comando | Quando usarlo |
|---|---|
| `/project:start-task [ID]` | Inizio lavoro su un task ClickUp |
| `/project:tdd` | Sviluppo backend con ciclo Red/Green/Refactor |
| `/project:bdd` | Sviluppo frontend con scenari Given/When/Then |
| `/project:review` | Code review prima di aprire la PR |
| `/project:sync-task` | Sincronizzare stato task su ClickUp |

---

## 6. Struttura progetto tipo

Dopo il setup, il tuo progetto avra' questi file AI-native:

```
progetto/
├── CONSTITUTION.md          # Regole inviolabili (non modificare)
├── AGENTS.md                # Istruzioni per agenti AI (standard cross-tool)
├── CLAUDE.md                # Entry point per Claude Code (importa AGENTS.md)
├── REGISTRY.md              # Indice di componenti, servizi, pattern, ADR
├── .env                     # Segreti locali (gitignored)
├── .claude/
│   ├── settings.json        # Permessi Claude Code
│   ├── skills/              # Comandi /project:*
│   ├── agents/              # Sub-agenti (clickup, review)
│   └── hooks/               # Automazioni (protect-files, post-edit, on-compact)
├── mcp/
│   └── mcp.json             # Server MCP configurati (gitignored)
└── .husky/                  # Git hooks (solo greenfield)
    ├── pre-commit           # prettier + eslint
    └── commit-msg           # commitlint
```

**File che non devi mai modificare manualmente:**
- `CONSTITUTION.md` — gestita dal meta-repo
- `.claude/hooks/*` — gestiti dal meta-repo
- `.claude/agents/*` — gestiti dal meta-repo

**File che devi mantenere aggiornato:**
- `REGISTRY.md` — si aggiorna anche via `/project:review`, ma puoi integrare manualmente

---

## 7. Troubleshooting

### Claude Code non vede i server MCP

```bash
# Verifica che il file mcp.json esista
ls mcp/mcp.json

# Se manca, ricrealo dal template
cp mcp/mcp.json.example mcp/mcp.json
```

### Il commit viene rifiutato dai git hooks

Non usare `--no-verify`. Leggi l'errore e correggi:
- **commitlint**: il messaggio non segue Conventional Commits
- **prettier**: il codice non e' formattato — salva il file e riprova
- **eslint**: ci sono errori nel codice — correggili prima di committare

### ClickUp non risponde

Al primo utilizzo, ClickUp apre il browser per l'autenticazione OAuth.
Se la sessione e' scaduta, riavvia Claude Code — il flusso OAuth riparte automaticamente.

### Il setup agent non rileva il mio stack

Assicurati che nella root del progetto ci sia:
- `package.json` con le dipendenze (per Next.js, Angular, React, NestJS)
- `pubspec.yaml` (per Flutter)
- `app.json` con `expo` (per React Native/Expo)

---

## 8. Prossimi passi

Dopo aver completato il primo task:

1. **Esplora il REGISTRY.md** — capire cosa e' gia' stato costruito nel progetto
2. **Leggi il profilo stack** del tuo progetto in `AGENTS.md` — contiene regole specifiche
3. **Usa Context7** — Claude Code accede alla documentazione aggiornata delle librerie via MCP,
   quindi puoi chiedergli riferimenti precisi senza cercare manualmente
4. **Figma (opzionale)** — se hai configurato il token, Claude Code puo' leggere i design
   direttamente dai file Figma e generare componenti coerenti
