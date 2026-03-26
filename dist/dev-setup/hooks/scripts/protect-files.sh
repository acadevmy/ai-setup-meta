#!/bin/bash
# PreToolUse hook: blocca modifiche a file protetti
# Impedisce a Claude di modificare file che non dovrebbero essere toccati manualmente

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Se non c'e' un file path, lascia passare
[ -z "$FILE_PATH" ] && exit 0

# File e pattern protetti
PROTECTED_PATTERNS=(
  ".env"
  ".env.local"
  "package-lock.json"
  "pnpm-lock.yaml"
  "yarn.lock"
  ".git/"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  case "$FILE_PATH" in
    *"$pattern"*)
      echo "Blocked: modifica a '$FILE_PATH' non consentita (match: '$pattern'). Questi file vanno gestiti manualmente o dai tool dedicati." >&2
      exit 2
      ;;
  esac
done

exit 0
