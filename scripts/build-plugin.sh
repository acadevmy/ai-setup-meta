#!/usr/bin/env bash
# build-plugin.sh — orchestrator: reads manifest.json and calls the builder
#
# Usage: bash scripts/build-plugin.sh [template-name]
#
# Prerequisites: jq
#
# Builder layout:
#   scripts/builders/common.sh       — shared helpers (ok, warn, fail, step)
#   scripts/builders/build-claude.sh — Claude Code plugin build (the only target)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDERS_DIR="$SCRIPT_DIR/builders"

source "$BUILDERS_DIR/common.sh"

TEMPLATE_NAME="${1:-}"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Prerequisites ─────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || fail "jq not found. Install it with: brew install jq"

# ── Select the template ───────────────────────────────────────────────────────
if [ -z "$TEMPLATE_NAME" ]; then
  TEMPLATES=()
  while IFS= read -r MF; do
    [ -n "$MF" ] || continue
    TEMPLATES+=("$(basename "$(dirname "$MF")")")
  done < <(find "$ROOT_DIR/templates" -maxdepth 2 -name "manifest.json" 2>/dev/null)
  if [ ${#TEMPLATES[@]} -eq 0 ]; then
    fail "No template found under templates/"
  elif [ ${#TEMPLATES[@]} -eq 1 ]; then
    TEMPLATE_NAME="${TEMPLATES[0]}"
    ok "Template selected automatically: $TEMPLATE_NAME"
  else
    echo "Available templates:"
    for i in "${!TEMPLATES[@]}"; do
      echo "  $((i+1)). ${TEMPLATES[$i]}"
    done
    read -rp "Pick a number: " CHOICE
    TEMPLATE_NAME="${TEMPLATES[$((CHOICE-1))]}"
  fi
fi

# ── Shared variables (exported for the builders) ──────────────────────────────
export TEMPLATE_DIR="$ROOT_DIR/templates/$TEMPLATE_NAME"
export MANIFEST="$TEMPLATE_DIR/manifest.json"
export DIST_DIR="$ROOT_DIR/dist/$TEMPLATE_NAME"

[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' not found under templates/"
[ -f "$MANIFEST" ] || fail "manifest.json not found in $TEMPLATE_DIR/"

step "Build plugin: $TEMPLATE_NAME"

NAME=$(jq -r '.name' "$MANIFEST")
DESCRIPTION=$(jq -r '.description' "$MANIFEST")
VERSION=$(sed -n 's/^TEMPLATE_VERSION=\([^ #]*\).*/\1/p' "$TEMPLATE_DIR/.env.example" 2>/dev/null)
[ -z "$VERSION" ] && VERSION=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null)
[ -z "$VERSION" ] && VERSION="1.0.0"
AUTHOR=$(jq -r '.author // "Acadevmy"' "$MANIFEST")
export NAME DESCRIPTION VERSION AUTHOR ROOT_DIR

ok "Manifest read: $NAME v$VERSION"

# ── Clean dist ────────────────────────────────────────────────────────────────
step "Creating the plugin layout under dist/$TEMPLATE_NAME/"
rm -rf "$DIST_DIR"

# ── Claude Code build (the only target) ──────────────────────────────────────
# DE-16489: the builders for the other runtimes were removed. A SKILL.md that
# conforms to the Agent Skills standard is readable elsewhere without conversion,
# so there is nothing left to convert.
bash "$BUILDERS_DIR/build-claude.sh"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Plugin $NAME v$VERSION built                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Output: dist/$TEMPLATE_NAME/"
echo ""

# Count the components
SKILL_COUNT=$(find "$DIST_DIR/skills" -name "SKILL.md" | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$DIST_DIR/agents" -name "*.md" | wc -l | tr -d ' ')
HOOK_COUNT=$(find "$DIST_DIR/hooks/scripts" -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')

echo "  Skills: $SKILL_COUNT"
echo "  Agents: $AGENT_COUNT"
echo "  Hooks:  $HOOK_COUNT"
echo ""
echo "  Validate:   claude plugin validate dist/$TEMPLATE_NAME/"
echo "  Try it:     claude --plugin-dir dist/$TEMPLATE_NAME/"
echo ""
