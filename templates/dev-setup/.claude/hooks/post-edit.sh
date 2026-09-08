#!/bin/bash
# PostToolUse hook: auto-format + auto-lint after Edit/Write
# Runs Prettier and ESLint --fix on the file Claude just changed

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# No file path, nothing to do
[ -z "$FILE_PATH" ] && exit 0

# The file is gone (it may have been deleted), nothing to do
[ ! -f "$FILE_PATH" ] && exit 0

# Auto-format with Prettier (when installed)
if command -v npx &>/dev/null && [ -f "node_modules/.bin/prettier" ]; then
  npx prettier --write "$FILE_PATH" 2>/dev/null
fi

# Auto-lint with ESLint --fix (JS/TS files only)
case "$FILE_PATH" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs)
    if command -v npx &>/dev/null && [ -f "node_modules/.bin/eslint" ]; then
      npx eslint --fix "$FILE_PATH" 2>/dev/null
    fi
    ;;
esac

exit 0
