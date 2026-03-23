---
name: generate-setup
description: Genera o rigenera il dev-setup-template completo a partire dalle sorgenti
user-invocable: true
disable-model-invocation: true
---

# /project:generate-setup

Genera o rigenera il `dev-setup-template` completo a partire dalle sorgenti di questo repo.

## Quando usarlo
- Prima creazione del template
- Dopo modifiche sostanziali alla struttura che richiedono rigenerazione completa
- Su richiesta esplicita del maintainer

## Procedura

1. **Verifica pre-esecuzione**
   - Controlla di non essere su `main`
   - Crea branch `chore/regenerate-setup-template` se non esiste
   - Leggi `CONSTITUTION.md` per vincoli aggiornati
   - Leggi tutti i profili in `profiles/` per avere lo stack completo

2. **Genera la struttura base**
   Crea o aggiorna `templates/dev-setup-template/` con:
   - `CONSTITUTION.md` — copia esatta da questo repo (non editare)
   - `AGENT.template.md` — template unico con placeholder (usato sia per greenfield che existing)
   - `REGISTRY.md` — template del registro progetto (vuoto, con struttura e convenzioni)
   - `mcp.json.example` — template MCP senza chiavi
   - `.env.example` — variabili richieste senza valori
   - `CHANGELOG.md` — inizializza con versione corrente

3. **Genera configurazione Claude Code**
   Crea `.claude/` con:
   - `settings.json` — permessi per sviluppatori (più restrittivi di questo repo)
   - `skills/` — skill per sviluppatori (workflow TDD, ClickUp sync, ecc.)

4. **Verifica configurazioni di qualita' in dist/setup.md**
   Le config di qualita' (husky, commitlint, prettier, eslint, releaserc, CI/CD workflow)
   NON sono file statici nel template — vengono generate al momento del bootstrap
   dall'agente setup (passi 9.3–9.6 di `dist/setup.md`). Verifica che i blocchi
   in setup.md siano aggiornati e coerenti con i profili in `profiles/*.md`.

5. **Validazione**
   Lancia l'agent `validate-template` con:
   - TEMPLATE_PATH: `templates/dev-setup-template`
   - SOURCE_CONSTITUTION_PATH: `./CONSTITUTION.md`
   Se STATUS: fail, correggi i problemi segnalati prima di procedere

7. **Aggiorna CHANGELOG**
   Aggiungi entry in `templates/dev-setup-template/CHANGELOG.md`

8. **Apri PR**
   Usa GitHub CLI per aprire PR con:
   - Titolo: `chore(template): regenerate dev-setup-template vX.Y.Z`
   - Label: `template`
   - Descrizione: lista dei file generati/modificati

## Output atteso
PR aperta su GitHub con il template aggiornato, pronta per review.
