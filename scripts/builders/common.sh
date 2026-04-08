#!/usr/bin/env bash
# common.sh — Funzioni condivise per i builder di plugin
#
# Questo file viene importato (source) dai builder specifici.
# Non eseguire direttamente.

# ── Colori e output ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

# ── Copia governance ─────────────────────────────────────────────────────────
# Cerca PM-CONSTITUTION.md o CONSTITUTION.md nei templates bundled e lo copia
# Uso: copy_governance <dest_dir> <platform_label>
copy_governance() {
  local DEST_DIR="$1"
  local LABEL="$2"
  for GOV_FILE in "PM-CONSTITUTION.md" "CONSTITUTION.md"; do
    local GOV_SRC="$DIST_DIR/skills/setup/templates/$GOV_FILE"
    if [ -f "$GOV_SRC" ]; then
      cp "$GOV_SRC" "$DEST_DIR/$GOV_FILE"
      ok "Governance: $GOV_FILE copiata per $LABEL"
      return 0
    fi
  done
  warn "Nessun file di governance trovato per $LABEL"
  return 1
}

# ── Copia skills ─────────────────────────────────────────────────────────────
# Copia tutte le skill da dist/ (tranne quelle escluse) in una directory target
# Uso: copy_skills <dest_dir> <platform_label> <skip_list_space_separated>
copy_skills() {
  local DEST_DIR="$1"
  local LABEL="$2"
  local SKIP_LIST="$3"
  local COUNT=0

  for SKILL_DIR in "$DIST_DIR/skills"/*/; do
    local SKILL_FILE="$SKILL_DIR/SKILL.md"
    [ -f "$SKILL_FILE" ] || continue

    local SKILL_NAME
    SKILL_NAME=$(basename "$SKILL_DIR")

    # Controlla se la skill e' nella lista di skip
    local SKIP=false
    for S in $SKIP_LIST; do
      [ "$SKILL_NAME" = "$S" ] && SKIP=true && break
    done
    [ "$SKIP" = true ] && continue

    local SKILL_DST="$DEST_DIR/$SKILL_NAME"
    mkdir -p "$SKILL_DST"
    cp "$SKILL_FILE" "$SKILL_DST/SKILL.md"
    COUNT=$((COUNT + 1))
  done

  ok "Skills copiate per $LABEL: $COUNT"
}

# ── Copia agents ─────────────────────────────────────────────────────────────
# Copia tutti gli agent .md da dist/agents/ in una directory target
# Uso: copy_agents <dest_dir> <platform_label>
copy_agents() {
  local DEST_DIR="$1"
  local LABEL="$2"

  for AGENT_FILE in "$DIST_DIR/agents"/*.md; do
    [ -f "$AGENT_FILE" ] || continue
    cp "$AGENT_FILE" "$DEST_DIR/"
    ok "Agent copiato per $LABEL: $(basename "$AGENT_FILE")"
  done
}
