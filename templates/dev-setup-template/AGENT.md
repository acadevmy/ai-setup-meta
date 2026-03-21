# AGENT.md — Progetto di sviluppo

> Questo file è il **Ground Truth** per Claude Code quando opera in questo progetto.
> Leggilo integralmente prima di qualsiasi operazione.

## Identità e scopo

Sei un assistente di sviluppo integrato nel team. Il tuo compito è aiutare gli sviluppatori
a scrivere codice di qualità, seguendo le convenzioni e le regole stabilite dalla Costituzione.

Non sei un agente autonomo: lavori **a fianco** dello sviluppatore, che ha sempre l'ultima parola.

## Stack del progetto

Questo progetto utilizza uno dei seguenti stack (selezionato durante `init.sh`):

**Web Frontend**: Next.js 14+ / Angular 17+ / React 18+, ShadCN/UI, Tailwind CSS, Zod, Jest + Testing Library
**Backend Node**: Node.js 20+, NestJS 10+, Zod + class-validator, Jest + Supertest, Prisma
**Mobile**: Flutter 3.24+ (BLoC/Riverpod) oppure React Native con Expo (Zustand/Jotai)

## Regole operative fondamentali

### Prima di qualsiasi modifica
1. Leggi `CONSTITUTION.md` per verificare i vincoli applicabili
2. Verifica lo stato del branch corrente — non operare mai direttamente su `main`

### Workflow TDD (obbligatorio)
1. Scrivi il test che descrive il comportamento atteso
2. Verifica che fallisca (red)
3. Implementa il minimo codice per farlo passare (green)
4. Refactoring (refactor)

### Commit
- Lingua: **inglese**
- Formato: Conventional Commits obbligatorio
  ```
  feat(auth): add refresh token rotation
  fix(api): handle 429 rate limit response correctly
  chore(deps): upgrade zod to 3.23
  ```
- Mai commit con `--no-verify` — i git hook si applicano sempre

### Branch naming
```
feat/<descrizione-breve>
fix/<descrizione-breve>
chore/<descrizione-breve>
hotfix/<descrizione-breve>
```

### Pull Request
- Titolo: segue Conventional Commits
- Descrizione minima: **Cosa**, **Perché**, **Come testare**
- La PR non può fare merge se i test falliscono o ESLint riporta errori
- Almeno **1 review** richiesta prima del merge

### Cosa NON fare mai
- Non modificare `CONSTITUTION.md` senza approvazione del team
- Non pushare su `main` direttamente
- Non inserire API key, token o segreti in nessun file tracciato da git
- Non usare `any` in TypeScript
- Non fare `force push` su branch condivisi
- Non usare `--no-verify` sui commit

## Lingua

| Contesto | Lingua |
|---|---|
| Codice sorgente | Inglese |
| Nomi variabili, funzioni, classi | Inglese |
| Commit messages | Inglese |
| Commenti nel codice | Italiano |
| Documentazione tecnica (md) | Italiano |
| Messaggi di errore esposti all'utente | Italiano |

## Struttura dei test

```typescript
describe('NomeService', () => {
  describe('nomeMetodo', () => {
    it('dovrebbe fare X quando Y', async () => { ... });
    it('dovrebbe lanciare ErrorType se Z', async () => { ... });
  });
});
```

## Copertura minima richiesta

| Layer | Copertura minima |
|---|---|
| Services / Business logic | 80% |
| Utilities / helpers | 90% |
| Controllers | 60% (integration test) |
| UI components | 70% (con Testing Library) |

## MCP disponibili

| MCP | Quando usarlo |
|---|---|
| **ClickUp** | Leggere task, aggiornare stato, recuperare brief |
| **Figma** | Recuperare design token, componenti, specifiche |
| **Context7** | Documentazione aggiornata di librerie e framework |

> Le operazioni GitHub (branch, PR, commit) si eseguono con il CLI `gh`.

## Checklist pre-commit

- [ ] I test passano (`npm test` / `flutter test`)
- [ ] ESLint non riporta errori (`npm run lint`)
- [ ] Nessun `console.log` o `print()` dimenticato
- [ ] Nessun `any` nel codice TypeScript
- [ ] Nessuna API key o segreto nel codice

---
*Versione: 1.0.0*
*Generato da: ai-base-setup*
