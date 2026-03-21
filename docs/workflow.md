# Workflow operativo

Guida pratica su come Claude Code opera nel meta-repo e come il maintainer
interagisce con esso giorno per giorno.

## Ciclo di vita tipico di una modifica

```
Maintainer individua un miglioramento
         │
         ▼
  Crea branch di lavoro
  git checkout -b feat/descrizione
         │
         ▼
  Avvia Claude Code: claude
         │
         ▼
  Esegue il comando slash appropriato:
  /project:update-constitution  (se modifica regole)
  /project:new-skill            (se nuova skill)
  /project:sync-profiles        (se aggiorna stack)
         │
         ▼
  Claude Code lavora in autonomia:
  - Crea/modifica file
  - Valida con validate-setup
  - Aggiorna CHANGELOG
  - Apre PR via GitHub MCP
         │
         ▼
  Maintainer revisiona la PR su GitHub
         │
         ▼
  Merge → /project:release (quando pronto)
         │
         ▼
  Team sviluppatori notificati via ClickUp
```

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

### Rilasciare una nuova versione del template
```bash
# Assicurarsi di essere su main aggiornato
git checkout main && git pull
bash scripts/release-template.sh minor   # o patch / major
# Poi in Claude Code per notificare su ClickUp:
claude
/project:release
```

## Regole per il maintainer

1. **Non operare mai su `main` direttamente** — sempre branch + PR
2. **Leggere ogni PR di Claude** prima di approvarla — la responsabilità resta umana
3. **Non approvare PR che modificano `CONSTITUTION.md`** senza una review attenta
4. **Aggiornare `AGENT.md`** se cambiano strumenti, profili o processi del team
5. **Testare `init.sh`** su una macchina pulita prima di ogni release minor/major

## Gestione degli errori di Claude Code

Se Claude Code fa qualcosa di inatteso:

1. **Non fare merge della PR** — chiuderla senza merge
2. Analizzare cosa è andato storto nell'`AGENT.md` o nei comandi slash
3. Correggere le istruzioni e riprovare
4. Se il problema è ricorrente, aprire una PR per migliorare il prompt

## Branch protection consigliata (GitHub Settings)

Per il repo `ai-setup-meta`, abilitare:
- ✅ Require a pull request before merging
- ✅ Require approvals: 1
- ✅ Dismiss stale pull request approvals when new commits are pushed
- ✅ Require status checks to pass (se configurate GitHub Actions)
- ✅ Do not allow bypassing the above settings
