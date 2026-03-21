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

NODE_VERSION=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
if [ "$NODE_VERSION" -lt 20 ]; then
  fail "Node.js 20+ richiesto. Versione attuale: $(node -v)"
fi

ok "Node.js $(node -v)"
ok "npm $(npm -v)"
ok "git $(git --version | awk '{print $3}')"

# ── 2. Variabili d'ambiente ───────────────────────────────────────────────────
step "Configurazione variabili d'ambiente"

if [ ! -f ".env.local" ]; then
  cp .env.example .env.local
  warn ".env.local creato da .env.example — compila le API key prima di procedere."
  echo ""
  echo "  File da compilare: .env.local"
  echo "  Variabili richieste:"
  echo "    GITHUB_TOKEN       → github.com > Settings > Developer settings > PAT"
  echo "    GITHUB_ORG         → nome organizzazione GitHub"
  echo "    CLICKUP_API_KEY    → app.clickup.com > Settings > Apps"
  echo "    CLICKUP_TEAM_ID    → URL workspace ClickUp"
  echo "    FIGMA_ACCESS_TOKEN → figma.com > Account Settings > Personal tokens"
  echo ""
  read -rp "Premi INVIO dopo aver compilato .env.local, oppure Ctrl+C per uscire..."
fi

# Carica variabili
set -a
# shellcheck source=.env.local
source .env.local
set +a

ok ".env.local caricato"

# ── 3. Verifica variabili obbligatorie ────────────────────────────────────────
step "Verifica variabili obbligatorie"

MISSING=0
for VAR in GITHUB_TOKEN GITHUB_ORG CLICKUP_API_KEY CLICKUP_TEAM_ID; do
  if [ -z "${!VAR:-}" ]; then
    warn "Variabile mancante: $VAR"
    MISSING=1
  else
    ok "$VAR impostata"
  fi
done

# Figma non bloccante
if [ -z "${FIGMA_ACCESS_TOKEN:-}" ]; then
  warn "FIGMA_ACCESS_TOKEN non impostata — MCP Figma non disponibile"
fi

if [ "$MISSING" -eq 1 ]; then
  fail "Alcune variabili obbligatorie mancano. Compila .env.local e riprova."
fi

# ── 4. Installazione dipendenze MCP ──────────────────────────────────────────
step "Installazione MCP servers"

MCP_SERVERS=(
  "@modelcontextprotocol/server-github"
  "@ClickUp/mcp-server"
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

# Genera mcp.json con le variabili reali sostituite
cat > "$MCP_TARGET" <<EOF
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    },
    "clickup": {
      "command": "npx",
      "args": ["-y", "@ClickUp/mcp-server"],
      "env": {
        "CLICKUP_API_KEY": "${CLICKUP_API_KEY}",
        "CLICKUP_TEAM_ID": "${CLICKUP_TEAM_ID}"
      }
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
