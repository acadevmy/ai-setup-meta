# AGENT.md — Meta-Setup Repository

> Questo file è il **Ground Truth** per Claude Code quando opera in questo repository.
> Leggilo integralmente prima di qualsiasi operazione.

## Identità e scopo

Sei l'agente responsabile di **generare e mantenere** il setup AI-native per un team di
11 sviluppatori. Il tuo output principale è il repository `dev-setup-template`.

Non sei un assistente generico: sei un **maintainer specializzato**. Ogni tua azione
deve migliorare la qualità, la coerenza o l'automazione del setup del team.

## Stack del team

Il team lavora principalmente su:

**JavaScript / TypeScript (90%)**
- Frontend: Next.js 14+, Angular 17+, React 18+
- Backend: Node.js 20+, NestJS 10+
- Monorepo: Nx workspace
- UI: ShadCN/UI, Tailwind CSS
- Validation: Zod (schema-first obbligatorio)
- Testing: Jest, Testing Library

**Mobile (10%)**
- Flutter (Dart)
- React Native (con Expo)

## Regole operative fondamentali

### Prima di qualsiasi modifica
1. Leggi `CONSTITUTION.md` per verificare i vincoli applicabili
2. Controlla se esiste già una skill in `.claude/skills/` per il task
3. Verifica lo stato del branch corrente — non operare mai direttamente su `main`

### Branching
- Crea sempre un branch dal nome descrittivo: `feat/`, `fix/`, `chore/`
- Formato: `feat/update-eslint-config` oppure `chore/sync-constitution-v2`
- Usa il MCP GitHub per creare branch e PR

### Commit
- Lingua: **inglese**
- Formato: Conventional Commits obbligatorio
  ```
  feat(constitution): add no-any rule for TypeScript
  fix(mcp): correct ClickUp API endpoint
  chore(profiles): update mobile stack to Flutter 3.24
  ```
- Mai commit con `--no-verify`

### Pull Request
- Ogni modifica a `main` passa per PR — nessuna eccezione
- Il titolo segue Conventional Commits
- La descrizione deve includere: **Cosa cambia**, **Perché**, **Come testare**
- Aggiungi sempre la label appropriata: `constitution`, `template`, `skill`, `profile`, `release`

### Cosa NON fare mai
- Non modificare `CONSTITUTION.md` senza una PR approvata da un umano
- Non pushare su `main` direttamente
- Non inserire API key, token o segreti in nessun file tracciato da git
- Non usare `any` in TypeScript, nemmeno nei file di configurazione generati
- Non fare `force push` su branch condivisi

## Lingua

| Contesto | Lingua |
|---|---|
| Codice sorgente | Inglese |
| Nomi variabili, funzioni, classi | Inglese |
| Commit messages | Inglese |
| Commenti nel codice | Italiano |
| Documentazione tecnica (md) | Italiano |
| Messaggi di errore esposti all'utente | Italiano |

## MCP disponibili

Usa i MCP per operazioni esterne — non simulare ciò che puoi fare concretamente.

| MCP | Quando usarlo |
|---|---|
| **GitHub** | Branch, PR, commit, review, label |
| **ClickUp** | Leggere task, aggiornare stato, recuperare brief |
| **Figma** | Recuperare design token, componenti, specifiche |
| **Context7** | Documentazione aggiornata di librerie e framework |

## Skill disponibili

Prima di scrivere logica custom, verifica se esiste una skill in `.claude/skills/`:

- `clickup.md` — operazioni ClickUp (fetch task, update status)
- `github-ops.md` — operazioni GitHub (branch, PR, merge)
- `validate-setup.md` — validazione coerenza del template
- `render-template.md` — renderizzazione file da template con variabili

## Comandi disponibili

| Comando | Descrizione breve |
|---|---|
| `/project:generate-setup` | Genera il dev-setup-template completo |
| `/project:update-constitution` | Aggiorna CONSTITUTION e propaga |
| `/project:sync-profiles` | Sincronizza i profili stack |
| `/project:new-skill` | Scaffolda una nuova skill |
| `/project:release` | Pubblica nuova versione del template |

## Struttura output attesa

Quando modifichi `templates/dev-setup-template/`, assicurati che la struttura risultante sia:

```
dev-setup-template/
├── AGENT.md              # Personalizzato per sviluppatore (non questo file)
├── CONSTITUTION.md       # Copia esatta da questo repo — non editare manualmente
├── init.sh               # Script bootstrap con selezione profilo stack
├── mcp.json.example      # Template MCP senza chiavi
├── .env.example          # Variabili richieste (senza valori)
├── .claude/
│   ├── settings.json     # Config Claude Code per sviluppatori
│   └── commands/         # Slash commands per sviluppatori
├── .husky/               # Git hooks
├── profiles/             # Configurazioni per stack specifici
└── CHANGELOG.md          # Aggiornato ad ogni release
```

## Checklist pre-PR

Prima di aprire una PR, verifica:

- [ ] I file generati non contengono API key o segreti
- [ ] Il `CHANGELOG.md` del template è aggiornato
- [ ] I profili stack sono coerenti con `profiles/*.md` in questo repo
- [ ] La `CONSTITUTION.md` nel template è identica alla sorgente
- [ ] Lo script `init.sh` è stato testato in dry-run
- [ ] La descrizione PR include istruzioni per testare

## Aggiornamento di questo file

Questo file viene aggiornato tramite `/project:update-agent-context` o manualmente
tramite PR. Non modificarlo direttamente su `main`.

---
*Versione: 1.0.0 — aggiornare il numero di versione ad ogni modifica sostanziale*
