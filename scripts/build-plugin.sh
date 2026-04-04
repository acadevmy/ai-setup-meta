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
VERSION=$(sed -n 's/^TEMPLATE_VERSION=//p' "$TEMPLATE_DIR/.env.example" 2>/dev/null || echo "1.0.0")
[ -z "$VERSION" ] && VERSION="1.0.0"
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

# Genera userConfig in base al template
if [ "$NAME" = "dev-setup" ]; then
  USER_CONFIG='{
    "CLICKUP_SETUP_LIST_ID": {
      "title": "ClickUp Sprint List ID",
      "description": "ID della lista ClickUp per i task di sprint (trovalo nell'\''URL: app.clickup.com/.../li/<ID>)",
      "type": "string",
      "sensitive": false,
      "required": false
    }
  }'
else
  USER_CONFIG='{}'
fi

# Costruisci plugin.json
jq -n \
  --arg name "$NAME" \
  --arg version "$VERSION" \
  --arg description "$DESCRIPTION" \
  --arg author "$AUTHOR" \
  --argjson agents "$AGENTS_JSON" \
  --argjson userConfig "$USER_CONFIG" \
  '{
    name: $name,
    version: $version,
    description: $description,
    author: { name: $author },
    skills: "./skills",
    agents: $agents,
    mcpServers: "./.mcp.json",
    userConfig: $userConfig
  }' > "$DIST_DIR/.claude-plugin/plugin.json"

ok "plugin.json generato"

# ── Copia hooks ───────────────────────────────────────────────────────────────
step "Generazione hooks"

# Copia hook scripts (se esistono)
HOOKS_SRC="$TEMPLATE_DIR/.claude/hooks"
HAS_HOOKS=false

if [ -d "$HOOKS_SRC" ]; then
  for SCRIPT in "$HOOKS_SRC"/*.sh; do
    [ -f "$SCRIPT" ] || continue
    cp "$SCRIPT" "$DIST_DIR/hooks/scripts/"
    chmod +x "$DIST_DIR/hooks/scripts/$(basename "$SCRIPT")"
    ok "Hook script: $(basename "$SCRIPT")"
    HAS_HOOKS=true
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
elif [ "$HAS_HOOKS" = true ]; then
  # Hook scripts presenti ma nessuna config in settings.json — genera fallback
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
else
  # Nessun hook — template senza hooks (es. pm-setup)
  echo '{"hooks": {}}' > "$DIST_DIR/hooks/hooks.json"
  ok "hooks.json generato (vuoto — template senza hooks)"
fi

# ── Genera .mcp.json ─────────────────────────────────────────────────────────
step "Generazione .mcp.json"

# Genera .mcp.json in base al template
if [ "$NAME" = "dev-setup" ]; then
  cat > "$DIST_DIR/.mcp.json" << 'MCPJSON'
{
  "mcpServers": {
    "clickup": {
      "type": "url",
      "url": "https://mcp.clickup.com/mcp"
    },
    "figma": {
      "type": "http",
      "url": "https://mcp.figma.com/mcp"
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    }
  }
}
MCPJSON
  ok ".mcp.json generato (clickup, figma, context7)"
else
  cat > "$DIST_DIR/.mcp.json" << 'MCPJSON'
{
  "mcpServers": {
    "clickup": {
      "type": "url",
      "url": "https://mcp.clickup.com/mcp"
    },
    "figma": {
      "type": "http",
      "url": "https://mcp.figma.com/mcp"
    }
  }
}
MCPJSON
  ok ".mcp.json generato (clickup, figma)"
fi

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

# ── Genera output Gemini (se gemini_support nel manifest) ────────────────────
GEMINI_SUPPORT=$(jq -r '.gemini_support // false' "$MANIFEST")

if [ "$GEMINI_SUPPORT" = "true" ]; then
  step "Generazione output Gemini CLI"

  GEMINI_DIR="$DIST_DIR/gemini"
  mkdir -p "$GEMINI_DIR"

  # Genera GEMINI.md combinando AGENTS.template + skill instructions
  {
    # Header
    echo "# Gemini System Instructions — $DESCRIPTION"
    echo ""
    echo "> Generato automaticamente da ai-base-setup. Non modificare direttamente."
    echo ""

    # Includi AGENTS.template.md se presente nei templates bundled
    AGENTS_TPL="$DIST_DIR/skills/setup/templates/AGENTS.template.md"
    if [ -f "$AGENTS_TPL" ]; then
      echo "---"
      echo ""
      cat "$AGENTS_TPL"
      echo ""
    fi

    # Includi ogni skill come sezione
    echo "---"
    echo ""
    echo "# Skill disponibili"
    echo ""

    for SKILL_DIR in "$DIST_DIR/skills"/*/; do
      SKILL_FILE="$SKILL_DIR/SKILL.md"
      [ -f "$SKILL_FILE" ] || continue

      SKILL_NAME=$(basename "$SKILL_DIR")
      # Salta la setup skill (non serve in Gemini, e' per il bootstrap)
      [ "$SKILL_NAME" = "setup" ] && continue

      echo "---"
      echo ""
      # Rimuovi il frontmatter YAML (tra i due ---) e scrivi il contenuto
      sed -n '/^---$/,/^---$/!p' "$SKILL_FILE"
      echo ""
    done
  } > "$GEMINI_DIR/GEMINI.md"

  ok "GEMINI.md generato con $(find "$DIST_DIR/skills" -name "SKILL.md" ! -path "*/setup/*" | wc -l | tr -d ' ') skill inline"

  # Copia la governance (PM-CONSTITUTION o CONSTITUTION)
  for GOV_FILE in "PM-CONSTITUTION.md" "CONSTITUTION.md"; do
    GOV_SRC="$DIST_DIR/skills/setup/templates/$GOV_FILE"
    if [ -f "$GOV_SRC" ]; then
      cp "$GOV_SRC" "$GEMINI_DIR/$GOV_FILE"
      ok "Governance: $GOV_FILE copiata per Gemini"
      break
    fi
  done

  # Genera settings.json Gemini-compatibile (solo MCP)
  if [ -f "$DIST_DIR/.mcp.json" ]; then
    cp "$DIST_DIR/.mcp.json" "$GEMINI_DIR/.mcp.json"
    ok "MCP config copiata per Gemini"
  fi
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

if [ "$GEMINI_SUPPORT" = "true" ]; then
  echo "  Gemini: GEMINI.md generato"
fi

echo ""
echo "  Validazione: claude plugin validate dist/$TEMPLATE_NAME/"
echo "  Test locale:  claude --plugin-dir dist/$TEMPLATE_NAME/"
echo ""
