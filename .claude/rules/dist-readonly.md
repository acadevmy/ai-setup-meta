---
paths:
  - "dist/**"
---

# dist/ is a generated directory — never edit it directly

Everything under `dist/` is produced by `scripts/build-plugin.sh`.

- **Do not create, edit or delete files in `dist/`** by hand
- Make the change in the sources instead: `templates/`, `shared/`, `scripts/`
- Regenerate with: `bash scripts/build-plugin.sh`
