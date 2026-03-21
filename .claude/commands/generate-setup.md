# /project:generate-setup

Genera o rigenera il `dev-setup-template` completo a partire dalle sorgenti di questo repo.

## Quando usarlo
- Prima creazione del template
- Dopo modifiche sostanziali alla struttura che richiedono rigenerazione completa
- Su richiesta esplicita del maintainer

## Procedura

1. **Verifica pre-esecuzione**
   - Controlla di non essere su `main`
   - Crea branch `chore/regenerate-setup-template` se non esiste
   - Leggi `CONSTITUTION.md` per vincoli aggiornati
   - Leggi tutti i profili in `profiles/` per avere lo stack completo

2. **Genera la struttura base**
   Crea o aggiorna `templates/dev-setup-template/` con:
   - `CONSTITUTION.md` — copia esatta da questo repo (non editare)
   - `AGENT.md` — versione per sviluppatori (tono diverso, scope limitato)
   - `init.sh` — script con menu interattivo per selezione stack
   - `mcp.json.example` — template MCP senza chiavi
   - `.env.example` — variabili richieste senza valori
   - `CHANGELOG.md` — inizializza con versione corrente

3. **Genera configurazione Claude Code**
   Crea `.claude/` con:
   - `settings.json` — permessi per sviluppatori (più restrittivi di questo repo)
   - `commands/` — slash commands per sviluppatori (workflow TDD, ClickUp sync, ecc.)

4. **Genera configurazione qualità**
   - `.husky/pre-commit` — ESLint + Prettier
   - `.husky/commit-msg` — Commitlint
   - `.commitlintrc.json` — configurazione conventional commits
   - `.prettierrc.json` — configurazione Prettier
   - `.eslintrc.base.json` — config ESLint base (estesa dai profili)
   - `.releaserc.json` — configurazione semantic-release (copia da template)
   - `.github/workflows/release.yml` — GitHub Action per release automatica (copia da template)

5. **Genera profili stack**
   Per ciascun profilo in `profiles/*.md`:
   - `profiles/web-frontend/` — config specifiche Next.js/Angular/React
   - `profiles/backend-node/` — config specifiche Node.js/NestJS
   - `profiles/mobile/` — config specifiche Flutter/React Native

6. **Validazione**
   Esegui la skill `validate-setup` per verificare coerenza

7. **Aggiorna CHANGELOG**
   Aggiungi entry in `templates/dev-setup-template/CHANGELOG.md`

8. **Apri PR**
   Usa GitHub MCP per aprire PR con:
   - Titolo: `chore(template): regenerate dev-setup-template vX.Y.Z`
   - Label: `template`
   - Descrizione: lista dei file generati/modificati

## Output atteso
PR aperta su GitHub con il template aggiornato, pronta per review.
