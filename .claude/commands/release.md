# /project:release

Tagga e pubblica una nuova versione del `dev-setup-template` su GitHub.

## Quando usarlo
- Dopo una o più PR mergate che modificano il template
- Quando il team è pronto ad adottare le modifiche
- Seguire semantic versioning: MAJOR.MINOR.PATCH

| Tipo di modifica | Versione |
|---|---|
| Breaking change (struttura incompatibile) | MAJOR |
| Nuova feature/skill/profilo | MINOR |
| Bugfix, aggiornamento dipendenze | PATCH |

## Input richiesto
- **Tipo di release**: `major` / `minor` / `patch`
- **Descrizione**: riassunto delle modifiche (2-3 righe)

## Procedura

1. **Verifica stato repo**
   - Sei su `main` e il branch è aggiornato
   - Non ci sono PR aperte in attesa di merge che influenzano il template
   - Tutti i test passano

2. **Calcola la nuova versione**
   Leggi la versione corrente da `templates/dev-setup-template/CHANGELOG.md`
   e incrementa secondo il tipo di release.

3. **Aggiorna i file di versione**
   - `templates/dev-setup-template/CHANGELOG.md` — aggiungi sezione `## [X.Y.Z] - YYYY-MM-DD`
   - `.env.example` in questo repo — aggiorna `TEMPLATE_VERSION`

4. **Crea commit di release**
   ```
   chore(release): bump dev-setup-template to vX.Y.Z
   ```

5. **Crea tag**
   Usa GitHub MCP:
   ```
   tag: template-vX.Y.Z
   message: "Release dev-setup-template vX.Y.Z\n\n<descrizione>"
   ```

6. **Pubblica GitHub Release**
   Usa GitHub MCP per creare una Release con:
   - Tag: `template-vX.Y.Z`
   - Titolo: `dev-setup-template vX.Y.Z`
   - Body: contenuto della sezione CHANGELOG per questa versione
   - Allega: nessun artifact (il repo template è distribuito via clone)

7. **Notifica il team**
   Crea un task in ClickUp nella lista `${CLICKUP_SETUP_LIST_ID}` con:
   - Titolo: `[AI Setup] Aggiornare dev-setup alla v X.Y.Z`
   - Descrizione: link alla Release GitHub + istruzioni di aggiornamento
   - Assegna a: tutti gli sviluppatori del team

## Output atteso
- Tag `template-vX.Y.Z` creato su GitHub
- GitHub Release pubblicata
- Task ClickUp creato per notificare il team
