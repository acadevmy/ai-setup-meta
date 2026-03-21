#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# inject.sh — Innesto workflow AI in codebase esistente
# Installa SOLO il workflow core (CONSTITUTION, AGENT, .claude/, MCP)
# senza toccare il tooling gia' presente nel progetto.
# Esegui: bash inject.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
  echo ""
  printf '%b\n' "${BLUE}╔══════════════════════════════════════════════╗${NC}"
  printf '%b\n' "${BLUE}║   AI Workflow Inject — Codebase esistente    ║${NC}"
  printf '%b\n' "${BLUE}╚══════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() { printf '%b\n' "${GREEN}▸${NC} $1"; }
print_warn() { printf '%b\n' "${YELLOW}⚠${NC} $1"; }
print_error() { printf '%b\n' "${RED}✗${NC} $1"; }
print_info() { printf '%b\n' "${CYAN}ℹ${NC} $1"; }

# ── Prerequisiti minimi ──────────────────────────────────
check_prerequisites() {
  local missing=0

  if ! command -v git &>/dev/null; then
    print_error "git non trovato"
    missing=1
  fi

  if ! command -v claude &>/dev/null; then
    print_warn "Claude CLI non trovato — MCP andra' configurato manualmente"
    print_warn "  Installa: npm install -g @anthropic-ai/claude-code"
    HAS_CLAUDE=false
  else
    HAS_CLAUDE=true
  fi

  if [ "$missing" -eq 1 ]; then
    print_error "Prerequisiti mancanti. Installa git e riprova."
    exit 1
  fi
}

# ── Auto-detection stack ─────────────────────────────────

