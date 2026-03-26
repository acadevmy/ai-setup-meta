#!/usr/bin/env bash
# build-plugin.sh — Legge manifest.json e produce un plugin Claude Code self-contained in dist/
#
# Uso: bash scripts/build-plugin.sh [template-name]
#
# Prerequisiti: jq
#
# Il plugin prodotto contiene: skills, agents, hooks, MCP config, template files.
# Pronto per essere referenziato da marketplace.json.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

TEMPLATE_NAME="${1:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Prerequisiti ──────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || fail "jq non trovato. Installa con: brew install jq"

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
MANIFEST="$TEMPLATE_DIR/manifest.json"
DIST_DIR="$ROOT_DIR/dist/$TEMPLATE_NAME"

[ -d "$TEMPLATE_DIR" ] || fail "Template '$TEMPLATE_NAME' non trovato in templates/"
[ -f "$MANIFEST" ] || fail "manifest.json non trovato in $TEMPLATE_DIR/"

step "Build plugin: $TEMPLATE_NAME"

# ── Leggi manifest ────────────────────────────────────────────────────────────
NAME=$(jq -r '.name' "$MANIFEST")
DESCRIPTION=$(jq -r '.description' "$MANIFEST")
VERSION=$(grep -oP 'TEMPLATE_VERSION=\K.*' "$TEMPLATE_DIR/.env.example" 2>/dev/null || echo "1.0.0")
AUTHOR=$(jq -r '.author // "Acadevmy"' "$MANIFEST")

ok "Manifest letto: $NAME v$VERSION"

# ── Pulisci e crea struttura ──────────────────────────────────────────────────
step "Creazione struttura plugin in dist/$TEMPLATE_NAME/"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/.claude-plugin"
mkdir -p "$DIST_DIR/skills/setup/templates/profiles"
mkdir -p "$DIST_DIR/agents"
mkdir -p "$DIST_DIR/hooks/scripts"

ok "Struttura directory creata"

# ── Genera plugin.json ────────────────────────────────────────────────────────
# (generato dopo la copia degli agents per costruire l'array dinamicamente)

# ── Copia shared skills ──────────────────────────────────────────────────────
step "Copia skills condivise"

