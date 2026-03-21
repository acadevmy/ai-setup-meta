# Skill: Validate Setup

Verifica la coerenza interna del `dev-setup-template` prima di aprire una PR.
Eseguire sempre prima di `/project:release`.

## Checklist di validazione

### 1. File obbligatori presenti
Verifica che esistano tutti questi file in `templates/dev-setup-template/`:
- [ ] `AGENT.md`
- [ ] `REGISTRY.md`
- [ ] `CONSTITUTION.md`
- [ ] `init.sh`
- [ ] `mcp.json.example`
- [ ] `.env.example`
- [ ] `CHANGELOG.md`
- [ ] `.claude/settings.json`
- [ ] `.husky/pre-commit`
- [ ] `.husky/commit-msg`
- [ ] `.commitlintrc.json`
- [ ] `.prettierrc.json`
- [ ] `.gitignore`

### 2. CONSTITUTION coerente
- [ ] `templates/dev-setup-template/CONSTITUTION.md` è identica a `CONSTITUTION.md` in questo repo
  ```bash
  diff CONSTITUTION.md templates/dev-setup-template/CONSTITUTION.md
  # Deve restituire nessun output
  ```

### 3. Nessun segreto nei file tracciati
Cerca pattern di chiavi API nei file del template:
```bash
grep -r "sk-" templates/dev-setup-template/
grep -r "pk_" templates/dev-setup-template/
grep -r "ghp_" templates/dev-setup-template/
grep -r "AKIA" templates/dev-setup-template/
```
Tutti devono restituire nessun output.

### 4. .gitignore corretto
Verifica che `.env.local` e altri file sensibili siano in `.gitignore`:
- [ ] `.env.local`
- [ ] `.env*.local`
- [ ] `node_modules/`
- [ ] `.claude/todos.md`

### 5. init.sh eseguibile e completo
- [ ] Il file ha permessi di esecuzione (`chmod +x`)
- [ ] Contiene menu per selezione profilo: `web-frontend`, `backend-node`, `mobile`
- [ ] Ogni profilo installa le dipendenze corrette
- [ ] Lo script termina con istruzioni di verifica

### 6. mcp.json.example senza chiavi reali
- [ ] Tutti i valori sono placeholder (`${VARIABILE}` o `"your-key-here"`)
- [ ] Sono presenti tutti e 4 i MCP: github, clickup, figma, context7

### 7. CHANGELOG aggiornato
- [ ] L'ultima versione in CHANGELOG corrisponde a `TEMPLATE_VERSION` in `.env.example`

### 8. REGISTRY.md struttura valida
- [ ] Contiene l'header `# REGISTRY.md`
- [ ] Contiene le sezioni: `## Feature`, `## Servizi e utility`, `## Componenti UI`, `## Decisioni architetturali`
- [ ] Contiene la sezione `## Convenzioni` con il formato entry documentato
- [ ] Nessun placeholder `{{...}}` non risolto

## Come eseguire la validazione
Chiedi all'agente di eseguire i comandi `diff` e `grep` sopra elencati
e di verificare manualmente la lista dei file. Riportare qualsiasi discrepanza
prima di procedere con la PR.
