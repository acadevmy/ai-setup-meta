---
paths:
  - "dist/**"
---

# dist/ e' una cartella generata — non modificarla mai direttamente

Il contenuto di `dist/` viene generato interamente da `scripts/build-plugin.sh`.

- **Non creare, modificare o eliminare file in `dist/`** manualmente
- Applica le modifiche nei sorgenti: `templates/`, `shared/`, `scripts/`
- Rigenera con: `bash scripts/build-plugin.sh`