for SKILL in $(jq -r '.shared_skills[]' "$MANIFEST"); do
  SRC="$ROOT_DIR/shared/skills/$SKILL"
  DST="$DIST_DIR/skills/$SKILL"
  if [ -d "$SRC" ]; then
    mkdir -p "$DST"
    cp -r "$SRC"/* "$DST/"
    ok "Shared skill: $SKILL"
  else
    warn "Shared skill non trovata: $SKILL"
  fi
done

# ── Copia template skills ────────────────────────────────────────────────────
step "Copia skills del template"

for SKILL in $(jq -r '.template_skills[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/.claude/skills/$SKILL"
  DST="$DIST_DIR/skills/$SKILL"
  if [ -d "$SRC" ]; then
    mkdir -p "$DST"
    cp -r "$SRC"/* "$DST/"
    ok "Template skill: $SKILL"
  else
    warn "Template skill non trovata: $SKILL"
  fi
done

# ── Crea setup skill ─────────────────────────────────────────────────────────
step "Creazione setup skill"

# Copia il sorgente della setup skill
SETUP_SKILL_SRC="$TEMPLATE_DIR/setup-skill.md"
if [ -f "$SETUP_SKILL_SRC" ]; then
  cp "$SETUP_SKILL_SRC" "$DIST_DIR/skills/setup/SKILL.md"
  ok "Setup skill copiata"
else
  fail "File sorgente setup-skill.md non trovato in $TEMPLATE_DIR/"
fi

# Bundle template files per la setup skill
TEMPLATES_DST="$DIST_DIR/skills/setup/templates"

# Required files dal manifest
for FILE in $(jq -r '.required_files[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/$FILE"
  if [ -f "$SRC" ]; then
    # Preserva la struttura directory (es. .claude/settings.json → settings.json nella root templates)
    BASENAME=$(basename "$FILE")
    cp "$SRC" "$TEMPLATES_DST/$BASENAME"
    ok "Template file: $FILE"
  else
    warn "Required file non trovato: $FILE"
  fi
done

# File di governance non nel required_files
for EXTRA in "CONSTITUTION.md" "REGISTRY.md"; do
  SRC="$TEMPLATE_DIR/$EXTRA"
  if [ -f "$SRC" ] && [ ! -f "$TEMPLATES_DST/$EXTRA" ]; then
    cp "$SRC" "$TEMPLATES_DST/$EXTRA"
    ok "Extra template: $EXTRA"
  fi
done

# Profili
for PROFILE in $(jq -r '.profiles[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/profiles/$PROFILE"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$TEMPLATES_DST/profiles/$PROFILE"
    ok "Profilo: $PROFILE"
  else
    warn "Profilo non trovato: $PROFILE"
  fi
done

# Settings.json (solo permessi, senza hooks)
SETTINGS_SRC="$TEMPLATE_DIR/.claude/settings.json"
if [ -f "$SETTINGS_SRC" ]; then
  jq '{permissions: .permissions}' "$SETTINGS_SRC" > "$TEMPLATES_DST/settings.json"
  ok "Settings (solo permessi) estratto"
fi

# ── Copia agents ──────────────────────────────────────────────────────────────
step "Copia agents"

for AGENT in $(jq -r '.shared_agents[]' "$MANIFEST"); do
  SRC="$ROOT_DIR/shared/agents/$AGENT"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/agents/$AGENT"
    ok "Shared agent: $AGENT"
  else
    warn "Shared agent non trovato: $AGENT"
  fi
done

for AGENT in $(jq -r '.template_agents[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/.claude/agents/$AGENT"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/agents/$AGENT"
    ok "Template agent: $AGENT"
  else
    warn "Template agent non trovato: $AGENT"
  fi
done

# ── Genera plugin.json (dopo la copia agents per costruire l'array) ───────────
step "Generazione plugin.json"

# Costruisci array agents dai file copiati
AGENTS_JSON=$(find "$DIST_DIR/agents" -name "*.md" -exec basename {} \; | sort | \
  sed 's|^|"./agents/|;s|$|"|' | paste -sd',' - | sed 's/^/[/;s/$/]/')

cat > "$DIST_DIR/.claude-plugin/plugin.json" << PLUGINJSON
{
  "name": "$NAME",
  "version": "$VERSION",
  "description": "$DESCRIPTION",
  "author": {
    "name": "$AUTHOR"
  },
  "skills": "./skills",
  "agents": $AGENTS_JSON,
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json"
}
PLUGINJSON

ok "plugin.json generato"

# ── Copia hooks ───────────────────────────────────────────────────────────────
step "Generazione hooks"

# Copia hook scripts
HOOKS_SRC="$TEMPLATE_DIR/.claude/hooks"
if [ -d "$HOOKS_SRC" ]; then
  for SCRIPT in "$HOOKS_SRC"/*.sh; do
    [ -f "$SCRIPT" ] || continue
    cp "$SCRIPT" "$DIST_DIR/hooks/scripts/"
    chmod +x "$DIST_DIR/hooks/scripts/$(basename "$SCRIPT")"
    ok "Hook script: $(basename "$SCRIPT")"
  done
fi

# Genera hooks.json con path reindirizzati a $CLAUDE_PLUGIN_ROOT
# Legge le hooks dal settings.json e riscrive i path dei command
SETTINGS_HOOKS=$(jq '.hooks // {}' "$SETTINGS_SRC" 2>/dev/null)

if [ "$SETTINGS_HOOKS" != "{}" ] && [ -n "$SETTINGS_HOOKS" ]; then
  # Trasforma i path: $CLAUDE_PROJECT_DIR/.claude/hooks/ → ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/
  echo "$SETTINGS_HOOKS" | \
    jq 'walk(if type == "string" and test("\\$CLAUDE_PROJECT_DIR/\\.claude/hooks/") then
      gsub("\\$CLAUDE_PROJECT_DIR/\\.claude/hooks/"; "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/")
    else . end)' | \
    jq '{hooks: .}' > "$DIST_DIR/hooks/hooks.json"
  ok "hooks.json generato con path plugin"
else
  # Genera hooks.json manuale come fallback
  cat > "$DIST_DIR/hooks/hooks.json" << 'HOOKSJSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/protect-files.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/post-edit.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/on-compact.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Verifica che il lavoro richiesto dall'utente sia completo. Se ci sono test pertinenti alle modifiche fatte, sono stati eseguiti e passano? Se il lavoro non e' completo o i test falliscono, rispondi con {\"ok\": false, \"reason\": \"descrizione di cosa manca\"}. Se tutto e' a posto, rispondi con {\"ok\": true}."
          }
        ]
      }
    ]
  }
}
HOOKSJSON
  ok "hooks.json generato (fallback)"
fi

# ── Genera .mcp.json ─────────────────────────────────────────────────────────
step "Generazione .mcp.json"

cat > "$DIST_DIR/.mcp.json" << 'MCPJSON'
{
  "mcpServers": {
    "clickup": {
      "type": "url",
      "url": "https://mcp.clickup.com/mcp"
    },
    "figma": {
      "command": "npx",
      "args": ["-y", "@figma/mcp-server"],
      "env": {
        "FIGMA_ACCESS_TOKEN": "${FIGMA_ACCESS_TOKEN}"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
  }
}
MCPJSON

ok ".mcp.json generato (clickup, figma, context7)"

# ── Aggiorna marketplace.json ─────────────────────────────────────────────────
step "Aggiornamento marketplace.json"

MARKETPLACE="$ROOT_DIR/.claude-plugin/marketplace.json"
mkdir -p "$ROOT_DIR/.claude-plugin"

if [ -f "$MARKETPLACE" ]; then
  # Aggiorna la versione del plugin esistente o aggiungilo
  EXISTING=$(jq -r --arg name "$NAME" '.plugins[] | select(.name == $name) | .name' "$MARKETPLACE" 2>/dev/null || echo "")
  if [ -n "$EXISTING" ]; then
    jq --arg name "$NAME" --arg ver "$VERSION" --arg desc "$DESCRIPTION" \
      '(.plugins[] | select(.name == $name)) |= (.version = $ver | .description = $desc)' \
      "$MARKETPLACE" > "${MARKETPLACE}.tmp" && mv "${MARKETPLACE}.tmp" "$MARKETPLACE"
    ok "Plugin aggiornato in marketplace.json"
  else
    jq --arg name "$NAME" --arg ver "$VERSION" --arg desc "$DESCRIPTION" --arg src "./dist/$NAME" \
      '.plugins += [{"name": $name, "source": $src, "version": $ver, "description": $desc}]' \
      "$MARKETPLACE" > "${MARKETPLACE}.tmp" && mv "${MARKETPLACE}.tmp" "$MARKETPLACE"
    ok "Plugin aggiunto a marketplace.json"
  fi
else
  cat > "$MARKETPLACE" << MKJSON
{
  "name": "acadevmy",
  "owner": {
    "name": "Acadevmy"
  },
  "metadata": {
    "description": "Plugin AI-native per workflow di sviluppo"
  },
  "plugins": [
    {
      "name": "$NAME",
      "source": "./dist/$NAME",
      "version": "$VERSION",
      "description": "$DESCRIPTION"
    }
  ]
}
MKJSON
  ok "marketplace.json creato"
fi

# ── Riepilogo ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Plugin $NAME v$VERSION built                      ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Output: dist/$TEMPLATE_NAME/"
echo ""

# Conta i componenti
SKILL_COUNT=$(find "$DIST_DIR/skills" -name "SKILL.md" | wc -l | tr -d ' ')
AGENT_COUNT=$(find "$DIST_DIR/agents" -name "*.md" | wc -l | tr -d ' ')
HOOK_COUNT=$(find "$DIST_DIR/hooks/scripts" -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')

echo "  Skills: $SKILL_COUNT"
echo "  Agents: $AGENT_COUNT"
echo "  Hooks:  $HOOK_COUNT"
echo ""
echo "  Validazione: claude plugin validate dist/$TEMPLATE_NAME/"
echo "  Test locale:  claude --plugin-dir dist/$TEMPLATE_NAME/"
echo ""
