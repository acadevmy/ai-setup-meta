# Workflow operativo

Guida pratica su come Claude Code opera nel meta-repo e come il maintainer
interagisce con esso giorno per giorno.

## Ciclo di vita tipico di una modifica

```
Maintainer individua un miglioramento
         │
         ▼
  Crea branch di lavoro
  git checkout -b feat/DE-123-descrizione
         │
         ▼
  Avvia Claude Code: claude
         │
         ▼
  Esegue il comando slash appropriato:
  /project:update-constitution  (se modifica regole)
  /project:new-skill            (se nuova skill)
  /project:sync-profiles        (se aggiorna stack)
  /project:generate-setup       (se rigenera il setup agent)
         │
         ▼
  Claude Code lavora in autonomia:
  - Crea/modifica file in templates/dev-setup-template/
  - Valida con validate-setup
  - Aggiorna CHANGELOG
  - Apre PR via gh CLI
         │
         ▼
  Maintainer revisiona la PR su GitHub
         │
         ▼
  Merge su main
         │
         ▼
  bash scripts/release-template.sh minor
  → Sincronizza verso il repo template separato
  → Crea tag + GitHub Release
         │
         ▼
  /project:release → notifica il team su ClickUp
```

## Come funziona il release

Il release script (`scripts/release-template.sh`) pubblica il **setup agent** sul repo template.
Il repo template contiene solo l'entry point per il bootstrap — non l'intero contenuto di
`templates/dev-setup-template/`. I file del template vengono scaricati a runtime dal setup agent.

Il flusso:

1. Verifica prerequisiti (`gh` CLI, `.env.local`, branch `main` pulito)
2. Valida gli URL nel setup agent (`scripts/validate-setup-urls.sh`)
3. Calcola la nuova versione (semver)
4. Aggiorna `templates/dev-setup-template/CHANGELOG.md` e `.env.example` nel meta-repo
5. Crea commit nel meta-repo: `chore(release): bump dev-setup-template to vX.Y.Z`
6. Clona il repo template (`GITHUB_ORG/GITHUB_TEMPLATE_REPO`)
7. Copia **solo 3 file** nel repo template:
   - `.claude/skills/setup/SKILL.md` (da `dist/setup.md`)
   - `README.md` (generato dallo script)
   - `CHANGELOG.md`
8. Commit, tag e push sul repo template
9. Push del meta-repo
10. Crea la GitHub Release con `gh release create`

**Il repo template non va mai modificato direttamente.** Ogni modifica parte
dal meta-repo e viene pubblicata con il release script.

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

### Creare una nuova skill per gli sviluppatori
```bash
git checkout -b feat/skill-nome-skill
claude
# In Claude Code:
/project:new-skill
# Descrivere nome, scopo e stack applicabile
```

### Rigenerare il setup agent
```bash
git checkout -b chore/regen-setup
claude
# In Claude Code:
/project:generate-setup
# Verifica e commita il dist/setup.md aggiornato
```

### Rilasciare una nuova versione del template
```bash
# Assicurarsi di essere su main aggiornato
git checkout main && git pull

# Pubblica sul repo template
bash scripts/release-template.sh minor   # o patch / major

# Notifica il team su ClickUp
claude
/project:release
```

## Setup iniziale del repo template

La prima volta che si esegue `release-template.sh`, lo script:
1. Verifica se il repo `GITHUB_ORG/GITHUB_TEMPLATE_REPO` esiste su GitHub
2. Se non esiste, offre di crearlo automaticamente con `gh repo create`
3. Pubblica la prima versione

Dopo la creazione, si consiglia di:
- Andare su GitHub > Settings del repo template
- Spuntare **"Template repository"** per abilitare "Use this template"

## Regole per il maintainer

1. **Non operare mai su `main` direttamente** — sempre branch + PR
2. **Leggere ogni PR di Claude** prima di approvarla — la responsabilita' resta umana
3. **Non approvare PR che modificano `CONSTITUTION.md`** senza una review attenta
4. **Aggiornare `AGENT.md`** se cambiano strumenti, profili o processi del team
5. **Testare `/project:setup`** su un progetto pulito prima di ogni release minor/major
6. **Non modificare mai il repo template direttamente** — usare sempre il meta-repo

## Gestione degli errori di Claude Code

Se Claude Code fa qualcosa di inatteso:

1. **Non fare merge della PR** — chiuderla senza merge
2. Analizzare cosa e' andato storto nell'`AGENT.md` o nei comandi slash
3. Correggere le istruzioni e riprovare
4. Se il problema e' ricorrente, aprire una PR per migliorare il prompt

## Branch protection consigliata (GitHub Settings)

### Per il meta-repo (`ai-setup-meta`)
- Require a pull request before merging
- Require approvals: 1
- Dismiss stale pull request approvals when new commits are pushed
- Require status checks to pass (se configurate GitHub Actions)
- Do not allow bypassing the above settings

### Per il repo template (`dev-setup-template`)
- Nessuna branch protection necessaria — il repo viene aggiornato solo dallo script di release
- Abilitare "Template repository" nelle Settings per permettere "Use this template"
