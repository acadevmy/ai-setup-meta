# REGISTRY.md — Indice strutturato del progetto

> Questo file e' il **registro** di feature, servizi, componenti e decisioni architetturali.
> Claude Code lo legge all'inizio di ogni sessione per avere contesto immediato sul codice esistente.
> Viene aggiornato automaticamente dal comando `/project:review`.

## Convenzioni

Ogni entry usa il formato seguente, raggruppata nella sezione appropriata.

**Entry standard:**

```
### <scope>/<slug>
- **Type**: feature | service | component | utility | api-endpoint | config
- **Layer**: controller | service | repository | component | hook | utility | config
- **Files**: `path/file1.ts`, `path/file2.ts`
- **Depends on**: altri entry di questo registro o "nessuno"
- **Exposed API**: `METHOD /path` (se applicabile, altrimenti omettere)
- **Added**: YYYY-MM-DD
- **Task**: ID del task ClickUp (se applicabile, altrimenti omettere)
- **Summary**: una riga di descrizione in italiano
```

**Entry decisione architetturale (ADR):**

```
### ADR: <titolo>
- **Date**: YYYY-MM-DD
- **Status**: accepted | superseded | deprecated
- **Context**: perche' si e' posta la domanda
- **Decision**: cosa si e' deciso
- **Consequences**: impatto noto
```

**Regole:**
- Lo `scope` corrisponde al modulo o dominio (es. `auth`, `cart`, `ui`)
- Lo `slug` e' un nome breve e descrittivo in inglese (es. `refresh-token-rotation`)
- Non duplicare entry: se una feature evolve, aggiorna l'entry esistente
- Rimuovere entry solo quando il codice corrispondente viene eliminato

---

## Feature

_Nessuna feature registrata._

## Servizi e utility

_Nessun servizio registrato._

## Componenti UI

_Nessun componente registrato._

## Decisioni architetturali

_Nessuna decisione registrata._
