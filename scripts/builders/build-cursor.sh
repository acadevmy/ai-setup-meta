#!/usr/bin/env bash
# build-cursor.sh — Builder per Cursor plugin
#
# Genera la struttura plugin Cursor in $DIST_DIR (root condivisa con Claude).
# NON crea una sottocartella dedicata: skills/, agents/, hooks/scripts/ sono
# già prodotti dal builder Claude e vengono condivisi direttamente.
#
# File aggiunti da questo builder:
#   .cursor-plugin/plugin.json   — manifest Cursor (senza userConfig)
#   mcp.json                     — MCP config (type rimosso, compatibile Cursor)
#   hooks/hooks.cursor.json      — hooks con ${cursorPluginRoot} al posto di ${CLAUDE_PLUGIN_ROOT}
#   commands/<skill>.md          — comandi generati dalle skills operative
#
# Variabili richieste dall'orchestratore:
#   ROOT_DIR, TEMPLATE_DIR, MANIFEST, DIST_DIR, NAME, DESCRIPTION, VERSION, AUTHOR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Build Cursor plugin"

# ── Prerequisiti: verifica che il builder Claude abbia già girato ─────────────
[ -d "$DIST_DIR/skills" ] || fail "skills/ non trovata in $DIST_DIR — eseguire prima build-claude.sh"
[ -d "$DIST_DIR/agents" ] || fail "agents/ non trovata in $DIST_DIR — eseguire prima build-claude.sh"

# ── Crea struttura Cursor-specific ────────────────────────────────────────────
mkdir -p "$DIST_DIR/.cursor-plugin"
mkdir -p "$DIST_DIR/commands"

ok "Struttura directory Cursor creata"

# ── Genera mcp.json (senza campo type — Claude-specific) ─────────────────────
step "Generazione mcp.json per Cursor"

if [ -f "$DIST_DIR/.mcp.json" ]; then
  jq '
    .mcpServers |= with_entries(
      if .value.type == "url" or .value.type == "http" then
        .value = { url: .value.url }
      else
        .
      end
    )
  ' "$DIST_DIR/.mcp.json" > "$DIST_DIR/mcp.json"
  ok "mcp.json generato (campo type rimosso)"
else
  warn ".mcp.json non trovato — mcp.json Cursor non generato"
fi

# ── Genera hooks.cursor.json (path variable Cursor) ───────────────────────────
step "Generazione hooks.cursor.json"

if [ -f "$DIST_DIR/hooks/hooks.json" ]; then
  sed 's|${CLAUDE_PLUGIN_ROOT}|${cursorPluginRoot}|g' \
    "$DIST_DIR/hooks/hooks.json" > "$DIST_DIR/hooks/hooks.cursor.json"
  ok "hooks.cursor.json generato (\${CLAUDE_PLUGIN_ROOT} → \${cursorPluginRoot})"
else
  warn "hooks/hooks.json non trovato — hooks.cursor.json non generato"
fi

# ── Genera commands/ dalle skills operative ───────────────────────────────────
step "Generazione commands da skills"

# Skills da escludere: setup (bootstrap), clickup e github-ops (reference skills)
SKIP_SKILLS="setup clickup github-ops"

CMD_COUNT=0
for SKILL_DIR in "$DIST_DIR/skills"/*/; do
  SKILL_FILE="$SKILL_DIR/SKILL.md"
  [ -f "$SKILL_FILE" ] || continue

  SKILL_NAME=$(basename "$SKILL_DIR")

  SKIP=false
  for S in $SKIP_SKILLS; do
    [ "$SKILL_NAME" = "$S" ] && SKIP=true && break
  done
  [ "$SKIP" = true ] && continue

  # Estrai description dal frontmatter YAML
  SKILL_DESC=$(grep '^description:' "$SKILL_FILE" | head -1 | sed 's/^description: *//; s/^"//; s/"$//')
  [ -z "$SKILL_DESC" ] && SKILL_DESC="Esegui $SKILL_NAME"

  # Estrai il contenuto senza frontmatter (tutto dopo il secondo ---)
  SKILL_CONTENT=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$SKILL_FILE")

  ESCAPED_DESC=$(echo "$SKILL_DESC" | head -1 | sed 's/"/\\"/g')

  {
    echo "---"
    echo "description: \"$ESCAPED_DESC\""
    echo "---"
    echo ""
    echo "$SKILL_CONTENT"
  } > "$DIST_DIR/commands/$SKILL_NAME.md"

  CMD_COUNT=$((CMD_COUNT + 1))
