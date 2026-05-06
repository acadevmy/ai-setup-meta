#!/usr/bin/env bash
# install-pm-gemini.sh — Installa il PM Setup per Gemini CLI (globale, in ~)
#
# Uso:
#   bash install-pm-gemini.sh
#   curl -sL <url>/install.sh | bash
#
# Prerequisiti: Gemini CLI, Node.js 18+

set -euo pipefail

# ── Flag ──────────────────────────────────────────────────────────────────────
# --local-dist <path>  Copia i file da una dist/ locale invece di scaricarli
#                      Utile per testare prima di pubblicare su GitHub
LOCAL_DIST=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-dist) LOCAL_DIST="${2:-}"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# ── Colori e output ───────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}▶ $1${NC}"; }
info() { echo    "  $1"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         PM Setup — Installazione Gemini CLI             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Prerequisiti ──────────────────────────────────────────────────────────────
step "Verifica prerequisiti"

command -v curl >/dev/null 2>&1 || fail "curl non trovato. Installalo prima di procedere."
command -v gemini >/dev/null 2>&1 || fail "Gemini CLI non trovato. Installalo da: https://github.com/google-gemini/gemini-cli"
command -v node >/dev/null 2>&1 || fail "Node.js non trovato. Installalo da: https://nodejs.org/ (versione 18 o superiore)"

NODE_VER=$(node -e "process.stdout.write(process.version.replace('v','').split('.')[0])")
[ "$NODE_VER" -ge 18 ] 2>/dev/null || fail "Node.js $NODE_VER trovato, ma serve la versione 18 o superiore. Aggiornalo da: https://nodejs.org/"

ok "curl disponibile"
ok "Gemini CLI disponibile"
ok "Node.js $NODE_VER disponibile"

# ── Opzioni interattive ───────────────────────────────────────────────────────
step "Configurazione"

echo ""
read -r -p "  Vuoi aggiungere il supporto a Figma? [y/N] " RESP_FIGMA
WITH_FIGMA=false
[[ "$RESP_FIGMA" =~ ^[Yy]$ ]] && WITH_FIGMA=true

read -r -p "  Vuoi installare l'estensione Google Workspace (per le trascrizioni)? [Y/n] " RESP_GW
WITH_GOOGLE=true
[[ "$RESP_GW" =~ ^[Nn]$ ]] && WITH_GOOGLE=false

echo ""

# ── Percorsi ──────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME"
GEMINI_DIR="$INSTALL_DIR/.gemini"
CMDS_DIR="$GEMINI_DIR/commands/pm"
SETTINGS_FILE="$GEMINI_DIR/settings.json"
BASE_URL="https://raw.githubusercontent.com/acadevmy/ai-setup-meta/main/dist/pm-setup/gemini"

step "Installazione in $INSTALL_DIR"

mkdir -p "$CMDS_DIR"
ok "Directory creata: $CMDS_DIR"

COMMANDS=(pm-flow pm-intake pm-transcript pm-figma pm-structure pm-refine pm-review pm-publish)

if [ -n "$LOCAL_DIST" ]; then
  # ── Copia da dist/ locale (modalita' sviluppo) ────────────────────────────
  step "Copia file da dist/ locale: $LOCAL_DIST"

  [ -d "$LOCAL_DIST" ] || fail "Directory locale non trovata: $LOCAL_DIST"

  cp "$LOCAL_DIST/GEMINI.md"          "$GEMINI_DIR/GEMINI.md"          && ok "GEMINI.md"          || fail "Copia GEMINI.md fallita"
  cp "$LOCAL_DIST/PM-CONSTITUTION.md" "$INSTALL_DIR/PM-CONSTITUTION.md" && ok "PM-CONSTITUTION.md" || fail "Copia PM-CONSTITUTION.md fallita"

  step "Copia comandi slash"
  for cmd in "${COMMANDS[@]}"; do
    cp "$LOCAL_DIST/commands/pm/$cmd.toml" "$CMDS_DIR/$cmd.toml" && ok "$cmd.toml" || warn "$cmd.toml — copia fallita"
  done

else
  # ── Download da GitHub ────────────────────────────────────────────────────
  step "Download file di configurazione"

  curl -sfL "$BASE_URL/GEMINI.md"          -o "$GEMINI_DIR/GEMINI.md"          && ok "GEMINI.md"          || fail "Download GEMINI.md fallito — controlla la connessione a internet"
  curl -sfL "$BASE_URL/PM-CONSTITUTION.md" -o "$INSTALL_DIR/PM-CONSTITUTION.md" && ok "PM-CONSTITUTION.md" || fail "Download PM-CONSTITUTION.md fallito"

  step "Download comandi slash"
  FAILED=()
  for cmd in "${COMMANDS[@]}"; do
    if curl -sfL "$BASE_URL/commands/pm/$cmd.toml" -o "$CMDS_DIR/$cmd.toml"; then
      ok "$cmd.toml"
    else
      warn "$cmd.toml — download fallito"
      FAILED+=("$cmd")
    fi
  done

  if [ ${#FAILED[@]} -gt 0 ]; then
    warn "Alcuni comandi non sono stati scaricati. Riprova l'installazione."
  fi
fi

# ── Configurazione MCP (settings.json) ───────────────────────────────────────
step "Configurazione server MCP"

node - "$SETTINGS_FILE" "$WITH_FIGMA" <<'NODE'
const fs   = require('fs');
const file = process.argv[2];
const withFigma = process.argv[3] === 'true';

const settings = fs.existsSync(file)
  ? JSON.parse(fs.readFileSync(file, 'utf8'))
  : {};

if (!settings.mcpServers) settings.mcpServers = {};

settings.mcpServers.clickup = {
  trust: true,
  command: 'npx',
  args: ['-y', 'mcp-remote', 'https://mcp.clickup.com/mcp']
};

if (withFigma) {
  settings.mcpServers.figma = {
    trust: true,
    command: 'npx',
    args: ['-y', 'mcp-remote', 'https://mcp.figma.com/mcp']
  };
}

fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
NODE

ok "settings.json configurato (ClickUp MCP)"
[ "$WITH_FIGMA" = true ] && ok "Figma MCP aggiunto"

# ── Estensione Google Workspace ───────────────────────────────────────────────
if [ "$WITH_GOOGLE" = true ]; then
  step "Installazione estensione Google Workspace"
  if gemini extensions install https://github.com/gemini-cli-extensions/workspace; then
    ok "Estensione Google Workspace installata"
    info "Al primo utilizzo il browser si aprira' per autorizzare l'accesso al tuo account Google"
  else
    warn "Installazione estensione Google Workspace non riuscita"
    info "Puoi installarla manualmente in seguito con:"
    info "  gemini extensions install https://github.com/gemini-cli-extensions/workspace"
  fi
fi

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Installazione completata!                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
info "Avvia Gemini CLI con il comando: gemini"
echo ""
info "Comandi disponibili:"
info "  /pm:pm-flow        Flusso completo documento → task ClickUp"
info "  /pm:pm-intake      Analisi documento → Discovery Brief"
info "  /pm:pm-transcript  Analisi trascrizioni Google Meet"
info "  /pm:pm-figma       Analisi design Figma → task"
info "  /pm:pm-structure   Brief → gerarchia Epic/Story/Task"
info "  /pm:pm-refine      Validazione INVEST + criteri accettazione"
info "  /pm:pm-review      Revisione e approvazione"
info "  /pm:pm-publish     Pubblicazione su ClickUp"
echo ""
info "Al primo utilizzo, ClickUp ti chiedera' di autorizzare l'accesso al workspace."
echo ""
info "Per aggiornare il setup in futuro:"
info "  curl -sL $BASE_URL/install.sh | bash"
echo ""
