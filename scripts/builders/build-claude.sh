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
mkdir -p "$DIST_DIR/skills/setup/templates/rules"
mkdir -p "$DIST_DIR/skills/setup/reference"
mkdir -p "$DIST_DIR/reference"
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

# ── Copy the plugin-level shared references ──────────────────────────────────
#
# The contracts more than one skill needs (DE-16478): defined once here, cited by
# name from the skills as ${CLAUDE_PLUGIN_ROOT}/reference/<name>.md. They are not
# a skill: nothing routes to them, the skills that need them say so.
step "Copying the shared references"

REFERENCE_SRC="$TEMPLATE_DIR/.claude/reference"

for REF in $(jq -r '.plugin_reference[]? // empty' "$MANIFEST"); do
  SRC="$REFERENCE_SRC/$REF"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/reference/$REF"
    ok "Shared reference: $REF"
  else
    warn "Shared reference not found: $REF"
  fi
done

# ── Build the setup skill ────────────────────────────────────────────────────
step "Building the setup skill"

SETUP_SKILL_REL=$(jq -r '.setup_skill // "setup/SKILL.md"' "$MANIFEST")
SETUP_SKILL_SRC="$TEMPLATE_DIR/$SETUP_SKILL_REL"
if [ -f "$SETUP_SKILL_SRC" ]; then
  cp "$SETUP_SKILL_SRC" "$DIST_DIR/skills/setup/SKILL.md"
  ok "Setup skill copied"
else
  fail "Source file $SETUP_SKILL_REL not found in $TEMPLATE_DIR/"
fi

# The setup skill's own reference files: progressive disclosure (DE-16478). They
# sit next to SKILL.md so the model reaches them by name, one hop, on demand.
SETUP_REFERENCE_SRC="$(dirname "$SETUP_SKILL_SRC")/reference"
for REF in $(jq -r '.setup_reference[]? // empty' "$MANIFEST"); do
  SRC="$SETUP_REFERENCE_SRC/$REF"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$DIST_DIR/skills/setup/reference/$REF"
    ok "Setup reference: $REF"
  else
    warn "Setup reference not found: $REF"
  fi
done

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

# REGISTRY.md ships even when the manifest forgets to list it: the setup writes
# one into every project, so a build without it produces a skill that cannot run.
REGISTRY_SRC="$TEMPLATE_DIR/REGISTRY.md"
if [ -f "$REGISTRY_SRC" ] && [ ! -f "$TEMPLATES_DST/REGISTRY.md" ]; then
  cp "$REGISTRY_SRC" "$TEMPLATES_DST/REGISTRY.md"
  ok "Extra template: REGISTRY.md"
fi

# Path-scoped rule templates (DE-16477). The setup skill renders these into the
# project's .claude/rules/dev-setup-*.md — they replace the CONSTITUTION.md the
# setup used to copy whole into every project.
for RULE in $(jq -r '.rules[]? // empty' "$MANIFEST"); do
  SRC="$TEMPLATE_DIR/rules/$RULE"
  if [ -f "$SRC" ]; then
    cp "$SRC" "$TEMPLATES_DST/rules/$RULE"
    ok "Rule: $RULE"
  else
    warn "Rule not found: $RULE"
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
