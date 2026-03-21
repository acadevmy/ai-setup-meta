#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# init.sh — Bootstrap interattivo per dev-setup-template
# Esegui: bash init.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   AI-Native Dev Setup — Inizializzazione    ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() {
  echo -e "${GREEN}▸${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
  echo -e "${RED}✗${NC} $1"
}

# ── Verifica prerequisiti ──────────────────────────────────
check_prerequisites() {
  local missing=0

  if ! command -v node &>/dev/null; then
    print_error "Node.js non trovato. Installa Node.js 20+ da https://nodejs.org"
    missing=1
  else
    local node_version
    node_version=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$node_version" -lt 20 ]; then
      print_error "Node.js $node_version trovato, richiesto 20+"
      missing=1
    fi
  fi

  if ! command -v npm &>/dev/null; then
    print_error "npm non trovato"
    missing=1
  fi

  if ! command -v git &>/dev/null; then
    print_error "git non trovato"
    missing=1
  fi

  if ! command -v gh &>/dev/null; then
    print_warn "GitHub CLI (gh) non trovato — le operazioni GitHub non saranno disponibili"
  fi

  if [ "$missing" -eq 1 ]; then
    echo ""
    print_error "Prerequisiti mancanti. Installa i tool richiesti e riprova."
    exit 1
  fi
}

# ── Menu selezione stack ──────────────────────────────────
select_stack() {
  echo "Seleziona il profilo stack per questo progetto:"
  echo ""
  echo "  1) Web Frontend    — Next.js / Angular / React + ShadCN/UI + Tailwind"
  echo "  2) Backend Node    — Node.js / NestJS + Prisma + Zod"
  echo "  3) Mobile          — Flutter / React Native (Expo)"
  echo "  4) Full-stack      — Frontend + Backend (monorepo)"
  echo ""
  read -rp "Scelta [1-4]: " stack_choice

  case "$stack_choice" in
    1) STACK="web-frontend" ;;
    2) STACK="backend-node" ;;
    3) STACK="mobile" ;;
    4) STACK="fullstack" ;;
    *)
      print_error "Scelta non valida"
      exit 1
      ;;
  esac

  print_step "Stack selezionato: ${STACK}"
}

# ── Selezione sub-framework (per mobile) ──────────────────
select_mobile_framework() {
  if [ "$STACK" = "mobile" ]; then
    echo ""
    echo "Seleziona il framework mobile:"
    echo ""
    echo "  1) Flutter"
    echo "  2) React Native (Expo)"
    echo ""
    read -rp "Scelta [1-2]: " mobile_choice

    case "$mobile_choice" in
      1) MOBILE_FW="flutter" ;;
      2) MOBILE_FW="react-native" ;;
      *)
        print_error "Scelta non valida"
        exit 1
        ;;
    esac

    print_step "Framework mobile: ${MOBILE_FW}"
  fi
}

# ── Copia file base ──────────────────────────────────────
copy_base_files() {
  print_step "Copio file base..."

  cp "${SCRIPT_DIR}/CONSTITUTION.md" "${PROJECT_DIR}/CONSTITUTION.md"
  cp "${SCRIPT_DIR}/AGENT.md" "${PROJECT_DIR}/AGENT.md"
  cp "${SCRIPT_DIR}/mcp.json.example" "${PROJECT_DIR}/mcp.json.example"
  cp "${SCRIPT_DIR}/.env.example" "${PROJECT_DIR}/.env.example"

  print_step "File base copiati"
}

# ── Setup Claude Code ────────────────────────────────────
setup_claude_code() {
  print_step "Configuro Claude Code..."

  mkdir -p "${PROJECT_DIR}/.claude/commands"

  cp "${SCRIPT_DIR}/.claude/settings.json" "${PROJECT_DIR}/.claude/settings.json"

  # Copia comandi slash
  if [ -d "${SCRIPT_DIR}/.claude/commands" ]; then
    cp -r "${SCRIPT_DIR}/.claude/commands/"* "${PROJECT_DIR}/.claude/commands/" 2>/dev/null || true
  fi

  print_step "Claude Code configurato"
}

# ── Setup Husky + quality tools ──────────────────────────
setup_quality_tools() {
  print_step "Configuro strumenti di qualità..."

  # Installa dipendenze di qualità
  npm install --save-dev \
    husky \
    @commitlint/cli \
    @commitlint/config-conventional \
    prettier \
    eslint \
    @typescript-eslint/eslint-plugin \
    @typescript-eslint/parser \
    2>/dev/null

  # Inizializza Husky
  npx husky init 2>/dev/null || true

  # Copia hook
  mkdir -p "${PROJECT_DIR}/.husky"
  cp "${SCRIPT_DIR}/.husky/pre-commit" "${PROJECT_DIR}/.husky/pre-commit"
  cp "${SCRIPT_DIR}/.husky/commit-msg" "${PROJECT_DIR}/.husky/commit-msg"
  chmod +x "${PROJECT_DIR}/.husky/pre-commit"
  chmod +x "${PROJECT_DIR}/.husky/commit-msg"

  # Copia configurazioni
  cp "${SCRIPT_DIR}/.commitlintrc.json" "${PROJECT_DIR}/.commitlintrc.json"
  cp "${SCRIPT_DIR}/.prettierrc.json" "${PROJECT_DIR}/.prettierrc.json"
  cp "${SCRIPT_DIR}/.eslintrc.base.json" "${PROJECT_DIR}/.eslintrc.base.json"

  print_step "Strumenti di qualità configurati"
}

