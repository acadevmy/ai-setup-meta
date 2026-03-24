#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# validate-setup-urls.sh — Verifica che tutti i file referenziati
# dagli agent di setup esistano nel repository.
# Legge i manifest.json dei template per costruire la lista.
# Esegui: bash scripts/validate-setup-urls.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

errors=0

echo "Verifico file referenziati dal setup..."
echo ""

# File sempre richiesti
COMMON_FILES=(
  "dist/setup.md"
)

for file in "${COMMON_FILES[@]}"; do
  if [ -f "${REPO_ROOT}/${file}" ]; then
    printf '%b\n' "${GREEN}OK${NC}  ${file}"
  else
    printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
    errors=$((errors + 1))
  fi
done

# Per ogni template con manifest.json
for manifest in "${REPO_ROOT}"/templates/*/manifest.json; do
  [ -f "$manifest" ] || continue
  TEMPLATE_DIR=$(dirname "$manifest")
  TEMPLATE_NAME=$(basename "$TEMPLATE_DIR")

  echo ""
  echo "--- Template: $TEMPLATE_NAME ---"

  # Agent di dominio
  AGENT=$(python3 -c "import json; print(json.load(open('$manifest'))['agent'])" 2>/dev/null || echo "")
  if [ -n "$AGENT" ]; then
    file="templates/$TEMPLATE_NAME/$AGENT"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi

    # Copia in dist
    file="dist/agents/$AGENT"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  fi

  # Shared agents
  for agent in $(python3 -c "import json; [print(a) for a in json.load(open('$manifest')).get('shared_agents',[])]" 2>/dev/null); do
    file="shared/agents/$agent"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Shared skills
  for skill in $(python3 -c "import json; [print(s) for s in json.load(open('$manifest')).get('shared_skills',[])]" 2>/dev/null); do
    file="shared/skills/$skill/SKILL.md"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Template skills
  for skill in $(python3 -c "import json; [print(s) for s in json.load(open('$manifest')).get('template_skills',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/.claude/skills/$skill/SKILL.md"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Template agents
  for agent in $(python3 -c "import json; [print(a) for a in json.load(open('$manifest')).get('template_agents',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/.claude/agents/$agent"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Required files
  for req in $(python3 -c "import json; [print(r) for r in json.load(open('$manifest')).get('required_files',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/$req"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Profiles
  for profile in $(python3 -c "import json; [print(p) for p in json.load(open('$manifest')).get('profiles',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/profiles/$profile"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MANCANTE${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done
done

echo ""

if [ "$errors" -gt 0 ]; then
  printf '%b\n' "${RED}${errors} file mancanti. Correggi prima di pubblicare.${NC}"
  exit 1
else
  printf '%b\n' "${GREEN}Tutti i file presenti. Setup valido.${NC}"
fi
