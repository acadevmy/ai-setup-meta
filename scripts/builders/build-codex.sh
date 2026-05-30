#!/usr/bin/env bash
# build-codex.sh — Builder per OpenAI Codex CLI
#
# Genera la variante Codex in $DIST_DIR/codex/.
# Richiede che il build Claude sia gia' stato eseguito (legge da $DIST_DIR/).
# Variabili richieste dall'orchestratore:
#   ROOT_DIR, TEMPLATE_DIR, MANIFEST, DIST_DIR, NAME, DESCRIPTION, VERSION, AUTHOR
#
# Ref: https://developers.openai.com/codex/plugins/build

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Generazione output OpenAI Codex CLI"

CODEX_DIR="$DIST_DIR/codex"
mkdir -p "$CODEX_DIR/.codex-plugin"
mkdir -p "$CODEX_DIR/skills"

# ── AGENTS.md — istruzioni di sistema + PM-CONSTITUTION inline ───────────────
{
  echo "# Codex System Instructions — $DESCRIPTION"
  echo ""
  echo "> Generato automaticamente da ai-base-setup. Non modificare direttamente."
  echo ""

  AGENTS_TPL="$DIST_DIR/skills/setup/templates/AGENTS.template.md"
  if [ -f "$AGENTS_TPL" ]; then
    echo "---"
    echo ""
    # Adatta i comandi da /pm-setup:pm-* a nomi skill diretti
    sed 's|`/pm-setup:pm-|`pm-|g; s|/pm-setup:pm-|pm-|g' "$AGENTS_TPL"
    echo ""
  fi

  # Inline PM-CONSTITUTION so Codex skills always have it in context
  PM_CONST="$DIST_DIR/skills/setup/templates/PM-CONSTITUTION.md"
  if [ -f "$PM_CONST" ]; then
    echo "---"
    echo ""
    echo "<!-- PM-CONSTITUTION (bundled inline) -->"
    cat "$PM_CONST"
    echo ""
  fi
} > "$CODEX_DIR/AGENTS.md"

ok "AGENTS.md generato per Codex (con PM-CONSTITUTION inline)"

# ── Governance ───────────────────────────────────────────────────────────────
copy_governance "$CODEX_DIR" "Codex"

# ── Skills (Codex usa SKILL.md — sanitizza frontmatter Claude Code) ──────────
# Codex accetta solo name, description e metadata nel frontmatter.
# Rimuovi campi specifici di Claude Code: model, user-invocable, disable-model-invocation
CODEX_SKILL_COUNT=0
for SKILL_DIR in "$DIST_DIR/skills"/*/; do
  SKILL_FILE="$SKILL_DIR/SKILL.md"
  [ -f "$SKILL_FILE" ] || continue

  SKILL_NAME=$(basename "$SKILL_DIR")

  # Salta setup (specifico di Claude Code)
  [ "$SKILL_NAME" = "setup" ] && continue

  SKILL_DST="$CODEX_DIR/skills/$SKILL_NAME"
  mkdir -p "$SKILL_DST"

  # Sanitizza: rimuovi righe frontmatter non supportate da Codex
  # Rimuovi anche riferimenti a ${CLAUDE_SKILL_DIR} (PM-CONSTITUTION e' inlineato in AGENTS.md)
  awk '
    BEGIN { in_front=0; front_count=0 }
    /^---$/ {
      front_count++
      if (front_count == 1) { in_front=1; print; next }
      if (front_count == 2) { in_front=0; print; next }
    }
    in_front && /^(model|user-invocable|disable-model-invocation):/ { next }
    { print }
  ' "$SKILL_FILE" | \
  sed 's|\${CLAUDE_SKILL_DIR}/\.\./setup/templates/PM-CONSTITUTION\.md|PM-CONSTITUTION.md (gia'\''\ inlineata in AGENTS.md — disponibile in contesto)|g' \
  > "$SKILL_DST/SKILL.md"

  CODEX_SKILL_COUNT=$((CODEX_SKILL_COUNT + 1))
done

ok "Skills copiate per Codex: $CODEX_SKILL_COUNT (frontmatter sanitizzato)"

# ── .mcp.json (Codex plugin usa .mcp.json, come Claude Code) ────────────────
# Il formato e' lo stesso di Claude Code: i server URL/HTTP sono supportati nativamente.
# Ref: https://developers.openai.com/codex/mcp
if [ -f "$DIST_DIR/.mcp.json" ]; then
  # Rimuovi il campo "type" che e' specifico di Claude Code — Codex usa "url" direttamente
  jq '
    .mcpServers |= with_entries(
      if .value.type == "url" or .value.type == "http" then
        .value |= {url: .url}
      else
        .
      end
    )
  ' "$DIST_DIR/.mcp.json" > "$CODEX_DIR/.mcp.json"
  ok ".mcp.json generata per Codex"
fi

# ── plugin.json ──────────────────────────────────────────────────────────────
# Ref: https://developers.openai.com/codex/plugins/build
# Genera displayName: "pm-setup" → "Pm Setup"
DISPLAY_NAME=$(echo "$NAME" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

jq -n \
  --arg name "$NAME" \
  --arg version "$VERSION" \
  --arg description "$DESCRIPTION" \
  --arg author "$AUTHOR" \
  --arg displayName "$DISPLAY_NAME" \
  '{
    name: $name,
    version: $version,
    description: $description,
    author: { name: $author },
    skills: "./skills/",
    mcpServers: "./.mcp.json",
    interface: {
      displayName: $displayName,
      shortDescription: $description,
      developerName: $author,
      category: "Productivity"
    }
  }' > "$CODEX_DIR/.codex-plugin/plugin.json"

ok "plugin.json generato per Codex"

# ── README ───────────────────────────────────────────────────────────────────
CODEX_README="$TEMPLATE_DIR/CODEX-README.md"
if [ -f "$CODEX_README" ]; then
  cp "$CODEX_README" "$CODEX_DIR/README.md"
  ok "README.md copiato per Codex"
fi
