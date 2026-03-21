# Skill: GitHub Operations

Operazioni Git e GitHub tramite `git` e `gh` CLI.
NON usare MCP GitHub — usare sempre i comandi diretti.

## Pre-condizioni
- `gh` CLI installata e autenticata (`gh auth login`)
- `git` configurato con user.name e user.email

## Operazioni disponibili

### Creare un branch
```
git checkout -b <nome-branch>
Naming convention: vedi AGENT.md
Base: sempre `main` salvo indicazioni diverse
```

### Aprire una Pull Request
```
gh pr create --title "<titolo>" --body "<body>"
Campi obbligatori:
  - title: segue Conventional Commits
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