done

ok "Commands Cursor generati: $CMD_COUNT (.md in commands/)"

# ── Costruisci lista agents per plugin.json ───────────────────────────────────
AGENTS_JSON=$(find "$DIST_DIR/agents" -name "*.md" -exec basename {} \; | sort | \
  sed 's|^|"./agents/|;s|$|"|' | paste -sd',' - | sed 's/^/[/;s/$/]/')

# ── Genera .cursor-plugin/plugin.json ────────────────────────────────────────
step "Generazione .cursor-plugin/plugin.json"

# Determina path hooks: usa hooks.cursor.json se esiste, altrimenti ometti
HOOKS_PATH=""
[ -f "$DIST_DIR/hooks/hooks.cursor.json" ] && HOOKS_PATH="./hooks/hooks.cursor.json"

if [ -n "$HOOKS_PATH" ]; then
  jq -n \
    --arg name "$NAME" \
    --arg version "$VERSION" \
    --arg description "$DESCRIPTION" \
    --arg author "$AUTHOR" \
    --argjson agents "$AGENTS_JSON" \
    --arg hooksPath "$HOOKS_PATH" \
    '{
      name: $name,
      version: $version,
      description: $description,
      author: { name: $author },
      skills: "./skills",
      agents: $agents,
      mcpServers: "./mcp.json",
      hooks: $hooksPath,
      commands: "./commands"
    }' > "$DIST_DIR/.cursor-plugin/plugin.json"
else
  jq -n \
    --arg name "$NAME" \
    --arg version "$VERSION" \
    --arg description "$DESCRIPTION" \
    --arg author "$AUTHOR" \
    --argjson agents "$AGENTS_JSON" \
    '{
      name: $name,
      version: $version,
      description: $description,
      author: { name: $author },
      skills: "./skills",
      agents: $agents,
      mcpServers: "./mcp.json",
      commands: "./commands"
    }' > "$DIST_DIR/.cursor-plugin/plugin.json"
fi

ok ".cursor-plugin/plugin.json generato (userConfig escluso)"

# ── Aggiorna .cursor-plugin/marketplace.json al root repo ────────────────────
step "Aggiornamento .cursor-plugin/marketplace.json"

CURSOR_MARKETPLACE="$ROOT_DIR/.cursor-plugin/marketplace.json"
mkdir -p "$ROOT_DIR/.cursor-plugin"

if [ -f "$CURSOR_MARKETPLACE" ]; then
  EXISTING=$(jq -r --arg name "$NAME" '.plugins[] | select(.name == $name) | .name' "$CURSOR_MARKETPLACE" 2>/dev/null || echo "")
  if [ -n "$EXISTING" ]; then
    jq --arg name "$NAME" --arg ver "$VERSION" --arg desc "$DESCRIPTION" \
      '(.plugins[] | select(.name == $name)) |= (.version = $ver | .description = $desc)' \
      "$CURSOR_MARKETPLACE" > "${CURSOR_MARKETPLACE}.tmp" && mv "${CURSOR_MARKETPLACE}.tmp" "$CURSOR_MARKETPLACE"
    ok "Plugin aggiornato in .cursor-plugin/marketplace.json"
  else
    jq --arg name "$NAME" --arg ver "$VERSION" --arg desc "$DESCRIPTION" --arg src "./dist/$NAME" \
      '.plugins += [{"name": $name, "source": $src, "version": $ver, "description": $desc}]' \
      "$CURSOR_MARKETPLACE" > "${CURSOR_MARKETPLACE}.tmp" && mv "${CURSOR_MARKETPLACE}.tmp" "$CURSOR_MARKETPLACE"
    ok "Plugin aggiunto a .cursor-plugin/marketplace.json"
  fi
else
  cat > "$CURSOR_MARKETPLACE" << MKJSON
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
  ok ".cursor-plugin/marketplace.json creato"
fi
