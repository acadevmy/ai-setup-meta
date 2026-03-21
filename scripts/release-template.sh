#!/usr/bin/env bash
# release-template.sh — Pubblica nuova versione del dev-setup-template
# Sincronizza i file dal meta-repo al repo template separato su GitHub.
#
# Uso: bash scripts/release-template.sh [patch|minor|major]
#
# Prerequisiti:
#   - gh CLI autenticata (gh auth login)
#   - .env.local con GITHUB_ORG e GITHUB_TEMPLATE_REPO compilati
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

RELEASE_TYPE="${1:-patch}"
TEMPLATE_SOURCE="templates/dev-setup-template"

if [[ ! "$RELEASE_TYPE" =~ ^(patch|minor|major)$ ]]; then
  fail "Tipo release non valido: '$RELEASE_TYPE'. Usa: patch | minor | major"
fi

# ── Verifica prerequisiti ────────────────────────────────────────────────────
step "Verifica prerequisiti"

command -v gh >/dev/null 2>&1 || fail "gh CLI non trovata. Installa con: brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh CLI non autenticata. Esegui: gh auth login"
ok "gh CLI autenticata"

source .env.local 2>/dev/null || fail "File .env.local non trovato. Copia da .env.example e compila."

[ -n "${GITHUB_ORG:-}" ] || fail "GITHUB_ORG non configurata in .env.local"
[ -n "${GITHUB_TEMPLATE_REPO:-}" ] || fail "GITHUB_TEMPLATE_REPO non configurata in .env.local"
ok "Variabili: GITHUB_ORG=$GITHUB_ORG, GITHUB_TEMPLATE_REPO=$GITHUB_TEMPLATE_REPO"

# ── Verifica branch ─────────────────────────────────────────────────────────
step "Verifica branch e stato git"

CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
  fail "Devi essere su 'main' per fare release. Branch corrente: $CURRENT_BRANCH"
fi

if ! git diff --quiet HEAD; then
  fail "Ci sono modifiche non committate. Fai commit prima di procedere."
fi

ok "Branch: main, nessuna modifica pendente"

# ── Verifica che il repo template esista ─────────────────────────────────────
step "Verifica repo template su GitHub"

TEMPLATE_REPO_URL="git@github.com:${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}.git"

if ! gh repo view "${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}" >/dev/null 2>&1; then
  echo ""
  echo "  Il repo ${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO} non esiste."
  read -rp "  Vuoi crearlo ora? [y/N] " CREATE_REPO
  if [[ "$CREATE_REPO" =~ ^[Yy]$ ]]; then
    gh repo create "${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}" \
      --private \
      --description "Template AI-native per sviluppatori — generato da ai-setup-meta" \
      --clone=false
    ok "Repo ${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO} creato"
  else
    fail "Operazione annullata. Crea il repo manualmente e riprova."
  fi
fi

ok "Repo template: ${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}"

# ── Calcola nuova versione ──────────────────────────────────────────────────
step "Calcolo nuova versione"

CURRENT_VERSION="${TEMPLATE_VERSION:-1.0.0}"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$RELEASE_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"
TODAY=$(date +%Y-%m-%d)
TAG="v$NEW_VERSION"

ok "Versione: $CURRENT_VERSION → $NEW_VERSION"
ok "Tag: $TAG"

# ── Conferma ────────────────────────────────────────────────────────────────
echo ""
echo "  Stai per rilasciare: $TAG ($RELEASE_TYPE)"
echo "  Repo target: ${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}"
read -rp "  Confermi? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Operazione annullata."; exit 0; }

# ── Aggiorna versione nel meta-repo ─────────────────────────────────────────
step "Aggiornamento versione nel meta-repo"

sed -i.bak "s/^TEMPLATE_VERSION=.*/TEMPLATE_VERSION=$NEW_VERSION/" .env.example
rm -f .env.example.bak
ok ".env.example aggiornato"

