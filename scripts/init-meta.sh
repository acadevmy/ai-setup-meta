#!/usr/bin/env bash
# init-meta.sh — Bootstrap iniziale del meta-repo ai-setup-meta
# Eseguire una sola volta dopo il primo clone.

set -euo pipefail

# ── Colori ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      ai-setup-meta — Bootstrap iniziale      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Prerequisiti ───────────────────────────────────────────────────────────
step "Verifica prerequisiti"

command -v node   >/dev/null 2>&1 || fail "Node.js non trovato. Installa Node.js 20+."
command -v npm    >/dev/null 2>&1 || fail "npm non trovato."
command -v git    >/dev/null 2>&1 || fail "git non trovato."
command -v claude >/dev/null 2>&1 || warn "Claude Code non trovato nel PATH. Installa con: npm install -g @anthropic-ai/claude-code"

# gh CLI — installa automaticamente se mancante
if ! command -v gh >/dev/null 2>&1; then
  warn "gh CLI non trovata. Tentativo di installazione..."
  if command -v brew >/dev/null 2>&1; then
    brew install gh && ok "gh CLI installata via Homebrew"
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y gh && ok "gh CLI installata via apt"
  else
    fail "gh CLI non trovata e installazione automatica non disponibile. Installa da https://cli.github.com"
  fi
else
  ok "gh CLI $(gh --version | head -1 | awk '{print $3}')"
fi

NODE_VERSION=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
if [ "$NODE_VERSION" -lt 20 ]; then
  fail "Node.js 20+ richiesto. Versione attuale: $(node -v)"
fi

ok "Node.js $(node -v)"
ok "npm $(npm -v)"
ok "git $(git --version | awk '{print $3}')"

# ── 2. Variabili d'ambiente ───────────────────────────────────────────────────
step "Configurazione variabili d'ambiente"

# ── 2. Autenticazione GitHub via gh CLI ──────────────────────────────────────
step "Autenticazione GitHub"

if gh auth status >/dev/null 2>&1; then
  GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
  ok "gh CLI autenticata come: $GH_USER"
else
  echo "  GitHub usa gh CLI — si apre il browser per autorizzare con il tuo account."
  echo ""
  read -rp "Premi INVIO per avviare l'autenticazione GitHub (o Ctrl+C per saltare)..."
  gh auth login || fail "Autenticazione GitHub fallita. Riprova con: gh auth login"
  ok "gh CLI autenticata"
fi

# ── 3. Variabili d'ambiente (opzionali) ─────────────────────────────────────
step "Configurazione variabili d'ambiente"

if [ ! -f ".env.local" ]; then
  if [ -f ".env.example" ]; then
    cp .env.example .env.local
  else
    touch .env.local
  fi
  warn ".env.local creato — compila le variabili opzionali se necessario."
  echo ""
  echo "  Variabili opzionali:"
  echo "    FIGMA_ACCESS_TOKEN → figma.com > Account Settings > Personal tokens"
  echo ""
  echo "  GitHub: autenticato via gh CLI — nessun token manuale necessario."
  echo "  ClickUp: si configura via OAuth al passo successivo."
  echo ""
  read -rp "Premi INVIO per continuare..."
fi

# Carica variabili (se presenti)
if [ -s ".env.local" ]; then
  set -a
  # shellcheck source=.env.local
  source .env.local
  set +a
  ok ".env.local caricato"
fi

# Figma non bloccante
if [ -z "${FIGMA_ACCESS_TOKEN:-}" ]; then
  warn "FIGMA_ACCESS_TOKEN non impostata — MCP Figma non disponibile"
fi

# ── 4. Installazione dipendenze MCP ──────────────────────────────────────────
step "Installazione MCP servers"

MCP_SERVERS=(
  "@upstash/context7-mcp"
)

for PKG in "${MCP_SERVERS[@]}"; do
  echo "  → Verifico $PKG..."
  npx -y "$PKG" --version >/dev/null 2>&1 && ok "$PKG disponibile" || warn "$PKG non raggiungibile (verifica connessione)"
done

# Figma MCP opzionale
if [ -n "${FIGMA_ACCESS_TOKEN:-}" ]; then
  npx -y @figma/mcp-server --version >/dev/null 2>&1 && ok "@figma/mcp-server disponibile" || warn "@figma/mcp-server non raggiungibile"
fi

# ── 5. Configurazione MCP in Claude Code ─────────────────────────────────────
step "Configurazione MCP in Claude Code"

MCP_TARGET="${HOME}/.claude/mcp.json"
mkdir -p "$(dirname "$MCP_TARGET")"

# Genera mcp.json — GitHub usa gh CLI (no MCP), ClickUp usa OAuth
cat > "$MCP_TARGET" <<EOF
{
  "mcpServers": {
    "clickup": {
      "type": "url",
      "url": "https://mcp.clickup.com/mcp"
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
    $([ -n "${FIGMA_ACCESS_TOKEN:-}" ] && echo ',
    "figma": {
      "command": "npx",
      "args": ["-y", "@figma/mcp-server"],
      "env": {
        "FIGMA_ACCESS_TOKEN": "'"${FIGMA_ACCESS_TOKEN}"'"
      }
    }')
  }
}
EOF

ok "MCP configurato in $MCP_TARGET"

ok "ClickUp configurato — l'autenticazione OAuth avverra' automaticamente al primo utilizzo"

# ── 6. Verifica git ───────────────────────────────────────────────────────────
step "Verifica configurazione git"

GIT_USER=$(git config --global user.name  2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
  warn "git user.name o user.email non configurati globalmente."
  echo "  Esegui:"
  echo "    git config --global user.name  \"Nome Cognome\""
  echo "    git config --global user.email \"email@azienda.it\""
else
  ok "git user: $GIT_USER <$GIT_EMAIL>"
fi

# Verifica branch protection (informativo)
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
ok "Branch corrente: $CURRENT_BRANCH"

if [ "$CURRENT_BRANCH" = "main" ]; then
  warn "Sei su 'main'. Crea sempre un branch prima di operare con Claude Code."
fi

# ── 7. Riepilogo ─────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║             Setup completato ✓               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Prossimi passi:"
echo ""
echo "  1. Crea un branch di lavoro:"
echo "     git checkout -b chore/initial-setup"
echo ""
echo "  2. Avvia Claude Code:"
echo "     claude"
echo ""
echo "  3. Genera il dev-setup-template:"
echo "     /project:generate-setup"
echo ""
echo "  Documentazione: docs/workflow.md"
echo ""
