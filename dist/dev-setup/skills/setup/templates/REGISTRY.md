# REGISTRY.md — Structured project index

> Concise registry of reusable components, adopted patterns, and architectural decisions.
> Claude Code reads this at the start of each session for immediate context.
> Automatically updated by `/project:review`.

## Conventions

**Standard entry (component/service/feature):**

```
### <scope>/<slug>
- **Files**: `path/file1.ts`, `path/file2.ts`
- **Depends on**: other entries or "none"
- **API**: `METHOD /path` (only if it exposes an endpoint)
- **Summary**: one-line description
```

**Pattern entry:**

```
### <pattern-name>
- **Where**: `path/example.ts` (reference implementation)
- **Summary**: what it does and when to use it
```

**Architectural decision entry (ADR):**

```
### ADR: <title>
- **Status**: accepted | superseded | deprecated
- **Decision**: what was decided and why
- **Consequences**: known impact
```

**Rules:**
- `scope` = module or domain (e.g. `auth`, `cart`, `ui`)
- `slug` = short name in English (e.g. `refresh-token-rotation`)
- No duplicates: update the existing entry if it evolves
- Remove entries only when the code is deleted

---

## Features

_No features registered._

## Services and utilities

_No services registered._

## UI Components

_No components registered._

## Patterns and conventions

_No patterns registered._

## Architectural decisions

_No decisions registered._
