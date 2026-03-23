---
name: review
description: Esegue code review del branch corrente verificando conformita' CONSTITUTION e aggiornando REGISTRY
user-invocable: true
disable-model-invocation: false
---

# /project:review

Esegui una code review del codice modificato nel branch corrente tramite il Review Agent.

## Procedura

### 1. Lancia il Review Agent

Lancia l'agent `review` con:
- BASE_BRANCH: `main`
- CONSTITUTION_PATH: `./CONSTITUTION.md`
- REGISTRY_PATH: `./REGISTRY.md`
- TASK_ID: estratto dal nome del branch corrente (es. `feat/DE-123-desc` → `DE-123`), se presente

### 2. Analizza il risultato

Parsa l'output `---REVIEW-RESULT---` restituito dall'agent.

**Se STATUS = fail**:
- Mostra tutte le VIOLATIONS con file, riga e regola violata
- Mostra i WARNINGS come suggerimenti
- Informa lo sviluppatore che la review non e' passata
- Fermati — il codice va corretto prima di procedere

**Se STATUS = pass-with-warnings**:
- Mostra i WARNINGS come suggerimenti di miglioramento
- Procedi con il passo successivo

**Se STATUS = pass**:
- Conferma che il codice e' conforme
- Procedi con il passo successivo

### 3. Applica aggiornamenti REGISTRY

Se l'agent ha restituito REGISTRY_UPDATES non vuoto:

1. Leggi `REGISTRY.md` corrente
2. Per ogni entry con ACTION: `add`:
   - Aggiungi il blocco ENTRY nella SECTION indicata
   - Rimuovi eventuali placeholder `_Nessuna ... registrata._` dalla sezione
3. Per ogni entry con ACTION: `update`:
   - Trova l'entry esistente nella sezione e aggiorna i campi modificati
4. Committa l'aggiornamento: `docs(registry): update REGISTRY.md`

### 4. Report finale

Mostra un riepilogo:
```
Review: <STATUS>
Violazioni: <numero>
Warning: <numero>
REGISTRY aggiornato: <si/no>

<SUMMARY dall'agent>
```

## Output atteso
- Report di conformita' alla CONSTITUTION
- `REGISTRY.md` aggiornato con le nuove entry (se presenti)
- Commit `docs(registry): update REGISTRY.md` (se modifiche al registry)