detect_language() {
  DETECTED_LANGS=()
  [ -f "${PROJECT_DIR}/package.json" ] && DETECTED_LANGS+=("node")
  [ -f "${PROJECT_DIR}/pyproject.toml" ] || [ -f "${PROJECT_DIR}/requirements.txt" ] || [ -f "${PROJECT_DIR}/setup.py" ] && DETECTED_LANGS+=("python")
  [ -f "${PROJECT_DIR}/go.mod" ] && DETECTED_LANGS+=("go")
  [ -f "${PROJECT_DIR}/pubspec.yaml" ] && DETECTED_LANGS+=("flutter")
  [ -f "${PROJECT_DIR}/Cargo.toml" ] && DETECTED_LANGS+=("rust")

  if [ ${#DETECTED_LANGS[@]} -eq 0 ]; then
    DETECTED_LANGS+=("unknown")
  fi
}

detect_test_runner() {
  TEST_COMMAND=""

  if [ -f "${PROJECT_DIR}/package.json" ]; then
    if grep -q '"test"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      if grep -q 'vitest' "${PROJECT_DIR}/package.json" 2>/dev/null; then
        TEST_COMMAND="npx vitest"
      else
        TEST_COMMAND="npm test"
      fi
    fi
  fi

  if [ -z "$TEST_COMMAND" ] && { [ -f "${PROJECT_DIR}/pytest.ini" ] || [ -f "${PROJECT_DIR}/pyproject.toml" ] && grep -q '\[tool\.pytest' "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; }; then
    TEST_COMMAND="pytest"
  fi

  if [ -z "$TEST_COMMAND" ] && [ -f "${PROJECT_DIR}/go.mod" ]; then
    TEST_COMMAND="go test ./..."
  fi

  if [ -z "$TEST_COMMAND" ] && [ -f "${PROJECT_DIR}/pubspec.yaml" ]; then
    TEST_COMMAND="flutter test"
  fi

  if [ -z "$TEST_COMMAND" ] && [ -f "${PROJECT_DIR}/Cargo.toml" ]; then
    TEST_COMMAND="cargo test"
  fi

  [ -z "$TEST_COMMAND" ] && TEST_COMMAND="non rilevato"
}

detect_linter() {
  LINT_COMMAND=""

  # Node/JS linters
  if ls "${PROJECT_DIR}"/.eslintrc* 2>/dev/null | head -1 &>/dev/null || \
     ls "${PROJECT_DIR}"/eslint.config* 2>/dev/null | head -1 &>/dev/null || \
     ([ -f "${PROJECT_DIR}/package.json" ] && grep -q '"eslint"' "${PROJECT_DIR}/package.json" 2>/dev/null); then
    if [ -f "${PROJECT_DIR}/package.json" ] && grep -q '"lint"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      LINT_COMMAND="npm run lint"
    else
      LINT_COMMAND="npx eslint ."
    fi
  fi

  # Python linters
  if [ -z "$LINT_COMMAND" ]; then
    if [ -f "${PROJECT_DIR}/pyproject.toml" ] && grep -q '\[tool\.ruff\]' "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; then
      LINT_COMMAND="ruff check ."
    elif [ -f "${PROJECT_DIR}/.flake8" ] || ([ -f "${PROJECT_DIR}/setup.cfg" ] && grep -q '\[flake8\]' "${PROJECT_DIR}/setup.cfg" 2>/dev/null); then
      LINT_COMMAND="flake8"
    fi
  fi

  # Go linter
  if [ -z "$LINT_COMMAND" ] && [ -f "${PROJECT_DIR}/.golangci.yml" ]; then
    LINT_COMMAND="golangci-lint run"
  fi

  # Dart/Flutter linter
  if [ -z "$LINT_COMMAND" ] && [ -f "${PROJECT_DIR}/analysis_options.yaml" ]; then
    LINT_COMMAND="dart analyze"
  fi

  # Rust linter
  if [ -z "$LINT_COMMAND" ] && [ -f "${PROJECT_DIR}/Cargo.toml" ]; then
    LINT_COMMAND="cargo clippy"
  fi

  [ -z "$LINT_COMMAND" ] && LINT_COMMAND="non rilevato"
}

detect_validation_tool() {
  VALIDATION_TOOL=""

  if [ -f "${PROJECT_DIR}/package.json" ]; then
    if grep -q '"zod"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      VALIDATION_TOOL="Zod"
    elif grep -q '"joi"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      VALIDATION_TOOL="Joi"
    elif grep -q '"yup"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      VALIDATION_TOOL="Yup"
    elif grep -q '"class-validator"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      VALIDATION_TOOL="class-validator"
    fi
  fi

  if [ -z "$VALIDATION_TOOL" ] && [ -f "${PROJECT_DIR}/pyproject.toml" ]; then
    if grep -q 'pydantic' "${PROJECT_DIR}/pyproject.toml" 2>/dev/null; then
      VALIDATION_TOOL="Pydantic"
    fi
  fi

  if [ -z "$VALIDATION_TOOL" ] && [ -f "${PROJECT_DIR}/requirements.txt" ]; then
    if grep -q 'pydantic' "${PROJECT_DIR}/requirements.txt" 2>/dev/null; then
      VALIDATION_TOOL="Pydantic"
    fi
  fi

  [ -z "$VALIDATION_TOOL" ] && VALIDATION_TOOL="non rilevato"
}

detect_has_frontend() {
  HAS_FRONTEND=false

  if [ -f "${PROJECT_DIR}/package.json" ]; then
    if grep -qE '"(next|react|@angular/core|vue|nuxt|svelte)"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      HAS_FRONTEND=true
    fi
  fi

  if [ "$HAS_FRONTEND" = false ] && find "${PROJECT_DIR}/src" -name "*.tsx" -o -name "*.jsx" -o -name "*.vue" 2>/dev/null | head -1 | grep -q .; then
    HAS_FRONTEND=true
  fi
}

detect_has_mobile() {
  HAS_MOBILE=false

  if [ -f "${PROJECT_DIR}/pubspec.yaml" ]; then
    HAS_MOBILE=true
  fi

  if [ "$HAS_MOBILE" = false ] && [ -f "${PROJECT_DIR}/package.json" ]; then
    if grep -qE '"(react-native|expo)"' "${PROJECT_DIR}/package.json" 2>/dev/null; then
      HAS_MOBILE=true
    fi
  fi
}

run_detection() {
  print_step "Analizzo la codebase..."

  detect_language
  detect_test_runner
  detect_linter
  detect_validation_tool
  detect_has_frontend
  detect_has_mobile

  echo ""
  print_info "Stack rilevato:"
  echo "  Linguaggi:   ${DETECTED_LANGS[*]}"
  echo "  Test runner:  ${TEST_COMMAND}"
  echo "  Linter:       ${LINT_COMMAND}"
  echo "  Validazione:  ${VALIDATION_TOOL}"
  echo "  Frontend:     ${HAS_FRONTEND}"
  echo "  Mobile:       ${HAS_MOBILE}"
  echo ""
}

# ── Copia file con conflict detection ────────────────────

safe_copy() {
  local src="$1"
  local dest="$2"
  local label="$3"

  if [ -f "$dest" ]; then
    read -rp "$(printf '%b' "${YELLOW}⚠${NC}") ${label} esiste gia'. Sovrascrivere? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      print_warn "${label} — mantenuto esistente"
      return
    fi
  fi

  cp "$src" "$dest"
  print_step "${label} installato"
}

# ── Genera CONSTITUTION con sezioni rilevanti ────────────

generate_constitution() {
  print_step "Genero CONSTITUTION.md..."

  local src="${SCRIPT_DIR}/CONSTITUTION.md"
  local dest="${PROJECT_DIR}/CONSTITUTION.md"

  if [ -f "$dest" ]; then
    read -rp "$(printf '%b' "${YELLOW}⚠${NC}") CONSTITUTION.md esiste gia'. Sovrascrivere? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      print_warn "CONSTITUTION.md — mantenuto esistente"
      return
    fi
  fi

  # Parti dal file completo, poi rimuovi sezioni non rilevanti
  local content
  content="$(cat "$src")"

  if [ "$HAS_FRONTEND" = false ]; then
    # Rimuovi sezione VI (da "## VI." fino a prima di "## VII." o "## VIII.")
    content="$(echo "$content" | awk '
      /^## VI\./ { skip=1; next }
      /^## (VII|VIII)\./ { skip=0 }
      !skip { print }
    ')"
  fi

  if [ "$HAS_MOBILE" = false ]; then
    # Rimuovi sezione VII (da "## VII." fino a prima di "## VIII.")
    content="$(echo "$content" | awk '
      /^## VII\./ { skip=1; next }
      /^## VIII\./ { skip=0 }
      !skip { print }
    ')"
  fi

  # Per progetti non-TypeScript, aggiungi nota di adattamento nella sezione I
  local has_node=false
  for lang in "${DETECTED_LANGS[@]}"; do
    [ "$lang" = "node" ] && has_node=true
  done

  if [ "$has_node" = false ]; then
    content="$(echo "$content" | sed '/^## I\. Principi fondamentali$/a\
\
> **Nota**: Le regole specifiche a TypeScript\/Zod si applicano ai progetti TypeScript.\
> Per altri linguaggi, applicare il principio equivalente (validazione schema-first\
> con lo strumento appropriato del proprio stack, strict typing nativo del linguaggio).')"
  fi

  echo "$content" > "$dest"
  print_step "CONSTITUTION.md generata (sezioni: core${HAS_FRONTEND:+, frontend}${HAS_MOBILE:+, mobile})"
}

# ── Genera AGENT.md adattivo ─────────────────────────────

generate_agent_md() {
  print_step "Genero AGENT.md..."

  local dest="${PROJECT_DIR}/AGENT.md"

  if [ -f "$dest" ]; then
    read -rp "$(printf '%b' "${YELLOW}⚠${NC}") AGENT.md esiste gia'. Sovrascrivere? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      print_warn "AGENT.md — mantenuto esistente"
      return
    fi
  fi

  local src="${SCRIPT_DIR}/AGENT.inject.md"
  if [ ! -f "$src" ]; then
    print_error "AGENT.inject.md non trovato in ${SCRIPT_DIR}"
    return
  fi

  local content
  content="$(cat "$src")"

  # Sostituisci placeholders
  local stack_desc="${DETECTED_LANGS[*]}"
  [ "$TEST_COMMAND" != "non rilevato" ] && stack_desc="${stack_desc}, test: ${TEST_COMMAND}"
  [ "$LINT_COMMAND" != "non rilevato" ] && stack_desc="${stack_desc}, linter: ${LINT_COMMAND}"
  [ "$VALIDATION_TOOL" != "non rilevato" ] && stack_desc="${stack_desc}, validazione: ${VALIDATION_TOOL}"

  content="${content//\{\{STACK_DESCRIPTION\}\}/${stack_desc}}"
  content="${content//\{\{TEST_COMMAND\}\}/${TEST_COMMAND}}"
  content="${content//\{\{LINT_COMMAND\}\}/${LINT_COMMAND}}"
  content="${content//\{\{VALIDATION_TOOL\}\}/${VALIDATION_TOOL}}"

  echo "$content" > "$dest"
  print_step "AGENT.md generato per stack: ${stack_desc}"
}

# ── Setup Claude Code (.claude/) ─────────────────────────

setup_claude_code() {
  print_step "Configuro Claude Code..."

  mkdir -p "${PROJECT_DIR}/.claude/commands"

  # Settings: merge se esiste, altrimenti copia
  if [ -f "${PROJECT_DIR}/.claude/settings.json" ]; then
    print_warn ".claude/settings.json esiste — mantenuto (verifica compatibilita' manualmente)"
  else
    cp "${SCRIPT_DIR}/.claude/settings.json" "${PROJECT_DIR}/.claude/settings.json"
    print_step ".claude/settings.json installato"
  fi

  # Comandi: copia solo quelli mancanti
  for cmd in start-task.md sync-task.md tdd.md review.md; do
    if [ -f "${PROJECT_DIR}/.claude/commands/${cmd}" ]; then
      print_warn ".claude/commands/${cmd} esiste — mantenuto"
    else
      cp "${SCRIPT_DIR}/.claude/commands/${cmd}" "${PROJECT_DIR}/.claude/commands/${cmd}"
      print_step ".claude/commands/${cmd} installato"
    fi
  done

  print_step "Claude Code configurato"
}

# ── Setup .env ───────────────────────────────────────────

setup_env() {
  if [ -f "${PROJECT_DIR}/.env" ]; then
    # Appendi CLICKUP_SETUP_LIST_ID se mancante
    if ! grep -q 'CLICKUP_SETUP_LIST_ID' "${PROJECT_DIR}/.env" 2>/dev/null; then
      echo "" >> "${PROJECT_DIR}/.env"
      echo "# ClickUp — ID della lista per i task (aggiunto da inject.sh)" >> "${PROJECT_DIR}/.env"
      echo "CLICKUP_SETUP_LIST_ID=" >> "${PROJECT_DIR}/.env"
      print_step "CLICKUP_SETUP_LIST_ID aggiunto a .env"
    else
      print_step "CLICKUP_SETUP_LIST_ID gia' presente in .env"
    fi
  elif [ -f "${PROJECT_DIR}/.env.example" ]; then
    if ! grep -q 'CLICKUP_SETUP_LIST_ID' "${PROJECT_DIR}/.env.example" 2>/dev/null; then
      echo "" >> "${PROJECT_DIR}/.env.example"
      echo "# ClickUp — ID della lista per i task" >> "${PROJECT_DIR}/.env.example"
      echo "CLICKUP_SETUP_LIST_ID=" >> "${PROJECT_DIR}/.env.example"
      print_step "CLICKUP_SETUP_LIST_ID aggiunto a .env.example"
    fi
  else
    cat > "${PROJECT_DIR}/.env.example" << 'ENV'
# ClickUp — ID della lista per i task
CLICKUP_SETUP_LIST_ID=
ENV
    print_step ".env.example creato con CLICKUP_SETUP_LIST_ID"
  fi
}

# ── Setup MCP servers ────────────────────────────────────
# Riusa la stessa logica di init.sh

setup_mcp() {
  print_step "Configuro MCP servers..."

  if [ "$HAS_CLAUDE" = false ]; then
    print_warn "Claude CLI non disponibile — configura MCP manualmente:"
    print_warn "  claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp"
    print_warn "  claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest"
    return
  fi

  # ClickUp — OAuth, user scope
  if claude mcp list 2>/dev/null | grep -q "clickup"; then
    print_step "MCP ClickUp gia' configurato"
  else
    if claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp; then
      print_step "MCP ClickUp aggiunto (autenticati con OAuth al primo uso)"
    else
      print_warn "Errore nell'aggiunta di ClickUp MCP — configuralo manualmente"
    fi
  fi

  # Context7 — documentazione librerie
  if claude mcp list 2>/dev/null | grep -q "context7"; then
    print_step "MCP Context7 gia' configurato"
  else
    if claude mcp add context7 -s project -- npx -y @upstash/context7-mcp@latest; then
      print_step "MCP Context7 aggiunto"
    else
      print_warn "Errore nell'aggiunta di Context7 MCP — configuralo manualmente"
    fi
  fi

  # Figma — solo se frontend rilevato
  if [ "$HAS_FRONTEND" = true ]; then
    echo ""
    read -rp "Frontend rilevato. Vuoi configurare il MCP Figma? (richiede Personal Access Token) [y/N]: " setup_figma
    if [[ "$setup_figma" =~ ^[Yy]$ ]]; then
      read -rp "Inserisci il Figma Personal Access Token: " figma_token
      if [ -n "$figma_token" ]; then
        claude mcp add figma -s project -e FIGMA_ACCESS_TOKEN="$figma_token" -- npx -y @figma/mcp-server
        print_step "MCP Figma aggiunto"
      else
        print_warn "Token vuoto — MCP Figma non configurato"
      fi
    fi
  fi
}

# ── Cleanup ──────────────────────────────────────────────

cleanup() {
  # Rimuovi inject.sh dal progetto (se copiato li')
  if [ -f "${PROJECT_DIR}/inject.sh" ] && [ "${PROJECT_DIR}/inject.sh" != "${SCRIPT_DIR}/inject.sh" ]; then
    rm "${PROJECT_DIR}/inject.sh"
    print_step "inject.sh rimosso dal progetto"
  fi

  # Rimuovi AGENT.inject.md se copiato nel progetto
  if [ -f "${PROJECT_DIR}/AGENT.inject.md" ]; then
    rm "${PROJECT_DIR}/AGENT.inject.md"
  fi
}

# ── Riepilogo ────────────────────────────────────────────

print_summary() {
  echo ""
  printf '%b\n' "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  printf '%b\n' "${GREEN}║       Workflow AI innestato con successo!    ║${NC}"
  printf '%b\n' "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo "File installati:"
  echo "  - CONSTITUTION.md       — regole di governance"
  echo "  - AGENT.md              — istruzioni per Claude Code"
  echo "  - .claude/              — settings + slash commands"
  echo ""
  echo "Stack rilevato:"
  echo "  - Linguaggi:   ${DETECTED_LANGS[*]}"
  echo "  - Test runner:  ${TEST_COMMAND}"
  echo "  - Linter:       ${LINT_COMMAND}"
  echo "  - Validazione:  ${VALIDATION_TOOL}"
  echo ""
  echo "NON modificato (tooling esistente rispettato):"
  echo "  - Git hooks, ESLint, Prettier, CI/CD, .gitignore"
  echo ""
  echo "Prossimi passi:"
  echo "  1. Compila CLICKUP_SETUP_LIST_ID nel file .env"
  echo "  2. Verifica MCP: claude mcp list"
  echo "  3. Usa /project:start-task per iniziare un task ClickUp"
  echo ""
}

# ── Main ─────────────────────────────────────────────────

main() {
  print_header
  check_prerequisites
  run_detection

  echo "Procedo con l'installazione del workflow AI."
  echo "Il tooling esistente (hooks, linter, formatter, CI) NON verra' modificato."
  echo ""
  read -rp "Continuare? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Annullato."
    exit 0
  fi

  echo ""
  generate_constitution
  generate_agent_md
  setup_claude_code
  setup_env
  setup_mcp
  cleanup
  print_summary
}

main "$@"
