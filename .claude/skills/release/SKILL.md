---
name: release
description: Pubblica una nuova versione di un template sul repo di distribuzione
user-invocable: true
disable-model-invocation: true
---

# /project:release

Pubblica una nuova versione di un template sul repo di distribuzione.

## Quando usarlo
- Dopo aver completato e mergiato le modifiche a un template
- Prima di un deploy o annuncio al team

## Input richiesto
- **Tipo release**: `patch` | `minor` | `major` (opzionale — se non specificato, viene chiesto)
- **Template**: nome del template (opzionale — se non specificato, viene elencata la lista)

## Procedura

1. **Seleziona il template**
   - Elenca le directory in `templates/` che contengono un `manifest.json`
   - Se c'e' un solo template, selezionalo automaticamente
   - Se ce ne sono piu' di uno, chiedi quale rilasciare
   - Leggi `manifest.json` per ottenere `agent` e `description`

2. **Valida il template**
   Lancia l'agent `validate-template` con:
   - TEMPLATE_NAME: `<TEMPLATE_NAME>`
   - SOURCE_CONSTITUTION_PATH: `./CONSTITUTION.md`
   Se STATUS non e' `pass`, fermati e mostra i problemi.

3. **Chiedi tipo release**
   Se non specificato: `patch`, `minor`, o `major`?

4. **Genera dist/**
   - Copia `templates/<TEMPLATE_NAME>/<manifest.agent>` → `dist/agents/<manifest.agent>`
   - Verifica che `dist/setup.md` sia aggiornato

5. **Esegui lo script di release**
   ```bash
   bash scripts/release-template.sh <tipo> <TEMPLATE_NAME>
   ```

6. **Mostra risultato**
   Comunica il link alla GitHub Release e il comando curl per il setup.

## Flusso di release

```
ai-setup-meta (sorgente)
    ↓ bash scripts/release-template.sh [type] [template-name]
    ↓ copia dist/ (setup.md + agents/) → repo distribuzione
    ↓ crea tag + GitHub Release
Repo distribuzione (unico per tutti i domini)
    ↓ curl per scaricare setup.md + agents
Progetto sviluppatore/PM
```

## Nota su semantic-release nei progetti dei developer

Per i progetti greenfield, il setup agent (passo 9.6 dell'agent di dominio dev)
genera il workflow CI/CD (`.github/workflows/release.yml`) al momento del
bootstrap. Le release dei singoli progetti dei developer sono
**automatizzate via CI** — non serve questo comando per quei progetti.
