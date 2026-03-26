# REGISTRY.md — Indice strutturato del progetto

> Registro sintetico di componenti riutilizzabili, pattern adottati e decisioni architetturali.
> Claude Code lo legge all'inizio di ogni sessione per contesto immediato.
> Aggiornato automaticamente da `/project:review`.

## Convenzioni

**Entry standard (componente/servizio/feature):**

```
### <scope>/<slug>
- **Files**: `path/file1.ts`, `path/file2.ts`
- **Depends on**: altri entry o "nessuno"
- **API**: `METHOD /path` (solo se espone endpoint)
- **Summary**: una riga di descrizione
```

**Entry pattern:**

```
### <nome-pattern>
- **Dove**: `path/esempio.ts` (implementazione di riferimento)
- **Summary**: cosa fa e quando usarlo
```

**Entry decisione architetturale (ADR):**

```
### ADR: <titolo>
- **Status**: accepted | superseded | deprecated
- **Decision**: cosa si e' deciso e perche'
- **Consequences**: impatto noto
```

**Regole:**
- `scope` = modulo o dominio (es. `auth`, `cart`, `ui`)
- `slug` = nome breve in inglese (es. `refresh-token-rotation`)
- Non duplicare: aggiorna l'entry esistente se evolve
- Rimuovere entry solo quando il codice viene eliminato

---

## Feature

_Nessuna feature registrata._

## Servizi e utility

_Nessun servizio registrato._

## Componenti UI

_Nessun componente registrato._

## Pattern e convenzioni

_Nessun pattern registrato._

## Decisioni architetturali

_Nessuna decisione registrata._
