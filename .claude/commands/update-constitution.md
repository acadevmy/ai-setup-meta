# /project:update-constitution

Aggiorna `CONSTITUTION.md` con le modifiche specificate e propaga al `dev-setup-template`.

## Quando usarlo
- Aggiunta o modifica di regole tecniche
- Aggiornamento versioni di librerie obbligatorie
- Correzione di regole esistenti

## Input richiesto
Descrivi la modifica da apportare:
- Quale regola aggiungere / modificare / rimuovere
- Motivazione
- Sezione di riferimento (I–VIII)

## Procedura

1. **Crea branch**
   ```
   feat/constitution-<descrizione-breve>
   ```

2. **Analizza la modifica richiesta**
   - Verifica che non sia in contrasto con regole esistenti
   - Identifica la sezione corretta
   - Prepara esempi di codice (✅ corretto / ❌ vietato) se applicabile

3. **Modifica `CONSTITUTION.md`**
   - Aggiorna il numero di versione (patch per correzioni, minor per nuove regole)
   - Aggiorna la data "Aggiornato"

4. **Propaga al template**
   - Copia `CONSTITUTION.md` in `templates/dev-setup-template/CONSTITUTION.md`
   - Aggiorna `templates/dev-setup-template/CHANGELOG.md`

5. **Apri PR**
   - Titolo: `feat(constitution): <descrizione modifica>`
   - Label: `constitution`
   - Descrizione: regola aggiunta/modificata + motivazione

## ⚠️ Nota importante
Questo comando **non** approva automaticamente le modifiche alla Costituzione.
La PR richiede approvazione umana esplicita prima del merge.
Nessun agente può auto-approvare modifiche a `CONSTITUTION.md`.
