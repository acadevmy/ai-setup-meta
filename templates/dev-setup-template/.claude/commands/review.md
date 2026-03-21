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

5. **Aggiorna REGISTRY.md**
   Dopo la review, aggiorna `REGISTRY.md` con le entry nuove o modificate:

   a. Leggi `REGISTRY.md` corrente
   b. Analizza i file in `git diff main...HEAD` per identificare:
      - Nuove feature, servizi, componenti, utility, endpoint
      - Feature esistenti modificate in modo sostanziale (nuovi file, nuovi endpoint)
      - Decisioni architetturali rilevanti (nuova libreria, cambio pattern, nuovo layer)
   c. Per ogni entry nuova, aggiungi un blocco nella sezione appropriata:
      ```
      ### <scope>/<slug>
      - **Type**: feature | service | component | utility | api-endpoint | config
      - **Layer**: controller | service | repository | component | hook | utility | config
      - **Files**: `path/to/file1.ts`, `path/to/file2.ts`
      - **Depends on**: entry esistenti o "nessuno"
      - **Exposed API**: `METHOD /path` (se applicabile)
      - **Added**: data odierna (YYYY-MM-DD)
      - **Task**: ID del task ClickUp dal branch name (se presente)
      - **Summary**: una riga di descrizione
      ```
   d. Per entry gia' esistenti che sono state modificate, aggiorna solo i campi cambiati (Files, Summary, Depends on)
   e. Rimuovi i placeholder "_Nessuna ... registrata._" quando aggiungi la prima entry in una sezione
   f. Committa l'aggiornamento: `docs(registry): update REGISTRY.md`
