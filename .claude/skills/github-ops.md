# Skill: GitHub Operations

Operazioni Git e GitHub tramite MCP. Usare sempre questa skill invece di
eseguire operazioni GitHub manualmente o via curl.

## Pre-condizioni
- MCP GitHub configurato e autenticato (`GITHUB_TOKEN` in `.env.local`)
- Variabile `GITHUB_ORG` settata

## Operazioni disponibili

### Creare un branch
```
Usa il MCP GitHub per creare un branch.
Input: nome branch (seguire naming convention da AGENT.md)
Base: sempre `main` salvo indicazioni diverse
```

### Aprire una Pull Request
```
Usa il MCP GitHub per aprire una PR.
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
Usa il MCP GitHub per creare un tag annotato e una Release.
Input: tag name, title, body (dal CHANGELOG)
```

### Verificare stato PR
```
Usa il MCP GitHub per controllare se una PR è aperta/mergeata/chiusa.
Utile prima di operazioni che dipendono dallo stato delle PR.
```

## Regole
- Non usare `git push --force` in nessuna circostanza
- Non pushare direttamente su `main`
- Verificare sempre che il branch locale sia aggiornato prima di operazioni
