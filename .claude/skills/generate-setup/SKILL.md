---
name: generate-setup
description: Genera o rigenera un template completo a partire dalle sorgenti (multi-dominio, guidato da manifest.json)
user-invocable: true
disable-model-invocation: true
---

# /project:generate-setup

Genera o rigenera un template completo a partire dalle sorgenti di questo repo.

## Quando usarlo
- Prima creazione di un template
- Dopo modifiche sostanziali alla struttura che richiedono rigenerazione completa
- Su richiesta esplicita del maintainer

## Procedura

1. **Seleziona il template**
   - Elenca le directory in `templates/` che contengono un `manifest.json`
   - Se c'e' un solo template, selezionalo automaticamente
   - Se ce ne sono piu' di uno, chiedi quale generare (o accetta parametro: `/project:generate-setup dev-setup`)

2. **Verifica pre-esecuzione**
   - Controlla di non essere su `main`
   - Crea branch `chore/regenerate-<TEMPLATE_NAME>` se non esiste
   - Leggi `CONSTITUTION.md` per vincoli aggiornati
   - Leggi `templates/<TEMPLATE_NAME>/manifest.json`

3. **Copia shared assets nel template**
   Per ogni entry in `manifest.shared_agents`:
   - Copia `shared/agents/<name>` → `templates/<TEMPLATE_NAME>/.claude/agents/<name>`

   Per ogni entry in `manifest.shared_skills`:
   - Copia `shared/skills/<name>/SKILL.md` → `templates/<TEMPLATE_NAME>/.claude/skills/<name>/SKILL.md`

   Se `manifest.copy_constitution` e' `true`:
   - Copia `CONSTITUTION.md` → `templates/<TEMPLATE_NAME>/CONSTITUTION.md`

4. **Genera la struttura base del template**
   Verifica che tutti i `required_files` del manifest esistano in `templates/<TEMPLATE_NAME>/`.
   Crea o aggiorna i file mancanti:
   - `AGENTS.template.md` — template unico con placeholder
   - `REGISTRY.md` — template del registro progetto
   - `.env.example` — variabili richieste senza valori
   - `CHANGELOG.md` — inizializza con versione corrente
   - `.claude/settings.json` — permessi per sviluppatori

5. **Genera l'agent di dominio in dist/**
   Copia `templates/<TEMPLATE_NAME>/<manifest.agent>` → `dist/agents/<manifest.agent>`

6. **Verifica configurazioni di qualita' in dist/setup.md**
   Verifica che `dist/setup.md` (il dispatcher) sia aggiornato e coerente.

7. **Validazione**
   Lancia l'agent `validate-template` con:
   - TEMPLATE_NAME: `<TEMPLATE_NAME>`
   - SOURCE_CONSTITUTION_PATH: `./CONSTITUTION.md`
   Se STATUS: fail, correggi i problemi segnalati prima di procedere

8. **Aggiorna CHANGELOG**
   Aggiungi entry in `templates/<TEMPLATE_NAME>/CHANGELOG.md`

9. **Apri PR**
   Usa GitHub CLI per aprire PR con:
   - Titolo: `chore(template): regenerate <TEMPLATE_NAME>`
   - Label: `template`
   - Descrizione: lista dei file generati/modificati

## Output atteso
PR aperta su GitHub con il template aggiornato, pronta per review.
