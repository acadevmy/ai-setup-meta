---
name: new-skill
description: Scaffolda una nuova skill da aggiungere al dev-setup-template
user-invocable: true
disable-model-invocation: true
---

# /project:new-skill

Scaffolda una nuova skill da aggiungere al `dev-setup-template`.

## Quando usarlo
- Il team ha un pattern ripetuto che vale la pena automatizzare
- Un processo multi-step può essere codificato come skill riutilizzabile
- Un nuovo MCP richiede una skill di integrazione

## Input richiesto
Descrivi la skill da creare:
- **Nome**: snake_case (es. `create-feature`, `write-test`, `sync-clickup`)
- **Scopo**: cosa fa questa skill in una frase
- **Trigger**: quando uno sviluppatore dovrebbe usarla
- **Stack**: si applica a tutti i profili o solo ad alcuni?

## Procedura

1. **Crea branch**
   ```
   feat/skill-<nome-skill>
   ```

2. **Determina la categoria**
   - `workflow/` — skill che orchestrano processi multi-step
   - `codegen/` — skill che generano codice boilerplate
   - `integration/` — skill che interagiscono con MCP esterni
   - `quality/` — skill per review, testing, validazione

3. **Crea il file skill**
   Path: `templates/dev-setup-template/.claude/skills/<categoria>/<nome>.md`

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

   ## Stack applicabili
   - [ ] Web Frontend (Next.js, Angular, React)
   - [ ] Backend (Node.js, NestJS)
   - [ ] Mobile (Flutter, React Native)
   - [ ] Tutti

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

4. **Aggiungi la skill anche a `.claude/skills/` di questo meta-repo**
   se la skill è utile anche per il maintainer del meta-repo.

5. **Aggiorna `templates/dev-setup-template/AGENT.md`**
   Aggiungi la skill alla tabella "Skill disponibili".

6. **Aggiorna CHANGELOG**

7. **Apri PR**
   - Titolo: `feat(skill): add <nome> skill`
   - Label: `skill`
