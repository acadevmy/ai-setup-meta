#!/usr/bin/env bash
# release-template.sh — Pubblica nuova versione del dev-setup-template
# Uso: bash scripts/release-template.sh [patch|minor|major]

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

RELEASE_TYPE="${1:-patch}"

if [[ ! "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]]; then
  fail "Tipo release non valido: '$RELEASE_TYPE'. Usa: patch | minor | major"
fi

# ── Verifica branch ───────────────────────────────────────────────────────────
step "Verifica branch e stato git"

CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
  fail "Devi essere su 'main' per fare release. Branch corrente: $CURRENT_BRANCH"
fi

if ! git diff --quiet HEAD; then
  fail "Ci sono modifiche non committate. Fai commit prima di procedere."
fi

ok "Branch: main, nessuna modifica pendente"

# ── Calcola nuova versione ────────────────────────────────────────────────────
step "Calcolo nuova versione"

source .env.local 2>/dev/null || true
CURRENT_VERSION="${TEMPLATE_VERSION:-1.0.0}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$RELEASE_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
TODAY=$(date +%Y-%m-%d)
TAG="template-v$NEW_VERSION"

ok "Versione: $CURRENT_VERSION → $NEW_VERSION"
ok "Tag: $TAG"

# ── Conferma ─────────────────────────────────────────────────────────────────
echo ""
echo "  Stai per rilasciare: $TAG ($RELEASE_TYPE)"
read -rp "  Confermi? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Operazione annullata."; exit 0; }

# ── Aggiorna file di versione ─────────────────────────────────────────────────
step "Aggiornamento file di versione"

# Aggiorna .env.example
sed -i.bak "s/^TEMPLATE_VERSION=.*/TEMPLATE_VERSION=$NEW_VERSION/" .env.example
rm -f .env.example.bak
ok ".env.example aggiornato"

# Aggiorna CHANGELOG del template
CHANGELOG="templates/dev-setup-template/CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
  # Inserisce nuova sezione dopo la prima riga
  TEMP=$(mktemp)
  head -1 "$CHANGELOG" > "$TEMP"
  echo "" >> "$TEMP"
  echo "## [$NEW_VERSION] - $TODAY" >> "$TEMP"
  echo "" >> "$TEMP"
  echo "- Aggiornamento automatico via release-template.sh" >> "$TEMP"
  echo "- Vedi PR per dettaglio modifiche" >> "$TEMP"
  tail -n +2 "$CHANGELOG" >> "$TEMP"
  mv "$TEMP" "$CHANGELOG"
  ok "CHANGELOG aggiornato"
fi

# ── Commit di release ─────────────────────────────────────────────────────────
step "Commit e tag"

git add .env.example "$CHANGELOG"
git commit -m "chore(release): bump dev-setup-template to v$NEW_VERSION"
ok "Commit creato"

git tag -a "$TAG" -m "Release dev-setup-template v$NEW_VERSION"
ok "Tag $TAG creato"

# ── Push ─────────────────────────────────────────────────────────────────────
step "Push su GitHub"

git push origin main
git push origin "$TAG"
ok "Push completato"

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║       Release $TAG completata ✓       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Prossimi passi manuali:"
echo "  1. Crea la GitHub Release su:"
echo "     https://github.com/\${GITHUB_ORG}/ai-setup-meta/releases/new?tag=$TAG"
echo "  2. Esegui /project:release in Claude Code per notificare il team su ClickUp"
echo ""
