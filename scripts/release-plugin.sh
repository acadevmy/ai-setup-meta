#!/usr/bin/env bash
# release-plugin.sh — Build plugin, bump version, aggiorna CHANGELOG, tag e push
#
# Uso: bash scripts/release-plugin.sh [patch|minor|major] [template-name] [--yes]
#
# Prerequisiti:
#   - gh CLI autenticata (gh auth login)
#   - jq installato
#   - Essere su branch main con working tree pulito

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

AUTO_CONFIRM=false
RELEASE_TYPE="${1:-patch}"
TEMPLATE_NAME="${2:-}"

for arg in "$@"; do
  [[ "$arg" == "--yes" || "$arg" == "-y" ]] && AUTO_CONFIRM=true
done

if [[ ! "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]]; then
  fail "Tipo release non valido: '$RELEASE_TYPE'. Usa: patch | minor | major"
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Prerequisiti ──────────────────────────────────────────────────────────────
step "Verifica prerequisiti"

command -v gh >/dev/null 2>&1 || fail "gh CLI non trovata. Installa con: brew install gh"
command -v jq >/dev/null 2>&1 || fail "jq non trovato. Installa con: brew install jq"
gh auth status >/dev/null 2>&1 || fail "gh CLI non autenticata. Esegui: gh auth login"
ok "Prerequisiti verificati"

# ── Verifica branch ──────────────────────────────────────────────────────────
step "Verifica branch e stato git"

CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
  fail "Devi essere su 'main' per fare release. Branch corrente: $CURRENT_BRANCH"
fi

if ! git diff --quiet HEAD; then
  fail "Ci sono modifiche non committate. Fai commit prima di procedere."
fi

ok "Branch: main, nessuna modifica pendente"

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

TEMPLATE_DIR="$ROOT_DIR/templates/$TEMPLATE_NAME"
[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' non trovato"

# ── Calcola nuova versione ───────────────────────────────────────────────────
step "Calcolo nuova versione"

CURRENT_VERSION=$(sed -n 's/^TEMPLATE_VERSION=//p' "$TEMPLATE_DIR/.env.example" 2>/dev/null)
[ -z "$CURRENT_VERSION" ] && CURRENT_VERSION="1.0.0"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$RELEASE_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
TODAY=$(date +%Y-%m-%d)
TAG="${TEMPLATE_NAME}-v${NEW_VERSION}"

ok "Versione: $CURRENT_VERSION → $NEW_VERSION"
ok "Tag: $TAG"

# ── Conferma ─────────────────────────────────────────────────────────────────
echo ""
echo "  Stai per rilasciare: $TAG ($RELEASE_TYPE)"
echo "  Template: $TEMPLATE_NAME"
if [ "$AUTO_CONFIRM" = false ]; then
  read -rp "  Confermi? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Operazione annullata."; exit 0; }
fi

# ── Aggiorna versione ────────────────────────────────────────────────────────
step "Aggiornamento versione"

sed -i.bak "s/^TEMPLATE_VERSION=.*/TEMPLATE_VERSION=$NEW_VERSION/" "$TEMPLATE_DIR/.env.example"
rm -f "$TEMPLATE_DIR/.env.example.bak"
ok ".env.example aggiornato"

MARKETPLACE_FILE="$ROOT_DIR/.claude-plugin/marketplace.json"
if [ -f "$MARKETPLACE_FILE" ]; then
  TMPFILE=$(mktemp)
  jq --arg name "$TEMPLATE_NAME" --arg ver "$NEW_VERSION" \
    '(.plugins[] | select(.name == $name)).version = $ver' \
    "$MARKETPLACE_FILE" > "$TMPFILE" && mv "$TMPFILE" "$MARKETPLACE_FILE"
  ok "marketplace.json aggiornato a v$NEW_VERSION"
fi

# ── Build plugin ─────────────────────────────────────────────────────────────
step "Build plugin"

bash "$ROOT_DIR/scripts/build-plugin.sh" "$TEMPLATE_NAME"
ok "Plugin built"

# ── Aggiorna CHANGELOG ───────────────────────────────────────────────────────
step "Aggiornamento CHANGELOG"

CHANGELOG_FILE="$TEMPLATE_DIR/CHANGELOG.md"
PREV_TAG="${TEMPLATE_NAME}-v${CURRENT_VERSION}"

CHANGELOG_ADDED=""
CHANGELOG_CHANGED=""
CHANGELOG_FIXED=""

while IFS= read -r MSG; do
  [ -z "$MSG" ] && continue
  case "$MSG" in
    feat:*|feat\(*) CHANGELOG_ADDED="${CHANGELOG_ADDED}\n- ${MSG#*: }" ;;
    fix:*|fix\(*)   CHANGELOG_FIXED="${CHANGELOG_FIXED}\n- ${MSG#*: }" ;;
    *)               CHANGELOG_CHANGED="${CHANGELOG_CHANGED}\n- ${MSG#*: }" ;;
  esac
done < <(git log --format='%s' "${PREV_TAG}..HEAD" -- "$TEMPLATE_DIR/" shared/ 2>/dev/null || \
         git log --format='%s' -20 -- "$TEMPLATE_DIR/" shared/)

NEW_ENTRY="## [$NEW_VERSION] - $TODAY"
[ -n "$CHANGELOG_ADDED" ]  && NEW_ENTRY="${NEW_ENTRY}\n\n### Added$(echo -e "$CHANGELOG_ADDED")"
[ -n "$CHANGELOG_CHANGED" ] && NEW_ENTRY="${NEW_ENTRY}\n\n### Changed$(echo -e "$CHANGELOG_CHANGED")"
[ -n "$CHANGELOG_FIXED" ]   && NEW_ENTRY="${NEW_ENTRY}\n\n### Fixed$(echo -e "$CHANGELOG_FIXED")"

if [ -z "$CHANGELOG_ADDED" ] && [ -z "$CHANGELOG_CHANGED" ] && [ -z "$CHANGELOG_FIXED" ]; then
  NEW_ENTRY="${NEW_ENTRY}\n\n### Changed\n- Aggiornamento plugin"
fi

if [ -f "$CHANGELOG_FILE" ]; then
  HEAD_LINES=$(grep -n '^## \[' "$CHANGELOG_FILE" | head -1 | cut -d: -f1)
  if [ -n "$HEAD_LINES" ]; then
    TMPFILE=$(mktemp)
    head -n $((HEAD_LINES - 1)) "$CHANGELOG_FILE" > "$TMPFILE"
    echo -e "$NEW_ENTRY\n" >> "$TMPFILE"
    tail -n +"$HEAD_LINES" "$CHANGELOG_FILE" >> "$TMPFILE"
    mv "$TMPFILE" "$CHANGELOG_FILE"
  else
    echo -e "\n$NEW_ENTRY" >> "$CHANGELOG_FILE"
  fi
else
  echo -e "# Changelog\n\n$NEW_ENTRY" > "$CHANGELOG_FILE"
fi

ok "CHANGELOG.md aggiornato"

# ── Commit ───────────────────────────────────────────────────────────────────
step "Commit e tag"

git add "$TEMPLATE_DIR/.env.example" "$CHANGELOG_FILE" "dist/$TEMPLATE_NAME/" ".claude-plugin/marketplace.json"
if ! git diff --cached --quiet; then
  git commit -m "chore(release): bump $TEMPLATE_NAME to v$NEW_VERSION"
  ok "Commit creato"
fi

git tag -a "$TAG" -m "Release $TEMPLATE_NAME v$NEW_VERSION"
ok "Tag $TAG creato"

# ── Push ─────────────────────────────────────────────────────────────────────
step "Push"

git push origin main
git push origin "$TAG"
ok "Push completato"

# ── GitHub Release ───────────────────────────────────────────────────────────
step "Creazione GitHub Release"

RELEASE_NOTES="## $TEMPLATE_NAME v$NEW_VERSION ($TODAY)

Tipo: $RELEASE_TYPE

### Setup

\`\`\`bash
# Aggiungi il marketplace (una tantum)
/plugin marketplace add acadevmy/ai-setup-meta

# Installa il plugin
/plugin install dev-setup@acadevmy

# Avvia il setup nel tuo progetto
/dev-setup:setup
\`\`\`

---
Generata da: ai-setup-meta/scripts/release-plugin.sh"

gh release create "$TAG" \
  --title "$TEMPLATE_NAME v$NEW_VERSION" \
  --notes "$RELEASE_NOTES"

ok "GitHub Release creata"

# ── Riepilogo ────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Release $TEMPLATE_NAME v$NEW_VERSION completata              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Tag: $TAG"
echo "  Plugin: dist/$TEMPLATE_NAME/"
echo "  Marketplace: .claude-plugin/marketplace.json"
echo ""
