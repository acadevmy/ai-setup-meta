#!/bin/bash
# PostToolUse hook: auto-format + auto-lint dopo Edit/Write
# Esegue Prettier e ESLint --fix sul file appena modificato da Claude

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Se non c'e' un file path, esci
[ -z "$FILE_PATH" ] && exit 0

# Se il file non esiste piu' (potrebbe essere stato cancellato), esci
[ ! -f "$FILE_PATH" ] && exit 0

# Auto-format con Prettier (se installato)
if command -v npx &>/dev/null && [ -f "node_modules/.bin/prettier" ]; then
  npx prettier --write "$FILE_PATH" 2>/dev/null
fi

# Auto-lint con ESLint --fix (solo per file JS/TS)
case "$FILE_PATH" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    if command -v npx &>/dev/null && [ -f "node_modules/.bin/eslint" ]; then
      npx eslint --fix "$FILE_PATH" 2>/dev/null
    fi
    ;;
esac

exit 0
