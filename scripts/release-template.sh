#!/usr/bin/env bash
# release-template.sh — Pubblica setup agent + agent di dominio sul repo di distribuzione
# Sincronizza dist/ (setup.md, agents/, CHANGELOG, README) dal meta-repo al repo dist.
#
# Uso: bash scripts/release-template.sh [patch|minor|major] [template-name] [--yes]
#
# Prerequisiti:
#   - gh CLI autenticata (gh auth login)
#   - .env.local con GITHUB_ORG e GITHUB_DIST_REPO compilati
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

# ── Verifica prerequisiti ────────────────────────────────────────────────────
step "Verifica prerequisiti"

command -v gh >/dev/null 2>&1 || fail "gh CLI non trovata. Installa con: brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh CLI non autenticata. Esegui: gh auth login"
ok "gh CLI autenticata"

source .env.local 2>/dev/null || fail "File .env.local non trovato. Copia da .env.example e compila."

[ -n "${GITHUB_ORG:-}" ] || fail "GITHUB_ORG non configurata in .env.local"
[ -n "${GITHUB_DIST_REPO:-}" ] || fail "GITHUB_DIST_REPO non configurata in .env.local"
ok "Variabili: GITHUB_ORG=$GITHUB_ORG, GITHUB_DIST_REPO=$GITHUB_DIST_REPO"

# Verifica che setup.md esista
[ -f "dist/setup.md" ] || fail "dist/setup.md non trovato. Generalo prima di rilasciare."