# Aggiorna CHANGELOG del template
CHANGELOG="$TEMPLATE_SOURCE/CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
  TEMP=$(mktemp)
  head -1 "$CHANGELOG" > "$TEMP"
  echo "" >> "$TEMP"
  echo "## [$NEW_VERSION] - $TODAY" >> "$TEMP"
  echo "" >> "$TEMP"
  echo "- Aggiornamento automatico via release-template.sh" >> "$TEMP"
  echo "- Vedi GitHub Release per dettaglio modifiche" >> "$TEMP"
  tail -n +2 "$CHANGELOG" >> "$TEMP"
  mv "$TEMP" "$CHANGELOG"
  ok "CHANGELOG aggiornato"
fi

# Commit nel meta-repo
git add .env.example "$CHANGELOG" 2>/dev/null || true
if ! git diff --cached --quiet; then
  git commit -m "chore(release): bump dev-setup-template to v$NEW_VERSION"
  ok "Commit nel meta-repo creato"
fi

# ── Sync verso repo template ────────────────────────────────────────────────
step "Sincronizzazione verso ${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Clona il repo template (o inizializza se vuoto)
if git ls-remote "$TEMPLATE_REPO_URL" HEAD >/dev/null 2>&1; then
  git clone --depth 1 "$TEMPLATE_REPO_URL" "$WORK_DIR/template" 2>/dev/null
  ok "Repo template clonato"
else
  mkdir -p "$WORK_DIR/template"
  cd "$WORK_DIR/template"
  git init
  git remote add origin "$TEMPLATE_REPO_URL"
  cd - >/dev/null
  ok "Repo template inizializzato (primo rilascio)"
fi

# Pulisci il contenuto esistente (tranne .git)
find "$WORK_DIR/template" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

# Copia i file del template
cp -R "$TEMPLATE_SOURCE"/. "$WORK_DIR/template/"
ok "File copiati da $TEMPLATE_SOURCE"

# Commit e push nel repo template
cd "$WORK_DIR/template"

git add -A

if git diff --cached --quiet; then
  warn "Nessuna modifica rilevata rispetto alla versione precedente"
  cd - >/dev/null
else
  git commit -m "chore(release): v$NEW_VERSION

Generato automaticamente da ai-setup-meta.
Vedi il meta-repo per la storia completa delle modifiche."

  git tag -a "$TAG" -m "Release dev-setup-template v$NEW_VERSION"

  git push origin main
  git push origin "$TAG"
  cd - >/dev/null
  ok "Push completato su ${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}"
fi

# ── Push meta-repo ──────────────────────────────────────────────────────────
step "Push meta-repo"

git push origin main
ok "Meta-repo aggiornato"

# ── Crea GitHub Release ─────────────────────────────────────────────────────
step "Creazione GitHub Release"

RELEASE_NOTES="Release v$NEW_VERSION ($TODAY)

Tipo: $RELEASE_TYPE
Generata da: ai-setup-meta/scripts/release-template.sh"

# Aggiungi contenuto CHANGELOG se disponibile
if [ -f "$CHANGELOG" ]; then
  CHANGELOG_SECTION=$(sed -n "/## \[$NEW_VERSION\]/,/## \[/p" "$CHANGELOG" | head -n -1)
  if [ -n "$CHANGELOG_SECTION" ]; then
    RELEASE_NOTES="$CHANGELOG_SECTION

---
Generata da: ai-setup-meta/scripts/release-template.sh"
  fi
fi

gh release create "$TAG" \
  --repo "${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}" \
  --title "dev-setup-template v$NEW_VERSION" \
  --notes "$RELEASE_NOTES"

ok "GitHub Release creata"

# ── Riepilogo ───────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Release v$NEW_VERSION completata                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Repo aggiornato: https://github.com/${GITHUB_ORG}/${GITHUB_TEMPLATE_REPO}"
echo "  Tag: $TAG"
echo ""
echo "  La GitHub Release e' la notifica ufficiale per il team."
echo ""
