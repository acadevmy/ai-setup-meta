#!/usr/bin/env bash
# publish-release.sh — pubblica una release: crea tag annotato, push, GitHub Release
#
# Usato da:
#   - .github/workflows/release-publish.yml (CI, su merge di release PR)
#   - scripts/release-plugin.sh (wrapper locale per emergenze)
#
# Uso: scripts/release/publish-release.sh <template-name> <version>
#
# Esempio: scripts/release/publish-release.sh dev-setup 1.6.1
#
# Effetti:
#   - Crea tag annotato "<template>-v<version>" sul HEAD corrente
#   - Push del tag a origin
#   - Crea GitHub Release con il body letto dal CHANGELOG
#     (sezione "## [<version>] - ..." del template)

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
TEMPLATE_NAME="${1:-}"
VERSION="${2:-}"

[[ -z "$TEMPLATE_NAME" || -z "$VERSION" ]] && \
  fail "Uso: $0 <template-name> <version>"

# ── Prerequisiti ─────────────────────────────────────────────────────────────
command -v gh >/dev/null 2>&1 || fail "gh CLI non trovata"
command -v python3 >/dev/null 2>&1 || fail "python3 non trovato"
gh auth status >/dev/null 2>&1 || fail "gh CLI non autenticata"

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/templates/$TEMPLATE_NAME"
[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' non trovato in templates/"

CHANGELOG_FILE="$TEMPLATE_DIR/CHANGELOG.md"
[ -f "$CHANGELOG_FILE" ] || fail "CHANGELOG.md non trovato in $TEMPLATE_DIR"

TAG="${TEMPLATE_NAME}-v${VERSION}"

step "Pubblicazione: $TAG"

# ── 1. Verifica che la versione sia gia' committata in .env.example ──────────
ENV_FILE="$TEMPLATE_DIR/.env.example"
COMMITTED_VERSION=$(sed -n 's/^TEMPLATE_VERSION=//p' "$ENV_FILE" || echo "")
if [ "$COMMITTED_VERSION" != "$VERSION" ]; then
  fail "Mismatch versione: .env.example contiene '$COMMITTED_VERSION', atteso '$VERSION'. Il commit di prepare-release deve essere gia' su HEAD."
fi
ok ".env.example verificato a v$VERSION"

# ── 2. Verifica che il tag non esista gia' ───────────────────────────────────
if git -C "$ROOT_DIR" rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "Tag '$TAG' esiste gia' nel repo locale"
fi
if git -C "$ROOT_DIR" ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null | grep -q .; then
  fail "Tag '$TAG' esiste gia' su origin"
fi

# ── 3. Estrai release notes dalla sezione CHANGELOG ──────────────────────────
step "Estrazione release notes da CHANGELOG"
RELEASE_NOTES=$(python3 - "$CHANGELOG_FILE" "$VERSION" <<'PY'
import sys
import re
from pathlib import Path

path, version = sys.argv[1], sys.argv[2]
text = Path(path).read_text()

# Cattura la sezione "## [<version>] - ..." fino al successivo "## [" (o fine file)
# Escape dei punti nella versione per la regex
ver_escaped = re.escape(version)
pattern_with_next = re.compile(
    rf'^## \[{ver_escaped}\][^\n]*\n(.*?)(?=^## \[)',
    re.MULTILINE | re.DOTALL,
)
pattern_to_eof = re.compile(
    rf'^## \[{ver_escaped}\][^\n]*\n(.*)\Z',
    re.MULTILINE | re.DOTALL,
)

m = pattern_with_next.search(text) or pattern_to_eof.search(text)
if not m:
    sys.exit(f"No section [{version}] found in {path}")

print(m.group(1).strip())
PY
)

if [ -z "$RELEASE_NOTES" ]; then
  fail "Release notes vuote per v$VERSION"
fi

# Aggiungi footer setup-instructions
SETUP_FOOTER=$(cat <<EOF

---

## Setup

\`\`\`bash
# Aggiungi il marketplace (una tantum)
/plugin marketplace add acadevmy/ai-setup-meta

# Aggiorna il marketplace per vedere la nuova versione
/plugin marketplace update

# Installa o aggiorna il plugin
/plugin install $TEMPLATE_NAME@acadevmy
\`\`\`
EOF
)

FULL_NOTES="${RELEASE_NOTES}${SETUP_FOOTER}"
ok "Release notes estratte (${#RELEASE_NOTES} caratteri)"

# ── 4. Crea tag annotato ─────────────────────────────────────────────────────
step "Creazione tag annotato"
git -C "$ROOT_DIR" tag -a "$TAG" -m "Release $TEMPLATE_NAME v$VERSION"
ok "Tag $TAG creato in locale"

# ── 5. Push tag ──────────────────────────────────────────────────────────────
step "Push tag a origin"
git -C "$ROOT_DIR" push origin "$TAG"
ok "Tag $TAG pushato"

# ── 6. Crea GitHub Release ───────────────────────────────────────────────────
step "Creazione GitHub Release"
gh release create "$TAG" \
  --title "$TEMPLATE_NAME v$VERSION" \
  --notes "$FULL_NOTES"
ok "GitHub Release creata: $TAG"

step "Done"
echo "Tag:     $TAG"
echo "Release: $(gh release view "$TAG" --json url -q .url)"
