#!/usr/bin/env bash
# build-claude.sh — Builder per Claude Code plugin
#
# Genera la struttura plugin Claude Code in $DIST_DIR.
# Variabili richieste dall'orchestratore:
#   ROOT_DIR, TEMPLATE_DIR, MANIFEST, DIST_DIR, NAME, DESCRIPTION, VERSION, AUTHOR
#
# Importa common.sh per le funzioni condivise.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Build Claude Code plugin"

# ── Crea struttura ───────────────────────────────────────────────────────────
mkdir -p "$DIST_DIR/.claude-plugin"
mkdir -p "$DIST_DIR/skills/setup/templates/profiles"
mkdir -p "$DIST_DIR/agents"
mkdir -p "$DIST_DIR/hooks/scripts"

ok "Struttura directory creata"

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

SETUP_SKILL_SRC="$TEMPLATE_DIR/setup-skill.md"
if [ -f "$SETUP_SKILL_SRC" ]; then
  cp "$SETUP_SKILL_SRC" "$DIST_DIR/skills/setup/SKILL.md"
  ok "Setup skill copiata"
else
  fail "File sorgente setup-skill.md non trovato in $TEMPLATE_DIR/"
fi

# Bundle template files per la setup skill
TEMPLATES_DST="$DIST_DIR/skills/setup/templates"

for FILE in $(jq -r '.required_files[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/$FILE"
  if [ -f "$SRC" ]; then
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

# Boilerplate files (greenfield config, scaricati verbatim a runtime dal setup-agent)
mkdir -p "$TEMPLATES_DST/boilerplate"
for BP in $(jq -r '.boilerplate_files[] // empty' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/boilerplate/$BP"
  DST="$TEMPLATES_DST/boilerplate/$BP"
  if [ -f "$SRC" ]; then
    mkdir -p "$(dirname "$DST")"
    cp "$SRC" "$DST"
    ok "Boilerplate: $BP"
  else
    warn "Boilerplate non trovato: $BP"
  fi
done

# Settings.json (permessi + sandbox, senza hooks: gli hook li monta il plugin)
SETTINGS_SRC="$TEMPLATE_DIR/.claude/settings.json"
if [ -f "$SETTINGS_SRC" ]; then
  jq '{permissions: .permissions, sandbox: .sandbox}' "$SETTINGS_SRC" > "$TEMPLATES_DST/settings.json"
  ok "Settings (permessi + sandbox) estratto"
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

# ── Genera plugin.json ───────────────────────────────────────────────────────
step "Generazione plugin.json"

# Il plugin dichiara server MCP solo se il template ne fornisce una .mcp.json.
# I server che dipendono dallo stack (figma) o dalla configurazione del team
# (clickup) li registra la setup skill a livello progetto/utente: vedi Passo 6.
MCP_SRC="$TEMPLATE_DIR/.mcp.json"
if [ -f "$MCP_SRC" ]; then
  MCP_REF='"./.mcp.json"'
else
  MCP_REF='null'
fi

AGENTS_JSON=$(find "$DIST_DIR/agents" -name "*.md" -exec basename {} \; | sort | \
  sed 's|^|"./agents/|;s|$|"|' | paste -sd',' - | sed 's/^/[/;s/$/]/')

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

jq -n \
  --arg name "$NAME" \
  --arg version "$VERSION" \
  --arg description "$DESCRIPTION" \
  --arg author "$AUTHOR" \
  --argjson agents "$AGENTS_JSON" \
  --argjson userConfig "$USER_CONFIG" \
  --argjson mcpRef "$MCP_REF" \
  '{
    name: $name,
    version: $version,
    description: $description,
    author: { name: $author },
    skills: "./skills",
    agents: $agents,
    mcpServers: $mcpRef,
    userConfig: $userConfig
  }
  | if .mcpServers == null then del(.mcpServers) else . end' > "$DIST_DIR/.claude-plugin/plugin.json"

ok "plugin.json generato"

# ── Copia hooks ──────────────────────────────────────────────────────────────
step "Generazione hooks"

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

SETTINGS_HOOKS=$(jq '.hooks // {}' "$SETTINGS_SRC" 2>/dev/null)

if [ "$SETTINGS_HOOKS" != "{}" ] && [ -n "$SETTINGS_HOOKS" ]; then
  echo "$SETTINGS_HOOKS" | \
    jq 'walk(if type == "string" and test("\\$CLAUDE_PROJECT_DIR/\\.claude/hooks/") then
      gsub("\\$CLAUDE_PROJECT_DIR/\\.claude/hooks/"; "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/")
    else . end)' | \
    jq '{hooks: .}' > "$DIST_DIR/hooks/hooks.json"
  ok "hooks.json generato con path plugin"
elif [ "$HAS_HOOKS" = true ]; then
  cat > "$DIST_DIR/hooks/hooks.json" << 'HOOKSJSON'
{
  "hooks": {
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
    ]
  }
}
HOOKSJSON
  ok "hooks.json generato (fallback)"
else
  echo '{"hooks": {}}' > "$DIST_DIR/hooks/hooks.json"
  ok "hooks.json generato (vuoto — template senza hooks)"
fi

# ── Copia .mcp.json ──────────────────────────────────────────────────────────
step "Server MCP del plugin"

if [ -f "$MCP_SRC" ]; then
  cp "$MCP_SRC" "$DIST_DIR/.mcp.json"
  ok ".mcp.json copiato dal template ($(jq -r '.mcpServers | keys | join(", ")' "$MCP_SRC"))"
else
  ok "nessun server MCP nel plugin — li registra la setup skill per progetto"
fi

# ── Aggiorna marketplace.json ────────────────────────────────────────────────
step "Aggiornamento marketplace.json"

MARKETPLACE="$ROOT_DIR/.claude-plugin/marketplace.json"
mkdir -p "$ROOT_DIR/.claude-plugin"

if [ -f "$MARKETPLACE" ]; then
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
