# Workflow operativo

Guida pratica su come Claude Code opera nel meta-repo e come il maintainer
interagisce con esso giorno per giorno.

> **Ambito**: questo documento descrive il workflow **di manutenzione del plugin stesso**
> (il meta-repo `ai-setup-meta` e' ospitato su GitHub). Gli utenti finali del plugin
> possono lavorare su progetti GitHub **o** GitLab — vedi
> [developer-guide.md](./developer-guide.md) e [onboarding.md](./onboarding.md) per quel
> lato. I comandi `gh` qui sotto riguardano solo il release del plugin.

## Ciclo di vita tipico di una modifica

```
Contributor (umano o agent) apre branch + PR
  - Conventional commit: feat:/fix:/feat!:/etc.
  - Aggiunge entry in CHANGELOG.md sotto [Unreleased]
  - build-verify.yml controlla che dist/ sia in sync
         │
         ▼
  Review + merge su main (build-verify verde)
         │
         ▼
  auto-release.yml automatico su push su main:
  - calcola bump type (major/minor/patch) dai CC dall'ultimo tag
  - se ci sono commit rilevanti, force-recreate la "release PR" running
    (cut [Unreleased] -> [X.Y.Z], rebuild dist, push)
  - chiude eventuali release PR con versione obsoleta
         │
         ▼
  Maintainer rivede la release PR (eventualmente attende
  che si accumulino piu' PR feature, ognuna re-aggiorna la PR)
         │
         ▼
  Merge della release PR su main
         │
         ▼
  release-publish.yml automatico:
  - tag annotato dev-setup-vX.Y.Z
  - GitHub Release con sezione [X.Y.Z] del CHANGELOG come body
```

## Come funziona il release

Il release flow e' **completamente automatizzato via GitHub Actions**. Su ogni push su `main` con commit rilevanti, viene aperta (o aggiornata) una "release PR" running. Il maintainer la mergea quando ready; il merge crea tag + GitHub Release in automatico. Niente push diretto su `main`, niente release dal laptop, niente trigger manuale del workflow nel caso normale.

Tre componenti:

1. **Auto Release** (`auto-release.yml`) — su ogni push su `main`, calcola il bump type dai conventional commits e aggiorna la release PR running.
2. **Release - Prepare** (`release-prepare.yml`) — `workflow_dispatch` manuale come override se serve forzare patch/minor/major a mano. Stesso effetto di Auto Release ma con bump scelto a mano.
3. **Release - Publish** (`release-publish.yml`) — al merge della release PR, crea tag annotato + GitHub Release con la sezione `[X.Y.Z]` del CHANGELOG.

### Fase 0 — Conventional Commits durante le PR (la disciplina che fa girare tutto)

Ogni commit deve seguire CC 1.0. Il tipo determina il bump:

- `feat(...)` → `minor`
- `feat!:` o `BREAKING CHANGE:` nel body → `major`
- Tutti gli altri (`fix:`, `chore:`, `docs:`, `refactor:`, `perf:`, `style:`, `test:`, `ci:`) → `patch`
- Solo i commit che toccano `templates/dev-setup/`, `shared/`, `scripts/builders/`, `scripts/build-plugin.sh`, `scripts/release/` contano per il bump

Vedi [`AGENTS.md`](../AGENTS.md#tipi-e-impatto-sulla-release) per la tabella completa.

### Fase 1 — Auto Release apre/aggiorna la release PR

Su ogni `push` su `main`:

- `auto-release.yml` controlla i commit dall'ultimo tag `dev-setup-v*`
- Se ci sono cambi rilevanti, calcola il bump type
- Esegue `scripts/release/prepare-release.sh`
- **Force-recreate** del branch `release/dev-setup-vX.Y.Z` (running PR — riscritta ogni volta)
- Apre o refresha la PR

### Fase 1-bis (opzionale) — Override manuale

Se serve forzare il bump (es. release di emergenza con un solo `fix:` ma vuoi minor):

- Inputs: `release_type` (`patch` / `minor` / `major`) e `template` (default `dev-setup`).
- Il workflow `.github/workflows/release-prepare.yml` esegue `scripts/release/prepare-release.sh`, che:
  1. Calcola la nuova versione partendo da `templates/<template>/.env.example` (`TEMPLATE_VERSION`)
  2. **Cut del CHANGELOG**: rinomina `## [Unreleased]` in `## [X.Y.Z] - <data>` preservando la prosa verbatim, e re-inserisce un `[Unreleased]` vuoto sopra. **Non** ri-deriva entries dai messaggi di commit
  3. Aggiorna `version` in `.claude-plugin/marketplace.json` e `.cursor-plugin/marketplace.json`
  4. Aggiorna `TEMPLATE_VERSION` in `.env.example`
  5. Ricostruisce `dist/<template>/` via `scripts/build-plugin.sh`
- Il workflow committa tutto su un branch `release/<template>-vX.Y.Z` e apre una PR contro `main`.

### Fase 2 — Review + merge

La release PR e' un cambio normale: il maintainer la rivede, eventualmente edita la prosa del CHANGELOG (che ora vive in `## [X.Y.Z]`), e la mergea quando e' pronta.

Al merge il workflow `.github/workflows/release-publish.yml` esegue `scripts/release/publish-release.sh`, che:

1. Verifica che il branch corrisponda al pattern `release/<template>-v<X>.<Y>.<Z>` ed estrae template + versione
2. Crea un tag annotato `<template>-v<X>.<Y>.<Z>` puntato al merge commit
3. Pusha il tag a `origin`
4. Estrae la sezione `## [X.Y.Z]` dal CHANGELOG e la usa come body della GitHub Release (via `gh release create`)

### Fase 0 — Authoring delle entries di CHANGELOG durante le PR

Le entries del CHANGELOG **vengono scritte durante le PR feature/fix**, non al momento della release. Ogni contributor che apre una PR deve aggiungere una riga nella sezione `## [Unreleased]` di `templates/<template>/CHANGELOG.md` sotto `### Added` / `### Changed` / `### Fixed`. Esempio: una PR che aggiunge un nuovo profilo Terraform aggiunge `- add \`profiles/terraform.md\`` sotto `### Added`. Tieni le entries terse, in stile imperativo, una per riga — vedi le release storiche `[1.4.0]` e precedenti come riferimento.

Quando il workflow `Release - Prepare` gira, prende esattamente quelle entries e le promuove a `## [X.Y.Z]`. Non c'e' deduplicazione automatica: se le entries sono sbagliate o mancanti, lo saranno anche nella release.

### Verifica del build (PR check)

Ogni PR contro `main` che tocca `templates/`, `shared/`, `scripts/builders/`, `.{claude,cursor}-plugin/` o `dist/` triggera `.github/workflows/build-verify.yml`, che:

- Esegue `bash scripts/build-plugin.sh <template>`
- Fallisce se `git diff` rileva differenze rispetto a `dist/` committato

Cattura il caso in cui qualcuno modifica `templates/` ma dimentica di rebuildare `dist/`.

### Wrapper locale (`scripts/release-plugin.sh`)

Esiste solo per emergenze in cui le GitHub Actions non sono disponibili. Esegue prepare + push diretto su `main` + publish in sequenza, **bypassando la review della PR**. Da usare con consapevolezza.

## Operazioni frequenti

### Aggiungere una regola alla Costituzione
```bash
git checkout -b feat/constitution-nuova-regola
claude
# In Claude Code:
/project:update-constitution
# Descrivere la modifica quando richiesto
```

### Aggiornare le versioni di una libreria
```bash
git checkout -b chore/aggiornamento-stack-web
claude
# In Claude Code:
/project:sync-profiles
# Scegliere il profilo da aggiornare
```

### Rigenerare il setup agent
```bash
git checkout -b chore/regen-setup
claude
# In Claude Code:
/project:generate-setup
# Verifica e commita il dist/setup.md aggiornato
```

### Rilasciare una nuova versione del plugin

**Path standard** (auto, niente click):

1. Mergea le tue PR feature/fix con commit conventional. Auto Release apre/aggiorna automaticamente una release PR ad ogni merge.
2. Quando vuoi pubblicare, mergea la release PR. `Release - Publish` crea tag + GitHub Release.

**Path manuale** (override del bump type via dispatch):

1. Vai su **Actions → "Release - Prepare" → Run workflow**
2. Seleziona `release_type` e `template`
3. Esattamente come Auto Release, ma con bump type forzato

**Path di emergenza** (locale, bypassa review e Actions):
```bash
git checkout main && git pull
bash scripts/release-plugin.sh minor dev-setup   # o patch / major
```

## Setup iniziale del repo di distribuzione

La prima volta che si esegue `release-template.sh`, lo script:
1. Verifica se il repo `GITHUB_ORG/GITHUB_DIST_REPO` esiste su GitHub
2. Se non esiste, offre di crearlo automaticamente con `gh repo create`
3. Pubblica la prima versione

## Regole per il maintainer

1. **Non operare mai su `main` direttamente** — sempre branch + PR
2. **Leggere ogni PR di Claude** prima di approvarla — la responsabilita' resta umana
3. **Non approvare PR che modificano `CONSTITUTION.md`** senza una review attenta
4. **Aggiornare `AGENTS.md`** se cambiano strumenti, profili o processi del team
5. **Testare `/project:setup`** su un progetto pulito prima di ogni release minor/major
6. **Non modificare mai il repo template direttamente** — usare sempre il meta-repo

## Gestione degli errori di Claude Code

Se Claude Code fa qualcosa di inatteso:

1. **Non fare merge della PR** — chiuderla senza merge
2. Analizzare cosa e' andato storto nell'`AGENTS.md` o nei comandi slash
3. Correggere le istruzioni e riprovare
4. Se il problema e' ricorrente, aprire una PR per migliorare il prompt

## Branch protection consigliata (GitHub Settings)

### Per il meta-repo (`ai-setup-meta`)
- Require a pull request before merging
- Require approvals: 1
- Dismiss stale pull request approvals when new commits are pushed
- Require status checks to pass (se configurate GitHub Actions)
- Do not allow bypassing the above settings

### Per il repo di distribuzione (`dev-setup-template`)
- Nessuna branch protection necessaria — il repo viene aggiornato solo dallo script di release
