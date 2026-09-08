#!/usr/bin/env bash
# build-claude.sh — Claude Code plugin builder
#
# Generates the Claude Code plugin layout under $DIST_DIR.
# Variables the orchestrator has to provide:
#   ROOT_DIR, TEMPLATE_DIR, MANIFEST, DIST_DIR, NAME, DESCRIPTION, VERSION, AUTHOR
#
# Sources common.sh for the shared helpers.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Build Claude Code plugin"

# ── Create the layout ────────────────────────────────────────────────────────
mkdir -p "$DIST_DIR/.claude-plugin"
mkdir -p "$DIST_DIR/skills/setup/templates/profiles"
mkdir -p "$DIST_DIR/agents"
mkdir -p "$DIST_DIR/hooks/scripts"
mkdir -p "$DIST_DIR/scripts"

ok "Directory layout created"

# ── Copy the shared skills ───────────────────────────────────────────────────
step "Copying the shared skills"

for SKILL in $(jq -r '.shared_skills[]' "$MANIFEST"); do
  SRC="$ROOT_DIR/shared/skills/$SKILL"
  DST="$DIST_DIR/skills/$SKILL"
  if [ -d "$SRC" ]; then
    mkdir -p "$DST"
    cp -r "$SRC"/* "$DST/"
    ok "Shared skill: $SKILL"
  else
    warn "Shared skill not found: $SKILL"
  fi
done

# ── Copy the template skills ─────────────────────────────────────────────────
step "Copying the template skills"

for SKILL in $(jq -r '.template_skills[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/.claude/skills/$SKILL"
  DST="$DIST_DIR/skills/$SKILL"
  if [ -d "$SRC" ]; then
    mkdir -p "$DST"
    cp -r "$SRC"/* "$DST/"
    ok "Template skill: $SKILL"
  else
    warn "Template skill not found: $SKILL"
  fi
done

# ── Build the setup skill ────────────────────────────────────────────────────
step "Building the setup skill"

SETUP_SKILL_SRC="$TEMPLATE_DIR/setup-skill.md"
if [ -f "$SETUP_SKILL_SRC" ]; then
  cp "$SETUP_SKILL_SRC" "$DIST_DIR/skills/setup/SKILL.md"
  ok "Setup skill copied"
else
  fail "Source file setup-skill.md not found in $TEMPLATE_DIR/"
fi

# Bundle the template files the setup skill needs
TEMPLATES_DST="$DIST_DIR/skills/setup/templates"

for FILE in $(jq -r '.required_files[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/$FILE"
  if [ -f "$SRC" ]; then
    BASENAME=$(basename "$FILE")
    cp "$SRC" "$TEMPLATES_DST/$BASENAME"
    ok "Template file: $FILE"
  else
    warn "Required file not found: $FILE"
  fi
done

# Governance files that are not in required_files
for EXTRA in "CONSTITUTION.md" "REGISTRY.md"; do
  SRC="$TEMPLATE_DIR/$EXTRA"
  if [ -f "$SRC" ] && [ ! -f "$TEMPLATES_DST/$EXTRA" ]; then
    cp "$SRC" "$TEMPLATES_DST/$EXTRA"
    ok "Extra template: $EXTRA"
  fi
done

# Profiles
for PROFILE in $(jq -r '.profiles[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/profiles/$PROFILE"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$TEMPLATES_DST/profiles/$PROFILE"
    ok "Profile: $PROFILE"
  else
    warn "Profile not found: $PROFILE"
  fi
done

# Boilerplate files (greenfield config, read verbatim at runtime by the setup skill)
mkdir -p "$TEMPLATES_DST/boilerplate"
for BP in $(jq -r '.boilerplate_files[] // empty' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/boilerplate/$BP"
  DST="$TEMPLATES_DST/boilerplate/$BP"
  if [ -f "$SRC" ]; then
    mkdir -p "$(dirname "$DST")"
    cp "$SRC" "$DST"
    ok "Boilerplate: $BP"
  else
    warn "Boilerplate not found: $BP"
  fi
done

# Settings.json (permissions + sandbox, no hooks: the plugin mounts those itself)
SETTINGS_SRC="$TEMPLATE_DIR/.claude/settings.json"
if [ -f "$SETTINGS_SRC" ]; then
  jq '{permissions: .permissions, sandbox: .sandbox}' "$SETTINGS_SRC" > "$TEMPLATES_DST/settings.json"
  ok "Settings (permissions + sandbox) extracted"
fi

# ── Copy the agents ───────────────────────────────────────────────────────────
step "Copying the agents"

for AGENT in $(jq -r '.shared_agents[]' "$MANIFEST"); do
  SRC="$ROOT_DIR/shared/agents/$AGENT"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/agents/$AGENT"
    ok "Shared agent: $AGENT"
  else
    warn "Shared agent not found: $AGENT"
  fi
done

for AGENT in $(jq -r '.template_agents[]' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/.claude/agents/$AGENT"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/agents/$AGENT"
    ok "Template agent: $AGENT"
  else
    warn "Template agent not found: $AGENT"
  fi
done

# ── Generate plugin.json ─────────────────────────────────────────────────────
step "Generating plugin.json"

# The plugin declares MCP servers only if the template ships a .mcp.json.
# The servers that depend on the stack (figma) or on the team's configuration
# (clickup) are registered by the setup skill at project/user scope: see Step 6.
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
      "description": "ClickUp list id for the sprint tasks (find it in the URL: app.clickup.com/.../li/<ID>)",
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

ok "plugin.json generated"

# ── Copy the plugin scripts ──────────────────────────────────────────────────
#
# The deterministic work the agent used to re-derive from prose on every run
# (DE-16476): detect-stack, sdd-start, check-prerequisites, render-template.
# They land at $DIST_DIR/scripts/, which is what ${CLAUDE_PLUGIN_ROOT}/scripts
# resolves to at runtime.
step "Copying the plugin scripts"

SCRIPTS_SRC="$TEMPLATE_DIR/.claude/scripts"

for SCRIPT in $(jq -r '.plugin_scripts[]? // empty' "$MANIFEST"); do
  SRC="$SCRIPTS_SRC/$SCRIPT"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/scripts/$SCRIPT"
    chmod +x "$DIST_DIR/scripts/$SCRIPT"
    ok "Script: $SCRIPT"
  else
    warn "Script not found: $SCRIPT"
  fi
done

# ── Copy the hooks ───────────────────────────────────────────────────────────
step "Generating the hooks"

HOOKS_SRC="$TEMPLATE_DIR/.claude/hooks"
HAS_HOOKS=false

# The manifest is authoritative when it lists the hooks; otherwise every *.sh
# in the hooks directory ships.
MANIFEST_HOOKS=$(jq -r '.hooks[]? // empty' "$MANIFEST")

if [ -n "$MANIFEST_HOOKS" ]; then
  for HOOK in $MANIFEST_HOOKS; do
    SRC="$HOOKS_SRC/$HOOK"
    if [ -f "$SRC" ]; then
      cp "$SRC" "$DIST_DIR/hooks/scripts/$HOOK"
      chmod +x "$DIST_DIR/hooks/scripts/$HOOK"
      ok "Hook script: $HOOK"
      HAS_HOOKS=true
    else
      warn "Hook not found: $HOOK"
    fi
  done
elif [ -d "$HOOKS_SRC" ]; then
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
  ok "hooks.json generated with plugin paths"
elif [ "$HAS_HOOKS" = true ]; then
  cat > "$DIST_DIR/hooks/hooks.json" << 'HOOKSJSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/scripts/gate-commit.sh",
            "timeout": 600
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
    ]
  }
}
HOOKSJSON
  ok "hooks.json generated (fallback)"
else
  echo '{"hooks": {}}' > "$DIST_DIR/hooks/hooks.json"
  ok "hooks.json generated (empty — the template has no hooks)"
fi

# ── Copy .mcp.json ───────────────────────────────────────────────────────────
step "The plugin's MCP servers"

if [ -f "$MCP_SRC" ]; then
  cp "$MCP_SRC" "$DIST_DIR/.mcp.json"
  ok ".mcp.json copied from the template ($(jq -r '.mcpServers | keys | join(", ")' "$MCP_SRC"))"
else
  ok "no MCP server in the plugin — the setup skill registers them per project"
fi

# ── Update marketplace.json ──────────────────────────────────────────────────
step "Updating marketplace.json"

MARKETPLACE="$ROOT_DIR/.claude-plugin/marketplace.json"
mkdir -p "$ROOT_DIR/.claude-plugin"

if [ -f "$MARKETPLACE" ]; then
  EXISTING=$(jq -r --arg name "$NAME" '.plugins[] | select(.name == $name) | .name' "$MARKETPLACE" 2>/dev/null || echo "")
  if [ -n "$EXISTING" ]; then
    jq --arg name "$NAME" --arg ver "$VERSION" --arg desc "$DESCRIPTION" \
      '(.plugins[] | select(.name == $name)) |= (.version = $ver | .description = $desc)' \
      "$MARKETPLACE" > "${MARKETPLACE}.tmp" && mv "${MARKETPLACE}.tmp" "$MARKETPLACE"
    ok "Plugin updated in marketplace.json"
  else
    jq --arg name "$NAME" --arg ver "$VERSION" --arg desc "$DESCRIPTION" --arg src "./dist/$NAME" \
      '.plugins += [{"name": $name, "source": $src, "version": $ver, "description": $desc}]' \
      "$MARKETPLACE" > "${MARKETPLACE}.tmp" && mv "${MARKETPLACE}.tmp" "$MARKETPLACE"
    ok "Plugin added to marketplace.json"
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
  ok "marketplace.json created"
fi
