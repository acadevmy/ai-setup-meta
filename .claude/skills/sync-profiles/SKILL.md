---
name: sync-profiles
description: Sincronizza i profili stack nel template di dominio corrispondente
user-invocable: true
disable-model-invocation: true
---

# /project:sync-profiles

Sincronizza i profili stack nel template di dominio corrispondente.

## Quando usarlo
- Aggiornamento di versioni di librerie (es. Next.js 15, NestJS 11)
- Aggiunta di nuove configurazioni ESLint/TypeScript specifiche per stack
- Modifica delle regole Zod o Jest per uno specifico profilo

## Input richiesto

- **Template**: quale template aggiornare (es. `dev-setup`). Se non specificato, viene chiesto.
- **Profilo**: quale profilo aggiornare (o `all` per tutti). I profili disponibili vengono letti dal `manifest.json` del template scelto.

## Procedura

1. **Seleziona il template**
   Elenca i template disponibili in `templates/*/manifest.json`.
   Leggi il campo `profiles` dal manifest per sapere quali profili sono disponibili.

2. **Crea branch**
   ```
   chore/sync-profiles-<data>
   ```

3. **Per ogni profilo da aggiornare**

   a. Leggi `templates/<TEMPLATE_NAME>/profiles/<profilo>.md` per le specifiche aggiornate

   b. Aggiorna i file di configurazione generati nel template o nella sezione corrispondente
      dell'agent di dominio (`dist/setup.md` o `templates/<TEMPLATE_NAME>/<agent>`).

4. **Valida la coerenza**
   Lancia l'agent `validate-template` con TEMPLATE_NAME per verificare

5. **Aggiorna CHANGELOG**

6. **Apri PR**
   - Titolo: `chore(profiles): sync <profilo> stack configuration`
   - Label: `profile`
