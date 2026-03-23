---
name: github-ops
description: Documentazione di riferimento per operazioni Git e GitHub (branch, PR, tag, release)
user-invocable: false
disable-model-invocation: false
---

# Skill: GitHub Operations

Operazioni Git e GitHub tramite `git` e `gh` CLI.
NON usare MCP GitHub — usare sempre i comandi diretti.

## Pre-condizioni
- `gh` CLI installata e autenticata (`gh auth login`)
- `git` configurato con user.name e user.email

## Operazioni disponibili

### Creare un branch
```
git checkout -b <tipo>/<customId>-<descrizione-breve>

Naming convention:
  - Prefisso: feat/, fix/, chore/, hotfix/
  - CustomId: il custom_id del task ClickUp (es. DE-123)
  - Descrizione: breve, in kebab-case, in inglese

Esempi:
  feat/DE-123-add-user-auth
  fix/DE-456-handle-null-response
  chore/DE-789-update-dependencies

Base: sempre `main` salvo indicazioni diverse
```

### Aprire una Pull Request
```
gh pr create --title "<titolo>" --body "<body>"
Campi obbligatori:
  - title: segue Conventional Commits, include customId — es. "feat(auth): add refresh token rotation [DE-123]"
  - body: include sezioni Cosa / Perché / Come testare
  - labels: uno tra [constitution, template, skill, profile, release]
  - base: main
  - head: branch corrente
```

Template body PR:
```markdown
## Cosa cambia
<descrizione delle modifiche>

## Perché
<motivazione>

## Come testare
- [ ] <passo 1>
- [ ] <passo 2>

## Checklist
- [ ] Nessun segreto o API key inclusi
- [ ] CHANGELOG aggiornato
- [ ] CONSTITUTION rispettata

## ClickUp
- Task: [DE-XXX](link al task)
```

### Creare un tag e una Release
```
git tag -a <tag> -m "<messaggio>"
git push origin <tag>
gh release create <tag> --title "<titolo>" --notes "<body dal CHANGELOG>"
```

### Verificare stato PR
```
gh pr view <numero> --json state
gh pr list --state open
```

## Regole
- Non usare `git push --force` in nessuna circostanza
- Non pushare direttamente su `main`
- Verificare sempre che il branch locale sia aggiornato prima di operazioni
