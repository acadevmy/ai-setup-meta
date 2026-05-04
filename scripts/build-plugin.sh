#!/usr/bin/env bash
# build-plugin.sh — Orchestratore: legge manifest.json e invoca i builder specifici
#
# Uso: bash scripts/build-plugin.sh [template-name]
#
# Prerequisiti: jq
#
# Struttura builder:
#   scripts/builders/common.sh       — Funzioni condivise (ok, warn, fail, step)
#   scripts/builders/build-claude.sh — Build plugin Claude Code (sempre eseguito)
#   scripts/builders/build-gemini.sh — Build variante Gemini CLI (se gemini_support)
#   scripts/builders/build-codex.sh  — Build variante Codex CLI (se codex_support)

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
  TEMPLATES=($(find "$ROOT_DIR/templates" -name "manifest.json" -maxdepth 2 2>/dev/null | while read f; do basename "$(dirname "$f")"; done))
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

export NAME=$(jq -r '.name' "$MANIFEST")
export DESCRIPTION=$(jq -r '.description' "$MANIFEST")
export VERSION=$(sed -n 's/^TEMPLATE_VERSION=\([^ #]*\).*/\1/p' "$TEMPLATE_DIR/.env.example" 2>/dev/null)
[ -z "$VERSION" ] && VERSION=$(jq -r '.version // empty' "$MANIFEST" 2>/dev/null)
[ -z "$VERSION" ] && VERSION="1.0.0"
export AUTHOR=$(jq -r '.author // "Acadevmy"' "$MANIFEST")
export ROOT_DIR

ok "Manifest letto: $NAME v$VERSION"

# ── Pulisci dist ──────────────────────────────────────────────────────────────
step "Creazione struttura plugin in dist/$TEMPLATE_NAME/"
rm -rf "$DIST_DIR"

# ── 1. Build Claude Code (sempre) ────────────────────────────────────────────
bash "$BUILDERS_DIR/build-claude.sh"

# ── 2. Build Gemini CLI (se abilitato) ────────────────────────────────────────
GEMINI_SUPPORT=$(jq -r '.gemini_support // false' "$MANIFEST")
if [ "$GEMINI_SUPPORT" = "true" ]; then
  bash "$BUILDERS_DIR/build-gemini.sh"
fi

# ── 3. Build Codex CLI (se abilitato) ────────────────────────────────────────
CODEX_SUPPORT=$(jq -r '.codex_support // false' "$MANIFEST")
if [ "$CODEX_SUPPORT" = "true" ]; then
  bash "$BUILDERS_DIR/build-codex.sh"
fi

# ── 4. Build Cursor (se abilitato) ───────────────────────────────────────────
CURSOR_SUPPORT=$(jq -r '.cursor_support // false' "$MANIFEST")
if [ "$CURSOR_SUPPORT" = "true" ]; then
  bash "$BUILDERS_DIR/build-cursor.sh"
fi

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

if [ "$GEMINI_SUPPORT" = "true" ]; then
  echo "  Gemini: GEMINI.md generato"
fi

if [ "$CODEX_SUPPORT" = "true" ]; then
  echo "  Codex:  AGENTS.md + plugin generato"
fi

if [ "$CURSOR_SUPPORT" = "true" ]; then
  CMD_COUNT=$(find "$DIST_DIR/commands" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  echo "  Cursor: plugin.json + mcp.json + $CMD_COUNT commands generati"
  echo ""
  echo "  Test locale Cursor:"
  echo "    ln -s \$(pwd)/dist/$TEMPLATE_NAME ~/.cursor/plugins/local/$TEMPLATE_NAME"
  echo "    # poi: Developer → Reload Window in Cursor"
fi


echo ""
echo "  Validazione: claude plugin validate dist/$TEMPLATE_NAME/"
echo "  Test locale:  claude --plugin-dir dist/$TEMPLATE_NAME/"
echo ""
