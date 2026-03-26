Release di un plugin: bump versione, build, changelog, commit, tag, push e GitHub Release.

## Prerequisiti
- Essere su branch `main` con working tree pulito
- `gh` CLI autenticata
- `jq` installato

## Istruzioni

1. Chiedi all'utente il tipo di release se non specificato: `patch` (default), `minor`, o `major`
2. Chiedi conferma del template se non specificato
3. Esegui lo script di release:
   ```bash
   bash scripts/release-plugin.sh <tipo> <template-name> --yes
   ```
4. Se lo script fallisce, analizza l'errore e suggerisci la correzione
5. Al termine, riporta: tag creato, versione, link alla GitHub Release
