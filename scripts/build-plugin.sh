#!/usr/bin/env bash
# build-plugin.sh — Orchestratore: legge manifest.json e invoca il builder
#
# Uso: bash scripts/build-plugin.sh [template-name]
#
# Prerequisiti: jq
#
# Struttura builder:
#   scripts/builders/common.sh       — Funzioni condivise (ok, warn, fail, step)
#   scripts/builders/build-claude.sh — Build plugin Claude Code (unico target)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDERS_DIR="$SCRIPT_DIR/builders"

source "$BUILDERS_DIR/common.sh"

TEMPLATE_NAME="${1:-}"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Prerequisiti ──────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || fail "jq non trovato. Installa con: brew install jq"

# ── Seleziona template ────────────────────────────────────────────────────────
if [ -z "$TEMPLATE_NAME" ]; then
  TEMPLATES=()
  while IFS= read -r MF; do
    [ -n "$MF" ] || continue
    TEMPLATES+=("$(basename "$(dirname "$MF")")")
  done < <(find "$ROOT_DIR/templates" -maxdepth 2 -name "manifest.json" 2>/dev/null)
  if [ ${#TEMPLATES[@]} -eq 0 ]; then
    fail "Nessun template trovato in templates/"
  elif [ ${#TEMPLATES[@]} -eq 1 ]; then
    TEMPLATE_NAME="${TEMPLATES[0]}"
    ok "Template selezionato automaticamente: $TEMPLATE_NAME"
  else
    echo "Template disponibili:"
    for i in "${!TEMPLATES[@]}"; do
      echo "  $((i+1)). ${TEMPLATES[$i]}"
    done
    read -rp "Scegli un numero: " CHOICE
    TEMPLATE_NAME="${TEMPLATES[$((CHOICE-1))]}"
  fi
fi

# ── Variabili condivise (esportate per i builder) ─────────────────────────────
export TEMPLATE_DIR="$ROOT_DIR/templates/$TEMPLATE_NAME"
export MANIFEST="$TEMPLATE_DIR/manifest.json"
export DIST_DIR="$ROOT_DIR/dist/$TEMPLATE_NAME"

[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' non trovato in templates/"
[ -f "$MANIFEST" ] || fail "manifest.json non trovato in $TEMPLATE_DIR/"

step "Build plugin: $TEMPLATE_NAME"

NAME=$(jq -r '.name' "$MANIFEST")
DESCRIPTION=$(jq -r '.description' "$MANIFEST")
VERSION=$(sed -n 's/^TEMPLATE_VERSION=\([^ #]*\).*/\1/p' "$TEMPLATE_DIR/.env.example" 2>/dev/null)
[ -z "$VERSION" ] && VERSION=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null)
[ -z "$VERSION" ] && VERSION="1.0.0"
AUTHOR=$(jq -r '.author // "Acadevmy"' "$MANIFEST")
export NAME DESCRIPTION VERSION AUTHOR ROOT_DIR

ok "Manifest letto: $NAME v$VERSION"

# ── Pulisci dist ──────────────────────────────────────────────────────────────
step "Creazione struttura plugin in dist/$TEMPLATE_NAME/"
rm -rf "$DIST_DIR"

# ── Build Claude Code (unico target) ─────────────────────────────────────────
# DE-16489: i builder per gli altri runtime sono stati rimossi. Una SKILL.md
# conforme allo standard Agent Skills e' leggibile altrove senza conversione,
# quindi non c'e' niente da convertire.
bash "$BUILDERS_DIR/build-claude.sh"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Plugin $NAME v$VERSION built                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Output: dist/$TEMPLATE_NAME/"
echo ""

# Conta i componenti
SKILL_COUNT=$(find "$DIST_DIR/skills" -name "SKILL.md" | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$DIST_DIR/agents" -name "*.md" | wc -l | tr -d ' ')
HOOK_COUNT=$(find "$DIST_DIR/hooks/scripts" -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')

echo "  Skills: $SKILL_COUNT"
echo "  Agents: $AGENT_COUNT"
echo "  Hooks:  $HOOK_COUNT"
echo ""
echo "  Validazione: claude plugin validate dist/$TEMPLATE_NAME/"
echo "  Test locale:  claude --plugin-dir dist/$TEMPLATE_NAME/"
echo ""
