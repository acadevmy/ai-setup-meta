#!/usr/bin/env bash
# release-plugin.sh — wrapper per release locali (emergenze)
#
# Path standard: usa la GitHub Action "Release - Prepare" da
#   https://github.com/acadevmy/ai-setup-meta/actions/workflows/release-prepare.yml
# (workflow_dispatch). Apre una release PR rivedibile; il merge crea tag + Release.
#
# Questo wrapper esiste solo per le emergenze in cui le GitHub Actions non sono
# disponibili. Esegue prepare-release + push diretto su main + publish-release.
# Ogni esecuzione bypassa la review — usalo con consapevolezza.
#
# Uso: bash scripts/release-plugin.sh [patch|minor|major] [template-name] [--yes]
#
# Prerequisiti:
#   - gh CLI autenticata (gh auth login)
#   - jq, python3 installati
#   - Branch corrente: main, working tree pulito

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

AUTO_CONFIRM=false
RELEASE_TYPE="${1:-patch}"
TEMPLATE_NAME="${2:-}"

for arg in "$@"; do
  [[ "$arg" == "--yes" || "$arg" == "-y" ]] && AUTO_CONFIRM=true
done

[[ "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]] || \
  fail "Tipo release non valido: '$RELEASE_TYPE'. Usa: patch | minor | major"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Verifica branch + clean tree ─────────────────────────────────────────────
step "Verifica branch e stato git"
CURRENT_BRANCH=$(git -C "$ROOT_DIR" branch --show-current)
[ "$CURRENT_BRANCH" = "main" ] || fail "Devi essere su 'main'. Branch corrente: $CURRENT_BRANCH"
git -C "$ROOT_DIR" diff --quiet HEAD || fail "Ci sono modifiche non committate. Fai commit prima di procedere."
ok "Branch: main, working tree pulito"

# ── Auto-detect template se non specificato ──────────────────────────────────
if [ -z "$TEMPLATE_NAME" ]; then
  TEMPLATES=($(find "$ROOT_DIR/templates" -name "manifest.json" -maxdepth 2 2>/dev/null | while read f; do basename "$(dirname "$f")"; done))
  if [ ${#TEMPLATES[@]} -eq 1 ]; then
    TEMPLATE_NAME="${TEMPLATES[0]}"
    ok "Template selezionato automaticamente: $TEMPLATE_NAME"
  else
    fail "Specifica il template: $0 $RELEASE_TYPE <template-name>"
  fi
fi

# ── Avviso bypass review ─────────────────────────────────────────────────────
warn "Questo wrapper bypassa la review GitHub PR. Path standard: workflow_dispatch su release-prepare.yml."
if [ "$AUTO_CONFIRM" = false ]; then
  read -rp "Continuare con la release locale di '$TEMPLATE_NAME' ($RELEASE_TYPE)? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Operazione annullata."; exit 0; }
fi

# ── 1. Prepare ───────────────────────────────────────────────────────────────
step "Prepare release"
PREPARE_OUTPUT=$(bash "$ROOT_DIR/scripts/release/prepare-release.sh" "$RELEASE_TYPE" "$TEMPLATE_NAME")
echo "$PREPARE_OUTPUT"

NEW_VERSION=$(echo "$PREPARE_OUTPUT" | grep -E '^new_version=' | tail -1 | cut -d= -f2)
TAG=$(echo "$PREPARE_OUTPUT" | grep -E '^tag=' | tail -1 | cut -d= -f2)
[ -z "$NEW_VERSION" ] && fail "Impossibile estrarre la nuova versione dall'output di prepare-release"

# ── 2. Commit + push diretto su main ─────────────────────────────────────────
step "Commit e push su main"
git -C "$ROOT_DIR" add -A
if git -C "$ROOT_DIR" diff --cached --quiet; then
  warn "Nessuna modifica da committare (idempotente)"
else
  git -C "$ROOT_DIR" commit -m "chore(release): bump $TEMPLATE_NAME to v$NEW_VERSION"
  ok "Commit creato"
fi
git -C "$ROOT_DIR" push origin main
ok "Push su main completato"

# ── 3. Publish (tag + GitHub Release) ────────────────────────────────────────
step "Publish release"
bash "$ROOT_DIR/scripts/release/publish-release.sh" "$TEMPLATE_NAME" "$NEW_VERSION"

step "Done"
echo "Tag:    $TAG"
echo "Release: https://github.com/acadevmy/ai-setup-meta/releases/tag/$TAG"
