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
  - Conventional commit subject (feat:/fix:/feat!:/etc.)
  - build-verify.yml controlla che dist/ sia in sync
         │
         ▼
  Review + squash-merge su main (build-verify verde)
         │
         ▼
  release-please.yml automatico su push su main:
  - parse dei conventional commits dall'ultimo tag dev-setup-v*
  - calcola bump type (major/minor/patch) o niente (per docs:/chore:/ecc.)
  - se ci sono commit rilevanti, apre/aggiorna una "release PR" running:
      - bump versione in templates/dev-setup/.env.example (marker x-release-please-version)
      - bump version in dist/dev-setup/.{claude,cursor}-plugin/plugin.json
      - aggiorna .release-please-manifest.json
      - genera/aggiorna sezione "## [X.Y.Z]" in templates/dev-setup/CHANGELOG.md
        (raggruppata per Features / Bug Fixes / Documentation / ecc.)
         │
         ▼
  Maintainer rivede la release PR (puo' attendere accumulo di piu'
  PR feature — release-please aggiorna la PR ad ogni push su main)
         │
         ▼
  Merge della release PR su main
         │
         ▼
  release-please.yml di nuovo:
  - tag annotato dev-setup-vX.Y.Z
  - GitHub Release con il diff della sezione CHANGELOG come body
  - rebuild di dist/ e commit ("chore(dist): rebuild after release ...")
```

## Come funziona il release

Il release flow usa [release-please](https://github.com/googleapis/release-please) (action ufficiale Google, battle-tested). Su ogni push su `main`, l'action analizza i conventional commits dall'ultimo tag e:

- Apre o aggiorna una "release PR" running con bump versione + CHANGELOG generato
- Al merge della release PR, crea tag annotato + GitHub Release

Niente push diretto su `main`, niente trigger manuale, niente bash custom. Due workflow:

1. **`release-please.yml`** — gira su ogni push su `main`. Action: `googleapis/release-please-action@v4`.
2. **`build-verify.yml`** — gira su ogni PR. Verifica che `dist/` sia in sync con la sorgente.

### Configurazione release-please

- **`release-please-config.json`** (root) — definisce il package, gli `extra-files` da bumpare, il path del CHANGELOG. Single-package mode con root come scope.
- **`.release-please-manifest.json`** (root) — versione corrente. release-please la aggiorna automaticamente; non editare a mano.

`extra-files` configurati per il bump della versione:

- `templates/dev-setup/.env.example` — riconosciuto via marker comment `# x-release-please-version`
- `dist/dev-setup/.claude-plugin/plugin.json` — JSON path `$.version`
- `dist/dev-setup/.cursor-plugin/plugin.json` — JSON path `$.version`

I file `.claude-plugin/marketplace.json` e `.cursor-plugin/marketplace.json` non hanno il campo `version` per plugin: Claude Code/Cursor leggono la versione da `dist/<plugin>/.{claude,cursor}-plugin/plugin.json` come fallback.

### Verifica del build (PR check)

`build-verify.yml` gira su ogni PR che tocca `templates/`, `shared/`, `scripts/builders/`, marketplace files, o `dist/`:

- Esegue `bash scripts/build-plugin.sh <template>`
- Fallisce se `git diff` rileva differenze rispetto a `dist/` committato

Cattura il caso in cui qualcuno modifica `templates/` ma dimentica di rebuildare `dist/`.

### Override manuale del bump type

release-please ha un comando per forzare il release type tramite "release-as" footer in un commit:

```
feat(profile): add some feature

Release-As: 2.0.0
```

In alternativa puoi scrivere `release-please-action`-style annotations (vedi [docs ufficiali](https://github.com/googleapis/release-please#how-do-i-change-the-version-number)).

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

Niente azioni esplicite richieste:

1. Mergea le tue PR feature/fix con commit conventional (`feat:`, `fix:`, ecc.). release-please apre o aggiorna automaticamente una release PR ad ogni push su `main`.
2. Quando vuoi pubblicare, mergea la release PR. release-please crea tag e GitHub Release in automatico.

Per forzare una versione specifica (override): aggiungi `Release-As: X.Y.Z` nel footer di un commit.

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
