#!/usr/bin/env bash
# build-gemini.sh — Builder per Gemini CLI
#
# Genera la variante Gemini in $DIST_DIR/gemini/.
# Richiede che il build Claude sia gia' stato eseguito (legge da $DIST_DIR/).
# Variabili richieste dall'orchestratore:
#   ROOT_DIR, TEMPLATE_DIR, MANIFEST, DIST_DIR, NAME, DESCRIPTION, VERSION, AUTHOR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Generazione output Gemini CLI"

GEMINI_DIR="$DIST_DIR/gemini"
mkdir -p "$GEMINI_DIR"

# ── GEMINI.md — istruzioni di sistema ────────────────────────────────────────
{
  echo "# Gemini System Instructions — $DESCRIPTION"
  echo ""
  echo "> Generato automaticamente da ai-base-setup. Non modificare direttamente."
  echo ""

  AGENTS_TPL="$DIST_DIR/skills/setup/templates/AGENTS.template.md"
  if [ -f "$AGENTS_TPL" ]; then
    echo "---"
    echo ""
    cat "$AGENTS_TPL"
    echo ""
  fi
} > "$GEMINI_DIR/GEMINI.md"

ok "GEMINI.md generato (istruzioni generali — skill nei comandi .toml)"

# ── Governance ───────────────────────────────────────────────────────────────
copy_governance "$GEMINI_DIR" "Gemini"

# ── README ───────────────────────────────────────────────────────────────────
GEMINI_README="$TEMPLATE_DIR/GEMINI-README.md"
if [ -f "$GEMINI_README" ]; then
  cp "$GEMINI_README" "$GEMINI_DIR/README.md"
  ok "README.md copiato per Gemini"
fi

# ── Comandi .toml ────────────────────────────────────────────────────────────
GEMINI_CMDS_DIR="$GEMINI_DIR/commands/pm"
mkdir -p "$GEMINI_CMDS_DIR"

CMD_COUNT=0
for SKILL_DIR in "$DIST_DIR/skills"/*/; do
  SKILL_FILE="$SKILL_DIR/SKILL.md"
  [ -f "$SKILL_FILE" ] || continue

  SKILL_NAME=$(basename "$SKILL_DIR")
  # Salta setup e reference skills (clickup, github-ops)
  [ "$SKILL_NAME" = "setup" ] && continue
  [ "$SKILL_NAME" = "clickup" ] && continue
  [ "$SKILL_NAME" = "github-ops" ] && continue

  # Estrai description dal frontmatter YAML
  SKILL_DESC=$(grep '^description:' "$SKILL_FILE" | head -1 | sed 's/^description: *//; s/^"//; s/"$//')
  [ -z "$SKILL_DESC" ] && SKILL_DESC="Esegui $SKILL_NAME"

  # Estrai il contenuto senza frontmatter (tutto dopo il secondo ---)
  SKILL_CONTENT=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2{print}' "$SKILL_FILE")

  # Genera il file .toml
  ESCAPED_DESC=$(echo "$SKILL_DESC" | head -1 | sed 's/"/\\"/g')
  {
    echo "description = \"$ESCAPED_DESC\""
    echo 'prompt = """'
    echo "Leggi il file PM-CONSTITUTION.md prima di procedere."
    echo ""
    echo "Esegui la seguente skill. Se l'utente ha fornito argomenti, usali come input."
    echo ""
    echo "Argomenti dell'utente: {{args}}"
    echo ""
    echo "$SKILL_CONTENT"
    echo '"""'
  } > "$GEMINI_CMDS_DIR/$SKILL_NAME.toml"

  CMD_COUNT=$((CMD_COUNT + 1))
done

ok "Comandi Gemini generati: $CMD_COUNT (.toml in commands/pm/)"

# ── Script di installazione ──────────────────────────────────────────────────
INSTALL_SCRIPT="$SCRIPT_DIR/../install-pm-gemini.sh"
if [ -f "$INSTALL_SCRIPT" ]; then
  cp "$INSTALL_SCRIPT" "$GEMINI_DIR/install.sh"
  ok "install.sh copiato per Gemini"
fi

# ── MCP config (mcp-remote bridge) ──────────────────────────────────────────
if [ -f "$DIST_DIR/.mcp.json" ]; then
  jq '
    .mcpServers |= with_entries(
      if .value.type == "url" or .value.type == "http" then
        .value = {
          trust: true,
          command: "npx",
          args: ["-y", "mcp-remote", .value.url]
        }
      else
        .
      end
    )
  ' "$DIST_DIR/.mcp.json" > "$GEMINI_DIR/.mcp.json"
  ok "MCP config generata per Gemini (mcp-remote bridge)"
fi
