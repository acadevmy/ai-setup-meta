#!/usr/bin/env bash
# prepare-release.sh — prepara una release: bump versione, cut CHANGELOG, rebuild dist
#
# Usato da:
#   - .github/workflows/release-prepare.yml (CI, headless)
#   - scripts/release-plugin.sh (wrapper locale per emergenze)
#
# Uso: scripts/release/prepare-release.sh <patch|minor|major> <template-name> [--dry-run]
#
# Effetti collaterali (in modalita' normale):
#   - bump TEMPLATE_VERSION in templates/<template>/.env.example
#   - cut [Unreleased] -> [X.Y.Z] in templates/<template>/CHANGELOG.md
#     (preserva la prosa autorale; nessun re-derive da git log)
#   - bump version in .claude-plugin/marketplace.json + .cursor-plugin/marketplace.json
#   - rebuild dist/<template>/ via build-plugin.sh
#
# Output (stdout + $GITHUB_OUTPUT se presente):
#   new_version=X.Y.Z
#   tag=<template>-vX.Y.Z
#   branch=release/<template>-vX.Y.Z
#   current_version=A.B.C
#
# In --dry-run: stampa gli output ma non modifica nessun file.

set -euo pipefail

# ── Output utilities ─────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

# ── Argomenti ────────────────────────────────────────────────────────────────
RELEASE_TYPE="${1:-}"
TEMPLATE_NAME="${2:-}"
DRY_RUN=false

for arg in "$@"; do
  [[ "$arg" == "--dry-run" || "$arg" == "-n" ]] && DRY_RUN=true
done

[[ -z "$RELEASE_TYPE" || -z "$TEMPLATE_NAME" ]] && \
  fail "Uso: $0 <patch|minor|major> <template-name> [--dry-run]"
[[ "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]] || \
  fail "Tipo release non valido: '$RELEASE_TYPE'. Usa: patch | minor | major"

# ── Prerequisiti ─────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || fail "jq non trovato"
command -v python3 >/dev/null 2>&1 || fail "python3 non trovato"

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/templates/$TEMPLATE_NAME"
[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' non trovato in templates/"

# ── Versione corrente + nuova versione ───────────────────────────────────────
ENV_FILE="$TEMPLATE_DIR/.env.example"
[ -f "$ENV_FILE" ] || fail ".env.example non trovato in $TEMPLATE_DIR"

CURRENT_VERSION=$(sed -n 's/^TEMPLATE_VERSION=//p' "$ENV_FILE")
[ -z "$CURRENT_VERSION" ] && CURRENT_VERSION="1.0.0"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
case "$RELEASE_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW_VERSION="$MAJOR.$MINOR.$PATCH"
TAG="${TEMPLATE_NAME}-v${NEW_VERSION}"
BRANCH="release/${TAG}"
TODAY=$(date +%Y-%m-%d)

step "Release: $TEMPLATE_NAME $CURRENT_VERSION → $NEW_VERSION ($RELEASE_TYPE)"
ok "Tag: $TAG"
ok "Branch: $BRANCH"

# ── Dry-run gate ─────────────────────────────────────────────────────────────
emit_outputs() {
  echo "current_version=$CURRENT_VERSION"
  echo "new_version=$NEW_VERSION"
  echo "tag=$TAG"
  echo "branch=$BRANCH"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "current_version=$CURRENT_VERSION"
      echo "new_version=$NEW_VERSION"
      echo "tag=$TAG"
      echo "branch=$BRANCH"
    } >> "$GITHUB_OUTPUT"
  fi
}

if [ "$DRY_RUN" = true ]; then
  warn "DRY-RUN: nessuna modifica al filesystem"
  step "Output"
  emit_outputs
  exit 0
fi

# ── 1. Aggiorna .env.example ─────────────────────────────────────────────────
step "Aggiornamento .env.example"
sed -i.bak "s/^TEMPLATE_VERSION=.*/TEMPLATE_VERSION=$NEW_VERSION/" "$ENV_FILE"
rm -f "$ENV_FILE.bak"
ok "$(basename "$ENV_FILE") → TEMPLATE_VERSION=$NEW_VERSION"

# ── 2. Aggiorna marketplace.json (Claude + Cursor) ───────────────────────────
update_marketplace() {
  local file="$1"
  if [ -f "$file" ]; then
    local tmp; tmp=$(mktemp)
    jq --arg name "$TEMPLATE_NAME" --arg ver "$NEW_VERSION" \
      '(.plugins[] | select(.name == $name)).version = $ver' \
      "$file" > "$tmp" && mv "$tmp" "$file"
    ok "$(realpath --relative-to="$ROOT_DIR" "$file" 2>/dev/null || echo "$file") → version=$NEW_VERSION"
  fi
}

step "Aggiornamento marketplace.json"
update_marketplace "$ROOT_DIR/.claude-plugin/marketplace.json"
update_marketplace "$ROOT_DIR/.cursor-plugin/marketplace.json"

# ── 3. Cut CHANGELOG (preserva la prosa di [Unreleased]) ────────────────────
step "Cut CHANGELOG"
CHANGELOG_FILE="$TEMPLATE_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG_FILE" ]; then
  python3 - "$CHANGELOG_FILE" "$NEW_VERSION" "$TODAY" <<'PY'
import sys
import re
from pathlib import Path

path, version, today = sys.argv[1], sys.argv[2], sys.argv[3]
text = Path(path).read_text()

# Cattura la prima sezione [Unreleased] dal suo heading fino al successivo "## ["
# (o fino a fine file se non c'e' un successivo).
pattern_with_next = re.compile(
    r'^(## \[Unreleased\][^\n]*\n)(.*?)(?=^## \[)',
    re.MULTILINE | re.DOTALL,
)
pattern_to_eof = re.compile(
    r'^(## \[Unreleased\][^\n]*\n)(.*)\Z',
    re.MULTILINE | re.DOTALL,
)

m = pattern_with_next.search(text) or pattern_to_eof.search(text)
if not m:
    sys.exit(f"No [Unreleased] section found in {path}")

heading, body = m.group(1), m.group(2)
body_stripped = body.strip()

if not body_stripped:
    # Fallback: nessuna entry autorale -> nota generica
    new_dated = f"## [{version}] - {today}\n\n### Changed\n- Aggiornamento plugin\n\n"
else:
    new_dated = f"## [{version}] - {today}\n\n{body_stripped}\n\n"

# Sostituzione: lascia [Unreleased] vuoto, inserisce la nuova sezione datata sotto
replacement = f"{heading}\n{new_dated}"

if pattern_with_next.search(text):
    new_text = pattern_with_next.sub(replacement, text, count=1)
else:
    new_text = pattern_to_eof.sub(replacement, text, count=1)

Path(path).write_text(new_text)
PY
  ok "CHANGELOG.md → [Unreleased] cut a [$NEW_VERSION] - $TODAY"
else
  warn "CHANGELOG.md non trovato in $TEMPLATE_DIR — skippato"
fi

# ── 4. Rebuild dist ──────────────────────────────────────────────────────────
step "Build plugin"
bash "$ROOT_DIR/scripts/build-plugin.sh" "$TEMPLATE_NAME"
ok "Plugin built"

# ── 5. Output ────────────────────────────────────────────────────────────────
step "Output"
emit_outputs
