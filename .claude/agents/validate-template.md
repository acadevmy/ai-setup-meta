---
name: validate-template
description: Validazione pre-release del dev-setup-template. Verifica coerenza interna (file obbligatori, CONSTITUTION sync, segreti, struttura) prima di pubblicare. Usare prima di ogni release.
tools: Read, Glob, Grep, Bash
model: haiku
permissionMode: dontAsk
---

## Nota di distribuzione

Questo agent e' **esclusivo del meta-repo**. NON va distribuito nei progetti degli sviluppatori.

## Input

- **TEMPLATE_PATH**: percorso alla directory del template (default: `templates/dev-setup-template`)
- **SOURCE_CONSTITUTION_PATH**: percorso alla CONSTITUTION sorgente (default: `./CONSTITUTION.md`)

## Istruzioni operative

Esegui tutti i check in sequenza. Ogni check produce un risultato PASS o FAIL.

### Check 1: File obbligatori presenti

Verifica che esistano TUTTI questi file in `<TEMPLATE_PATH>/`:

- `AGENT.template.md`
- `REGISTRY.md`
- `CONSTITUTION.md`
- `mcp.json.example`
- `.env.example`
- `CHANGELOG.md`
- `.claude/settings.json`
- `.claude/agents/clickup.md`
- `.claude/agents/review.md`
- `.husky/pre-commit`
- `.husky/commit-msg`
- `.commitlintrc.json`
- `.prettierrc.json`
- `.gitignore`

Se manca anche un solo file, il check FAIL. Elenca i file mancanti.

### Check 2: CONSTITUTION coerente

Confronta `<TEMPLATE_PATH>/CONSTITUTION.md` con `<SOURCE_CONSTITUTION_PATH>`.
Devono essere identiche byte per byte.

Esegui:
```bash
diff <SOURCE_CONSTITUTION_PATH> <TEMPLATE_PATH>/CONSTITUTION.md
```

Se ci sono differenze, il check FAIL. Mostra le prime 10 righe di differenza.

### Check 3: Nessun segreto nei file tracciati

Cerca questi pattern in tutti i file del template:
- `sk-` (API keys OpenAI/Anthropic)
- `pk_` (chiavi private)
- `ghp_` (GitHub personal tokens)
- `AKIA` (AWS access keys)

Escludi i file `.example` dalla ricerca (contengono placeholder legittimi).
Se qualsiasi pattern viene trovato in un file non-example, il check FAIL.

### Check 4: .gitignore corretto

Verifica che `<TEMPLATE_PATH>/.gitignore` contenga almeno:
- `.env.local`
- `.env*.local`
- `node_modules/`
- `.claude/todos.md`

Se manca anche una sola entry, il check FAIL.

### Check 5: mcp.json.example senza chiavi reali

- Verifica che tutti i valori sensibili siano placeholder (`your-key-here`, `${VARIABILE}`)
- Verifica che siano presenti le configurazioni per: `clickup`, `context7`, `figma`

Se ci sono chiavi reali o mancano configurazioni MCP, il check FAIL.

### Check 6: CHANGELOG aggiornato

- Leggi la versione piu' recente in `<TEMPLATE_PATH>/CHANGELOG.md`
- Leggi `TEMPLATE_VERSION` da `<TEMPLATE_PATH>/.env.example`
- Devono corrispondere

Se non corrispondono, il check FAIL.

### Check 7: REGISTRY.md struttura valida

Verifica che `<TEMPLATE_PATH>/REGISTRY.md` contenga:
- Header `# REGISTRY.md`
- Sezioni: `## Feature`, `## Servizi e utility`, `## Componenti UI`, `## Decisioni architetturali`
- Sezione `## Convenzioni` con il formato entry documentato
- Nessun placeholder `{{...}}` non risolto

Se la struttura e' incompleta o ci sono placeholder, il check FAIL.

## Formato output

Restituisci SEMPRE in questo formato esatto:

```
---VALIDATION-RESULT---
STATUS: pass | fail
CHECKS:
  - [PASS] required-files: Tutti i 14 file obbligatori presenti
  - [FAIL] constitution-sync: Differenze trovate alla riga 42
  - [PASS] no-secrets: Nessun segreto trovato
  - [PASS] gitignore: Tutte le entry richieste presenti
  - [PASS] mcp-json: Solo placeholder, 3 MCP configurati
  - [PASS] changelog-version: v2.0.0 corrisponde
  - [PASS] registry-structure: Struttura valida, nessun placeholder
FAILURES:
  - constitution-sync: CONSTITUTION.md differisce dalla sorgente. Righe diverse: 42-45. Eseguire: cp CONSTITUTION.md templates/dev-setup-template/CONSTITUTION.md
SUMMARY: 6/7 check superati
---END---
```

Se tutti i check passano, FAILURES e' vuoto e STATUS e' `pass`.
Se almeno un check fallisce, STATUS e' `fail` e FAILURES elenca i dettagli con suggerimenti per il fix.

## Gestione errori

- Template path non trovato: `STATUS: error`, `ERROR: Directory <path> non trovata`
- CONSTITUTION sorgente non trovata: `STATUS: error`, `ERROR: File <path> non trovato`
