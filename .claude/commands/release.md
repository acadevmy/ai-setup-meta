# /project:release

Esegue la release di una nuova versione del `dev-setup-template`.

## Quando usarlo
- Quando vuoi pubblicare una nuova versione del template
- Lo script si occupa di: sync file, tag, push, GitHub Release

## Contesto

Il flusso di release e' a due repo:

```
ai-setup-meta (sorgente)
    |
    | bash scripts/release-template.sh [patch|minor|major]
    | -> copia templates/dev-setup-template/ -> repo template
    | -> tag + GitHub Release
    v
dev-setup-template (repo GitHub separato)
    |
    | "Use this template" o clone
    v
Repo progetto sviluppatore
```

## Procedura

1. **Chiedi il tipo di release** se non specificato dall'utente: `patch`, `minor` o `major`
2. **Esegui lo script**: `bash scripts/release-template.sh <tipo>`
3. **Mostra il risultato** con il link alla GitHub Release

## Nota su semantic-release nei progetti dei developer

I progetti generati dal template includono semantic-release configurato
(`.releaserc.json` + `.github/workflows/release.yml`). Le release dei
singoli progetti dei developer sono **automatizzate via CI** — non serve
questo comando per quei progetti.

## Output atteso
- GitHub Release creata sul repo template
- Link alla release mostrato all'utente
