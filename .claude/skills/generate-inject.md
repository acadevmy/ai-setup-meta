---
name: generate-inject
description: Genera o rigenera inject.sh per innesto workflow AI in codebase esistenti
user-invocable: true
disable-model-invocation: true
---

# /project:generate-inject

Genera o rigenera lo script `inject.sh` e i file di supporto per l'innesto del workflow AI in codebase esistenti.

## Quando usarlo
- Prima creazione dello script inject
- Dopo modifiche alla CONSTITUTION o ai comandi che richiedono aggiornamento
- Su richiesta esplicita del maintainer

## Procedura

1. **Verifica pre-esecuzione**
   - Controlla di non essere su `main`
   - Crea branch `feat/generate-inject-script` se non esiste
   - Leggi `CONSTITUTION.md` per vincoli aggiornati
   - Leggi tutti i file in `.claude/skills/` per il workflow corrente

2. **Genera lo script inject**
   Crea o aggiorna `templates/dev-setup-template/inject.sh` con:
   - Prerequisiti minimi (solo `git` e `claude` CLI, NO Node.js requirement)
   - Funzioni di auto-detection stack (linguaggio, test runner, linter, validazione, frontend, mobile)
   - CONSTITUTION modulare (sezioni VI/VII condizionali in base a frontend/mobile rilevati)
   - AGENT.md generato da `AGENT.template.md` con sostituzione placeholder
   - REGISTRY.md copiato nella root del progetto (safe_copy con conflict detection)
   - Setup `.claude/` con conflict detection (non sovrascrive file esistenti)
   - Setup MCP (ClickUp user scope, Context7 project scope, Figma condizionale)
   - Setup `.env` con merge (appende `CLICKUP_SETUP_LIST_ID` senza sovrascrivere)
   - Cleanup e summary finale

3. **Verifica coerenza AGENT.template.md**
   Verifica che `templates/dev-setup-template/AGENT.template.md` contenga tutti i placeholder necessari:
   - `{{STACK_DESCRIPTION}}`
   - `{{TEST_COMMAND}}`
   - `{{LINT_COMMAND}}`
   Se mancano, aggiornalo.

4. **Aggiorna skill adattive**
   Verifica che `tdd.md` e `review.md` usino detection multi-stack:
   - `tdd.md`: step "Verifica finale" con detection di npm test/pytest/go test/flutter test/cargo test
   - `review.md`: controlli conformita' con schema validator e typing del progetto rilevato

5. **Validazione**
   - Verifica che `inject.sh` sia eseguibile (`chmod +x`)
   - Verifica che `init.sh` non sia stato modificato (flusso greenfield intatto)
   - Esegui `bash -n inject.sh` per verificare la sintassi

6. **Apri PR**
   Usa GitHub CLI per aprire PR con:
   - Titolo: `feat(template): regenerate inject mode`
   - Label: `template`
   - Descrizione: lista dei file generati/modificati

## Differenza con generate-setup

| | generate-setup | generate-inject |
|---|---|---|
| Target | Progetti greenfield | Codebase esistenti |
| Installa tooling | Si (husky, eslint, prettier...) | No |
| Profili stack | Si (web-frontend, backend-node, mobile) | No (auto-detection) |
| CONSTITUTION | Copia completa | Modulare (sezioni condizionali) |
| AGENT.md | Template con valori da profilo scelto | Template con valori da auto-detection |

> **Nota**: Entrambi usano lo stesso `AGENT.template.md`. La differenza e' solo nella fonte
> dei valori per i placeholder (profilo scelto vs auto-detection).

## Output atteso
PR aperta su GitHub con inject.sh e file di supporto aggiornati.
