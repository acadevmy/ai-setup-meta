Build del plugin Claude Code per un template.

Legge il `manifest.json` del template e produce un plugin self-contained in `dist/`.

## Istruzioni

1. Se l'utente non ha specificato un template, elenca quelli disponibili in `templates/` e chiedi quale usare
2. Esegui lo script di build:
   ```bash
   bash scripts/build-plugin.sh <template-name>
   ```
3. Verifica l'output in `dist/<template-name>/` e riporta il riepilogo (skills, agents, hooks)
4. Se la build fallisce, analizza l'errore e suggerisci la correzione
