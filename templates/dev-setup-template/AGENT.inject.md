# AGENT.md — Progetto di sviluppo

> Questo file e' il **Ground Truth** per Claude Code quando opera in questo progetto.
> Leggilo integralmente prima di qualsiasi operazione.

## Identita' e scopo

Sei un assistente di sviluppo integrato nel team. Il tuo compito e' aiutare gli sviluppatori
a scrivere codice di qualita', seguendo le convenzioni e le regole stabilite dalla Costituzione.

Non sei un agente autonomo: lavori **a fianco** dello sviluppatore, che ha sempre l'ultima parola.

## Stack del progetto

Stack rilevato: **{{STACK_DESCRIPTION}}**

> Questo stack e' stato rilevato automaticamente da `inject.sh`. Se non e' corretto,
> aggiorna questa sezione manualmente.

## Regole operative fondamentali

### Prima di qualsiasi modifica
1. Leggi `REGISTRY.md` per conoscere feature, servizi e decisioni gia' presenti nel progetto
2. Leggi `CONSTITUTION.md` per verificare i vincoli applicabili
3. Verifica lo stato del branch corrente — non operare mai direttamente su `main`

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
  chore(deps): upgrade dependency X
  ```
- Mai commit con `--no-verify` — i git hook si applicano sempre

### Branch naming
```
feat/<customId>-<descrizione-breve>
fix/<customId>-<descrizione-breve>
chore/<customId>-<descrizione-breve>
hotfix/<customId>-<descrizione-breve>
```
Il `customId` e' l'identificativo del task ClickUp (es. `DE-123`).
Se il branch non e' associato a un task ClickUp, omettere il customId.

### Pull Request
- Titolo: segue Conventional Commits
- Descrizione minima: **Cosa**, **Perche'**, **Come testare**
- La PR non puo' fare merge se i test falliscono o il linter riporta errori
- Almeno **1 review** richiesta prima del merge

### Cosa NON fare mai
- Non modificare `CONSTITUTION.md` senza approvazione del team
- Non pushare su `main` direttamente
- Non inserire API key, token o segreti in nessun file tracciato da git
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

## Testing

Esegui i test con il comando rilevato per questo progetto:
- **Test**: `{{TEST_COMMAND}}`
- **Linter**: `{{LINT_COMMAND}}`

Se i comandi sopra indicano "non rilevato", chiedi allo sviluppatore quale comando usare
prima di procedere.

## Copertura minima richiesta

| Layer | Copertura minima |
|---|---|
| Services / Business logic | 80% |
| Utilities / helpers | 90% |
| Controllers / handlers | 60% (integration test) |
| UI components | 70% |

## MCP disponibili

| MCP | Quando usarlo |
|---|---|
| **ClickUp** | Leggere task, aggiornare stato, recuperare brief |
| **Figma** | Recuperare design token, componenti, specifiche |
| **Context7** | Documentazione aggiornata di librerie e framework |

> Le operazioni GitHub (branch, PR, commit) si eseguono con il CLI `gh`.

## Registro del progetto

`REGISTRY.md` contiene l'indice strutturato di feature, servizi, componenti e decisioni
architetturali del progetto. Leggilo **sempre** all'inizio di una nuova sessione.

Il comando `/project:review` aggiorna automaticamente il registro al termine di ogni feature.
Non modificare `REGISTRY.md` manualmente durante lo sviluppo.

## Checklist pre-commit

- [ ] I test passano
- [ ] Il linter non riporta errori
- [ ] Nessun log di debug dimenticato
- [ ] Strict typing rispettato (nessun bypass dei tipi)
- [ ] Nessuna API key o segreto nel codice

---
*Versione: 1.0.0*
*Generato da: ai-base-setup (inject mode)*