# Se template non specificato, trova quelli disponibili
if [ -z "$TEMPLATE_NAME" ]; then
  TEMPLATES=($(ls -d templates/*/manifest.json 2>/dev/null | xargs -I {} dirname {} | xargs -I {} basename {}))
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

TEMPLATE_DIR="templates/$TEMPLATE_NAME"
[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' non trovato in templates/"
[ -f "$TEMPLATE_DIR/manifest.json" ] || fail "manifest.json non trovato in $TEMPLATE_DIR/"

# Leggi agent name dal manifest
AGENT_FILE=$(python3 -c "import json; print(json.load(open('$TEMPLATE_DIR/manifest.json'))['agent'])" 2>/dev/null || echo "")
[ -n "$AGENT_FILE" ] || fail "Campo 'agent' non trovato in manifest.json"
[ -f "$TEMPLATE_DIR/$AGENT_FILE" ] || fail "Agent file '$AGENT_FILE' non trovato in $TEMPLATE_DIR/"
ok "Template: $TEMPLATE_NAME, Agent: $AGENT_FILE"

# Validazione URL
if [ -f "scripts/validate-setup-urls.sh" ]; then
  bash scripts/validate-setup-urls.sh || fail "Validazione URL fallita. Correggi prima di rilasciare."
fi

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

# ── Verifica che il repo dist esista ─────────────────────────────────────────
step "Verifica repo distribuzione su GitHub"

DIST_REPO_URL="git@github.com:${GITHUB_ORG}/${GITHUB_DIST_REPO}.git"

if ! gh repo view "${GITHUB_ORG}/${GITHUB_DIST_REPO}" >/dev/null 2>&1; then
  echo ""
  echo "  Il repo ${GITHUB_ORG}/${GITHUB_DIST_REPO} non esiste."
  if [ "$AUTO_CONFIRM" = false ]; then
    read -rp "  Vuoi crearlo ora? [y/N] " CREATE_REPO
  else
    CREATE_REPO="y"
  fi
  if [[ "$CREATE_REPO" =~ ^[Yy]$ ]]; then
    gh repo create "${GITHUB_ORG}/${GITHUB_DIST_REPO}" \
      --private \
      --description "Setup agent AI-native — scarica ed esegui /project:setup" \
      --clone=false
    ok "Repo ${GITHUB_ORG}/${GITHUB_DIST_REPO} creato"
  else
    fail "Operazione annullata. Crea il repo manualmente e riprova."
  fi
fi

ok "Repo distribuzione: ${GITHUB_ORG}/${GITHUB_DIST_REPO}"

# ── Calcola nuova versione ──────────────────────────────────────────────────
step "Calcolo nuova versione"

# Leggi TEMPLATE_VERSION dal .env.example del template
CURRENT_VERSION=$(grep -oP 'TEMPLATE_VERSION=\K.*' "$TEMPLATE_DIR/.env.example" 2>/dev/null || echo "1.0.0")

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

# ── Conferma ────────────────────────────────────────────────────────────────
echo ""
echo "  Stai per rilasciare: $TAG ($RELEASE_TYPE)"
echo "  Template: $TEMPLATE_NAME"
echo "  Repo target: ${GITHUB_ORG}/${GITHUB_DIST_REPO}"
echo "  Contenuto: setup.md + agents/ + README.md + CHANGELOG.md"
if [ "$AUTO_CONFIRM" = false ]; then
  read -rp "  Confermi? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Operazione annullata."; exit 0; }
fi

# ── Aggiorna CHANGELOG ────────────────────────────────────────────────────────
step "Aggiornamento CHANGELOG"

CHANGELOG_FILE="$TEMPLATE_DIR/CHANGELOG.md"
PREV_TAG="${TEMPLATE_NAME}-v${CURRENT_VERSION}"

# Raccogli i commit che hanno toccato il template dalla versione precedente
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

# Genera la nuova entry
NEW_ENTRY="## [$NEW_VERSION] - $TODAY"
[ -n "$CHANGELOG_ADDED" ]  && NEW_ENTRY="${NEW_ENTRY}\n\n### Added$(echo -e "$CHANGELOG_ADDED")"
[ -n "$CHANGELOG_CHANGED" ] && NEW_ENTRY="${NEW_ENTRY}\n\n### Changed$(echo -e "$CHANGELOG_CHANGED")"
[ -n "$CHANGELOG_FIXED" ]   && NEW_ENTRY="${NEW_ENTRY}\n\n### Fixed$(echo -e "$CHANGELOG_FIXED")"

# Se nessun commit trovato, inserisci una riga generica
if [ -z "$CHANGELOG_ADDED" ] && [ -z "$CHANGELOG_CHANGED" ] && [ -z "$CHANGELOG_FIXED" ]; then
  NEW_ENTRY="${NEW_ENTRY}\n\n### Changed\n- Aggiornamento setup agent"
fi

# Inserisci la nuova entry dopo l'header del CHANGELOG
sed -i.bak '/^## \[/,$!b; /^## \[/{i\
'"$(echo -e "$NEW_ENTRY")"'
;:a;n;ba}' "$CHANGELOG_FILE" 2>/dev/null || true
rm -f "${CHANGELOG_FILE}.bak"

# Fallback: se sed non ha funzionato, usa approccio con file temporaneo
if ! grep -q "\[$NEW_VERSION\]" "$CHANGELOG_FILE"; then
  TMPFILE=$(mktemp)
  HEAD_LINES=$(grep -n '^## \[' "$CHANGELOG_FILE" | head -1 | cut -d: -f1)
  head -n $((HEAD_LINES - 1)) "$CHANGELOG_FILE" > "$TMPFILE"
  echo -e "$NEW_ENTRY\n" >> "$TMPFILE"
  tail -n +"$HEAD_LINES" "$CHANGELOG_FILE" >> "$TMPFILE"
  mv "$TMPFILE" "$CHANGELOG_FILE"
fi

ok "CHANGELOG.md aggiornato con v$NEW_VERSION"

# ── Aggiorna versione nel template ──────────────────────────────────────────
step "Aggiornamento versione nel template"

sed -i.bak "s/^TEMPLATE_VERSION=.*/TEMPLATE_VERSION=$NEW_VERSION/" "$TEMPLATE_DIR/.env.example"
rm -f "$TEMPLATE_DIR/.env.example.bak"
ok "$TEMPLATE_DIR/.env.example aggiornato"

# ── Copia agent di dominio in dist/ ─────────────────────────────────────────
step "Aggiornamento dist/"

mkdir -p dist/agents
cp "$TEMPLATE_DIR/$AGENT_FILE" "dist/agents/$AGENT_FILE"
ok "Agent di dominio copiato in dist/agents/$AGENT_FILE"

# Commit nel meta-repo
git add "$TEMPLATE_DIR/.env.example" "$CHANGELOG_FILE" "dist/agents/$AGENT_FILE"
if ! git diff --cached --quiet; then
  git commit -m "chore(release): bump $TEMPLATE_NAME to v$NEW_VERSION"
  ok "Commit nel meta-repo creato"
fi

# ── Sync verso repo distribuzione ──────────────────────────────────────────
step "Sincronizzazione verso ${GITHUB_ORG}/${GITHUB_DIST_REPO}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Clona il repo dist (o inizializza se vuoto)
if git ls-remote "$DIST_REPO_URL" HEAD >/dev/null 2>&1; then
  git clone --depth 1 "$DIST_REPO_URL" "$WORK_DIR/dist" 2>/dev/null
  ok "Repo distribuzione clonato"
else
  mkdir -p "$WORK_DIR/dist"
  cd "$WORK_DIR/dist"
  git init
  git remote add origin "$DIST_REPO_URL"
  cd - >/dev/null
  ok "Repo distribuzione inizializzato (primo rilascio)"
fi

# Pulisci il contenuto esistente (tranne .git)
find "$WORK_DIR/dist" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

# Copia setup.md (dispatcher)
mkdir -p "$WORK_DIR/dist/.claude/skills/setup"
cp dist/setup.md "$WORK_DIR/dist/.claude/skills/setup/SKILL.md"
ok "setup.md (dispatcher) copiato"

# Copia agent di dominio
mkdir -p "$WORK_DIR/dist/.claude/agents"
cp dist/agents/*.md "$WORK_DIR/dist/.claude/agents/"
ok "Agent di dominio copiati"

# Copia CHANGELOG.md
cp "$CHANGELOG_FILE" "$WORK_DIR/dist/CHANGELOG.md"
ok "CHANGELOG.md copiato"

# Genera README per il repo distribuzione
AVAILABLE_TEMPLATES=$(ls -d templates/*/manifest.json 2>/dev/null | while read f; do
  DIR=$(dirname "$f")
  NAME=$(basename "$DIR")
  DESC=$(python3 -c "import json; print(json.load(open('$f'))['description'])" 2>/dev/null || echo "")
  echo "- **$NAME**: $DESC"
done)

cat > "$WORK_DIR/dist/README.md" << READMEEOF
# AI Setup Agent

Setup agent AI-Native — seleziona il dominio e configura il tuo progetto.

## Avvio rapido

\`\`\`bash
# 1. Nel tuo progetto, scarica il setup agent e gli agent di dominio
mkdir -p .claude/skills/setup .claude/agents && \\
  curl -sL https://raw.githubusercontent.com/${GITHUB_ORG}/${GITHUB_DIST_REPO}/main/.claude/skills/setup/SKILL.md \\
    -o .claude/skills/setup/SKILL.md && \\
  for agent in \$(curl -sL "https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_DIST_REPO}/contents/.claude/agents" | python3 -c "import sys,json; [print(f['name']) for f in json.load(sys.stdin) if f['name'].endswith('.md')]" 2>/dev/null); do \\
    curl -sL "https://raw.githubusercontent.com/${GITHUB_ORG}/${GITHUB_DIST_REPO}/main/.claude/agents/\$agent" \\
      -o ".claude/agents/\$agent"; \\
  done

# 2. Avvia Claude Code ed esegui il setup
claude
# poi digita: /project:setup
\`\`\`

## Domini disponibili

$AVAILABLE_TEMPLATES

## Come funziona

1. Il dispatcher (\`/project:setup\`) ti chiede quale tipo di setup vuoi
2. Lancia l'agent di dominio corrispondente gia' scaricato in locale
3. L'agent di dominio configura tutto: governance, skill, agent, MCP

## Aggiornamento

Per aggiornare, riesegui il curl e poi \`/project:setup\`. L'agente rileva
che il setup e' gia' presente e aggiorna solo i file necessari.

---
*Generato da [ai-setup-meta](https://github.com/${GITHUB_ORG}/ai-setup-meta)*
READMEEOF
ok "README.md generato"

# Commit e push nel repo distribuzione
cd "$WORK_DIR/dist"

git add -A

if git diff --cached --quiet; then
  warn "Nessuna modifica rilevata rispetto alla versione precedente"
  cd - >/dev/null
else
  git commit -m "chore(release): v$NEW_VERSION ($TEMPLATE_NAME)

Generato automaticamente da ai-setup-meta.
Contiene: dispatcher + agent di dominio."

  git tag -a "$TAG" -m "Release $TEMPLATE_NAME v$NEW_VERSION"

  git push origin main
  git push origin "$TAG"
  cd - >/dev/null
  ok "Push completato su ${GITHUB_ORG}/${GITHUB_DIST_REPO}"
fi

# ── Push meta-repo ──────────────────────────────────────────────────────────
step "Push meta-repo"

git push origin main
ok "Meta-repo aggiornato"

# ── Crea GitHub Release ─────────────────────────────────────────────────────
step "Creazione GitHub Release"

RELEASE_NOTES="## Release $TEMPLATE_NAME v$NEW_VERSION ($TODAY)

Tipo: $RELEASE_TYPE

### Setup

\`\`\`bash
mkdir -p .claude/skills/setup .claude/agents && \\
  curl -sL https://raw.githubusercontent.com/${GITHUB_ORG}/${GITHUB_DIST_REPO}/main/.claude/skills/setup/SKILL.md \\
    -o .claude/skills/setup/SKILL.md && \\
  curl -sL https://raw.githubusercontent.com/${GITHUB_ORG}/${GITHUB_DIST_REPO}/main/.claude/agents/${AGENT_FILE} \\
    -o .claude/agents/${AGENT_FILE}
\`\`\`

Poi esegui \`/project:setup\` in Claude Code.

---
Generata da: ai-setup-meta/scripts/release-template.sh"

gh release create "$TAG" \
  --repo "${GITHUB_ORG}/${GITHUB_DIST_REPO}" \
  --title "$TEMPLATE_NAME v$NEW_VERSION" \
  --notes "$RELEASE_NOTES"

ok "GitHub Release creata"

# ── Riepilogo ───────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Release $TEMPLATE_NAME v$NEW_VERSION completata              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Repo aggiornato: https://github.com/${GITHUB_ORG}/${GITHUB_DIST_REPO}"
echo "  Tag: $TAG"
echo "  Contenuto: setup.md + agents/ + README.md + CHANGELOG.md"
echo ""
