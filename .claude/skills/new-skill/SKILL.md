---
name: new-skill
description: Scaffolda una nuova skill (shared o specifica di un dominio)
user-invocable: true
disable-model-invocation: true
---

# /project:new-skill

Scaffolda una nuova skill da aggiungere a un template o alla cartella shared.

## Quando usarlo
- Il team ha un pattern ripetuto che vale la pena automatizzare
- Un processo multi-step puo' essere codificato come skill riutilizzabile
- Un nuovo MCP richiede una skill di integrazione

## Input richiesto
Descrivi la skill da creare:
- **Nome**: snake_case (es. `create-feature`, `write-test`, `sync-clickup`)
- **Scopo**: cosa fa questa skill in una frase
- **Trigger**: quando un utente dovrebbe usarla
- **Destinazione**: shared (comune a tutti i template) o specifica di un dominio?

## Procedura

1. **Determina la destinazione**
   Chiedi: "Questa skill e' **shared** (comune a tutti i template) o **specifica** di un dominio?"
   - Se **shared**: la skill verra' creata in `shared/skills/<nome>/SKILL.md`
   - Se **specifica**: chiedi quale template (elenca `templates/*/`) e crea in `templates/<dominio>/.claude/skills/<nome>/SKILL.md`

2. **Crea branch**
   ```
   feat/skill-<nome-skill>
   ```

3. **Determina la categoria**
   - `workflow/` — skill che orchestrano processi multi-step
   - `codegen/` — skill che generano codice boilerplate
   - `integration/` — skill che interagiscono con MCP esterni
   - `quality/` — skill per review, testing, validazione

4. **Crea il file skill**
   Struttura obbligatoria:
   ```markdown
   ---
   name: <nome>
   description: <una frase che descrive cosa fa>
   user-invocable: true|false
   disable-model-invocation: true|false
   ---

   # Skill: <Nome>

   ## Scopo
   Una frase che descrive cosa fa.

   ## Quando usarla
   - Situazione 1
   - Situazione 2

   ## Pre-condizioni
   - Lista di condizioni che devono essere vere prima di eseguire

   ## Procedura
   1. Passo 1
   2. Passo 2
   ...

   ## Output atteso
   Descrizione dell'output.

   ## Esempi
   (opzionale) Casi d'uso concreti.
   ```

5. **Aggiorna il manifest** (se skill specifica di un dominio)
   Aggiungi il nome della skill a `template_skills` in `templates/<dominio>/manifest.json`.
   Se shared, aggiungi a `shared_skills` nei manifest dei template rilevanti.

6. **Aggiorna CHANGELOG**

7. **Apri PR**
   - Titolo: `feat(skill): add <nome> skill`
   - Label: `skill`
