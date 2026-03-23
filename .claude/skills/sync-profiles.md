---
name: sync-profiles
description: Sincronizza i profili stack da profiles/ nel dev-setup-template
user-invocable: true
disable-model-invocation: true
---

# /project:sync-profiles

Sincronizza i profili stack da `profiles/` nel `dev-setup-template`.

## Quando usarlo
- Aggiornamento di versioni di librerie (es. Next.js 15, NestJS 11)
- Aggiunta di nuove configurazioni ESLint/TypeScript specifiche per stack
- Modifica delle regole Zod o Jest per uno specifico profilo

## Input richiesto
Specifica quale profilo aggiornare (o `all` per tutti):
- `web-frontend` — Next.js, Angular, React
- `backend-node` — Node.js, NestJS
- `mobile` — Flutter, React Native
- `all` — tutti i profili

## Procedura

1. **Crea branch**
   ```
   chore/sync-profiles-<data>
   ```

2. **Per ogni profilo da aggiornare**

   a. Leggi `profiles/<profilo>.md` per le specifiche aggiornate

   b. Aggiorna `templates/dev-setup-template/profiles/<profilo>/`:
      - `eslint.config.js` — regole ESLint specifiche del profilo
      - `tsconfig.json` — configurazione TypeScript del profilo
      - `jest.config.ts` — configurazione Jest del profilo
      - `README.md` — istruzioni di attivazione del profilo

   c. Aggiorna `templates/dev-setup-template/init.sh`:
      - Verifica che il menu di selezione profilo sia aggiornato
      - Verifica che i comandi di installazione dipendenze siano corretti

3. **Valida la coerenza**
   Esegui la skill `validate-setup` per ogni profilo aggiornato

4. **Aggiorna CHANGELOG**

5. **Apri PR**
   - Titolo: `chore(profiles): sync <profilo> stack configuration`
   - Label: `profile`
