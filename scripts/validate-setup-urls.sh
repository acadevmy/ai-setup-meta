#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# validate-setup-urls.sh — Verifica che tutti i file referenziati
# in dist/setup.md esistano nel repository.
# Esegui: bash scripts/validate-setup-urls.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# File referenziati in setup.md che devono esistere
REQUIRED_FILES=(
  "templates/dev-setup-template/CONSTITUTION.md"
  "templates/dev-setup-template/AGENT.template.md"
  "templates/dev-setup-template/.claude/settings.json"
  "templates/dev-setup-template/.claude/commands/start-task.md"
  "templates/dev-setup-template/.claude/commands/tdd.md"
  "templates/dev-setup-template/.claude/commands/review.md"
  "templates/dev-setup-template/.claude/commands/sync-task.md"
  "profiles/web-frontend.md"
  "profiles/backend-node.md"
  "profiles/mobile.md"
  "dist/setup.md"
)

errors=0

echo "Verifico file referenziati da setup.md..."
echo ""

for file in "${REQUIRED_FILES[@]}"; do
  if [ -f "${REPO_ROOT}/${file}" ]; then
    printf '%b\n' "${GREEN}OK${NC}  ${file}"
  else
    printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
    errors=$((errors + 1))
  fi
done

echo ""

if [ "$errors" -gt 0 ]; then
  printf '%b\n' "${RED}${errors} file mancanti. Correggi prima di pubblicare.${NC}"
  exit 1
else
  printf '%b\n' "${GREEN}Tutti i file presenti. Setup.md e' valido.${NC}"
fi