# ── Applica profilo stack ────────────────────────────────
apply_profile() {
  print_step "Applico profilo ${STACK}..."

  local profile_dir="${SCRIPT_DIR}/profiles/${STACK}"

  if [ -d "$profile_dir" ]; then
    # Copia ESLint specifico se presente
    if [ -f "${profile_dir}/.eslintrc.json" ]; then
      cp "${profile_dir}/.eslintrc.json" "${PROJECT_DIR}/.eslintrc.json"
    fi

    # Copia tsconfig se presente
    if [ -f "${profile_dir}/tsconfig.json" ]; then
      cp "${profile_dir}/tsconfig.json" "${PROJECT_DIR}/tsconfig.json"
    fi

    # Copia jest config se presente
    if [ -f "${profile_dir}/jest.config.ts" ]; then
      cp "${profile_dir}/jest.config.ts" "${PROJECT_DIR}/jest.config.ts"
    fi

    # Per Flutter: copia analysis_options
    if [ -f "${profile_dir}/analysis_options.yaml" ]; then
      cp "${profile_dir}/analysis_options.yaml" "${PROJECT_DIR}/analysis_options.yaml"
    fi
  fi

  # Fullstack: applica sia frontend che backend
  if [ "$STACK" = "fullstack" ]; then
    print_step "Setup monorepo fullstack..."
    mkdir -p "${PROJECT_DIR}/apps/web" "${PROJECT_DIR}/apps/api"

    if [ -d "${SCRIPT_DIR}/profiles/web-frontend" ]; then
      cp "${SCRIPT_DIR}/profiles/web-frontend/.eslintrc.json" "${PROJECT_DIR}/apps/web/.eslintrc.json" 2>/dev/null || true
      cp "${SCRIPT_DIR}/profiles/web-frontend/tsconfig.json" "${PROJECT_DIR}/apps/web/tsconfig.json" 2>/dev/null || true
    fi

    if [ -d "${SCRIPT_DIR}/profiles/backend-node" ]; then
      cp "${SCRIPT_DIR}/profiles/backend-node/.eslintrc.json" "${PROJECT_DIR}/apps/api/.eslintrc.json" 2>/dev/null || true
      cp "${SCRIPT_DIR}/profiles/backend-node/tsconfig.json" "${PROJECT_DIR}/apps/api/tsconfig.json" 2>/dev/null || true
    fi
  fi

  print_step "Profilo ${STACK} applicato"
}

# ── Setup .gitignore ─────────────────────────────────────
setup_gitignore() {
  if [ ! -f "${PROJECT_DIR}/.gitignore" ]; then
    cat > "${PROJECT_DIR}/.gitignore" << 'GITIGNORE'
# Dependencies
node_modules/
.pnp
.pnp.js

# Build
dist/
build/
.next/
out/

# Environment
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Testing
coverage/

# Misc
*.log
npm-debug.log*
GITIGNORE
    print_step ".gitignore creato"
  fi
}

# ── Riepilogo ────────────────────────────────────────────
print_summary() {
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║          Setup completato con successo!      ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo "File generati:"
  echo "  - CONSTITUTION.md      — regole di governance"
  echo "  - AGENT.md             — istruzioni per Claude Code"
  echo "  - .claude/             — configurazione Claude Code"
  echo "  - .husky/              — git hooks (lint + commit)"
  echo "  - .eslintrc.base.json  — configurazione ESLint base"
  echo "  - .prettierrc.json     — configurazione Prettier"
  echo "  - .commitlintrc.json   — configurazione Commitlint"
  echo "  - .env.example         — variabili d'ambiente richieste"
  echo "  - mcp.json.example     — template MCP"
  echo ""
  echo "Prossimi passi:"
  echo "  1. Copia .env.example in .env e compila le variabili"
  echo "  2. Configura i MCP: claude mcp add clickup https://mcp.clickup.com/mcp"
  echo "  3. Esegui npm install per installare le dipendenze"
  echo "  4. Inizia a sviluppare seguendo il workflow TDD!"
  echo ""
}

# ── Main ─────────────────────────────────────────────────
main() {
  print_header
  check_prerequisites
  select_stack
  select_mobile_framework
  copy_base_files
  setup_claude_code
  setup_quality_tools
  apply_profile
  setup_gitignore
  print_summary
}

main "$@"
