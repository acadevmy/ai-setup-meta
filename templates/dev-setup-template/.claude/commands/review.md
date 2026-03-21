# /project:review

Esegui una code review del codice modificato nel branch corrente.

## Procedura

1. **Identifica le modifiche**
   - Esegui `git diff main...HEAD` per vedere tutti i cambiamenti
   - Analizza ogni file modificato

2. **Verifica conformita' CONSTITUTION.md**
   - Schema-first: i dati esterni sono validati con lo schema validator del progetto?
     (Zod per TypeScript, Pydantic per Python, struct tags per Go, ecc.)
   - Strict typing: il codice usa tipi stretti senza bypass?
     (no `any` in TS, no `# type: ignore` in Python, no `interface{}` in Go, ecc.)
   - Gestione errori: ci sono `catch`/`except` vuoti?
   - Funzioni pure e piccole: qualche funzione supera le 40 righe?
   - Magic numbers/strings: ci sono valori hardcoded?

3. **Verifica qualità**
   - I test coprono i casi principali?
   - I nomi sono descrittivi e in inglese?
   - La struttura dei layer è rispettata?

4. **Output**
   Fornisci un report con:
   - Lista dei problemi trovati (con file e riga)
   - Suggerimenti di miglioramento
   - Conferma di conformità se tutto ok
