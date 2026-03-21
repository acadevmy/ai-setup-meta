# /project:release

Notifica il team dopo la pubblicazione di una nuova versione del `dev-setup-template`.

## Quando usarlo
- **Dopo** aver eseguito `bash scripts/release-template.sh` con successo
- Lo script ha gia' sincronizzato i file, creato tag e GitHub Release sul repo template
- Questo comando si occupa solo della **notifica al team su ClickUp**

## Contesto

Il flusso di release e' a due repo:

```
ai-setup-meta (sorgente)
    │
    │ bash scripts/release-template.sh minor
    │ → copia templates/dev-setup-template/ → repo template
    │ → tag + GitHub Release
    ▼
dev-setup-template (repo GitHub separato)
    │
    │ "Use this template" o clone
    ▼
Repo progetto sviluppatore
```

## Procedura

1. **Recupera la versione appena rilasciata**
   Leggi `TEMPLATE_VERSION` da `.env.example` per conoscere la versione corrente.
   Leggi `GITHUB_ORG` e `GITHUB_TEMPLATE_REPO` da `.env.local` per il link.

2. **Notifica il team**
   Crea un task in ClickUp nella lista `${CLICKUP_SETUP_LIST_ID}` con:
   - Titolo: `[AI Setup] Aggiornare dev-setup alla vX.Y.Z`
   - Descrizione:
     ```markdown
     Nuova versione del dev-setup-template disponibile.

     **Release**: https://github.com/ORG/REPO/releases/tag/vX.Y.Z

     **Come aggiornare:**
     Per progetti esistenti, eseguire nel proprio repo:
     1. Verificare la versione corrente nel CHANGELOG.md
     2. Scaricare i file aggiornati dalla release
     3. Rieseguire `bash init.sh` per applicare le modifiche

     Per nuovi progetti: usare "Use this template" su GitHub.
     ```
   - Assegna a: tutti gli sviluppatori del team

## Nota su semantic-release nei progetti dei developer

I progetti generati dal template includono semantic-release configurato
(`.releaserc.json` + `.github/workflows/release.yml`). Le release dei
singoli progetti dei developer sono **automatizzate via CI** — non serve
questo comando per quei progetti.

## Output atteso
- Task ClickUp creato per notificare il team
