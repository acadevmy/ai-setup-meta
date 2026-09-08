#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# validate-setup-urls.sh — checks that every file the setup skills reference
# actually exists in the repository.
# It reads the templates' manifest.json files to build the list.
# Run with: bash scripts/validate-setup-urls.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

errors=0

echo "Checking the files the setup references..."
echo ""

# dist/ is produced by the build (/project:build-plugin) — not validated here.
# Run the build and its own validation separately before a release.

# For every template that has a manifest.json
for manifest in "${REPO_ROOT}"/templates/*/manifest.json; do
  [ -f "$manifest" ] || continue
  TEMPLATE_DIR=$(dirname "$manifest")
  TEMPLATE_NAME=$(basename "$TEMPLATE_DIR")

  echo ""
  echo "--- Template: $TEMPLATE_NAME ---"

  # Domain agent
  AGENT=$(python3 -c "import json; print(json.load(open('$manifest'))['agent'])" 2>/dev/null || echo "")
  if [ -n "$AGENT" ]; then
    file="templates/$TEMPLATE_NAME/$AGENT"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi

    # the dist/ copy of the agent is validated by the build, not here
  fi

  # Shared agents
  for agent in $(python3 -c "import json; [print(a) for a in json.load(open('$manifest')).get('shared_agents',[])]" 2>/dev/null); do
    file="shared/agents/$agent"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Shared skills
  for skill in $(python3 -c "import json; [print(s) for s in json.load(open('$manifest')).get('shared_skills',[])]" 2>/dev/null); do
    file="shared/skills/$skill/SKILL.md"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Template skills
  for skill in $(python3 -c "import json; [print(s) for s in json.load(open('$manifest')).get('template_skills',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/.claude/skills/$skill/SKILL.md"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Template agents
  for agent in $(python3 -c "import json; [print(a) for a in json.load(open('$manifest')).get('template_agents',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/.claude/agents/$agent"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Required files
  for req in $(python3 -c "import json; [print(r) for r in json.load(open('$manifest')).get('required_files',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/$req"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Profiles
  for profile in $(python3 -c "import json; [print(p) for p in json.load(open('$manifest')).get('profiles',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/profiles/$profile"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Path-scoped rule templates (rendered into the project's .claude/rules/)
  for rule in $(python3 -c "import json; [print(r) for r in json.load(open('$manifest')).get('rules',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/rules/$rule"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Plugin scripts (the deterministic helpers shipped at dist/<name>/scripts/)
  for script in $(python3 -c "import json; [print(s) for s in json.load(open('$manifest')).get('plugin_scripts',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/.claude/scripts/$script"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Hooks
  for hook in $(python3 -c "import json; [print(h) for h in json.load(open('$manifest')).get('hooks',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/.claude/hooks/$hook"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done

  # Boilerplate files (greenfield-only verbatim downloads)
  for bp in $(python3 -c "import json; [print(b) for b in json.load(open('$manifest')).get('boilerplate_files',[])]" 2>/dev/null); do
    file="templates/$TEMPLATE_NAME/boilerplate/$bp"
    if [ -f "${REPO_ROOT}/${file}" ]; then
      printf '%b\n' "${GREEN}OK${NC}  ${file}"
    else
      printf '%b\n' "${RED}MISSING${NC}  ${file}"
      errors=$((errors + 1))
    fi
  done
done

echo ""

if [ "$errors" -gt 0 ]; then
  printf '%b\n' "${RED}${errors} missing file(s). Fix them before publishing.${NC}"
  exit 1
else
  printf '%b\n' "${GREEN}Every referenced file is present. Setup valid.${NC}"
fi
