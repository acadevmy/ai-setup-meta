#!/usr/bin/env bash
# measure-session-zero.sh — misura i token di prompt di una sessione zero.
#
# Apre una sessione `claude -p` con un prompt minimo e riporta la dimensione del
# prompt inviato: e' la baseline con cui confrontare l'effetto di una modifica al
# plugin (server MCP registrati, skill, regole, AGENTS.md).
#
# Uso:
#   scripts/measure-session-zero.sh --dir <progetto> [--mcp-config <file>]
#                                   [--tool-search on|off] [--model <nome>] [--json]
#
# Il totale e' input_tokens + cache_creation_input_tokens + cache_read_input_tokens:
# la somma non dipende dallo stato della cache, quindi due run sono confrontabili.
#
# Nota: con --mcp-config i server sono gli unici caricati (--strict-mcp-config), ma i
# server che richiedono OAuth risultano `needs-auth` in modalita' non interattiva e non
# contribuiscono tool definition. Controlla MCP_SERVERS nell'output prima di leggere i
# numeri.

set -euo pipefail

DIR="."
MCP_CONFIG=""
TOOL_SEARCH="on"
MODEL="sonnet"
AS_JSON=false

die() { echo "errore: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)         DIR="${2:-}"; shift 2 ;;
    --mcp-config)  MCP_CONFIG="${2:-}"; shift 2 ;;
    --tool-search) TOOL_SEARCH="${2:-}"; shift 2 ;;
    --model)       MODEL="${2:-}"; shift 2 ;;
    --json)        AS_JSON=true; shift ;;
    -h|--help)     sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "argomento non riconosciuto: $1" ;;
  esac
done

command -v claude >/dev/null 2>&1 || die "claude CLI non trovata in PATH"
command -v jq >/dev/null 2>&1 || die "jq non trovato in PATH"
[ -d "$DIR" ] || die "directory non trovata: $DIR"

case "$TOOL_SEARCH" in
  on)  unset ENABLE_TOOL_SEARCH ;;
  off) export ENABLE_TOOL_SEARCH=false ;;
  *)   die "--tool-search accetta 'on' oppure 'off' (ricevuto: $TOOL_SEARCH)" ;;
esac

ARGS=(-p "Rispondi esattamente: OK" --output-format stream-json --verbose --model "$MODEL")
if [ -n "$MCP_CONFIG" ]; then
  [ -f "$MCP_CONFIG" ] || die "file --mcp-config non trovato: $MCP_CONFIG"
  ARGS+=(--strict-mcp-config --mcp-config "$MCP_CONFIG")
fi

STREAM=$(cd "$DIR" && claude "${ARGS[@]}" 2>/dev/null) || die "la sessione claude e' fallita"
[ -n "$STREAM" ] || die "nessun output dalla sessione claude"

RESULT=$(printf '%s\n' "$STREAM" | jq -c 'select(.type == "result")' | tail -1)
INIT=$(printf '%s\n' "$STREAM" | jq -c 'select(.subtype == "init")' | tail -1)
[ -n "$RESULT" ] || die "la sessione non ha prodotto un messaggio di result"

OUT=$(jq -n \
  --argjson result "$RESULT" \
  --argjson init "${INIT:-null}" \
  --arg model "$MODEL" \
  --arg toolSearch "$TOOL_SEARCH" \
  '{
    TOTAL_PROMPT_TOKENS: ($result.usage.input_tokens
                          + $result.usage.cache_creation_input_tokens
                          + $result.usage.cache_read_input_tokens),
    INPUT_TOKENS: $result.usage.input_tokens,
    CACHE_CREATION_TOKENS: $result.usage.cache_creation_input_tokens,
    CACHE_READ_TOKENS: $result.usage.cache_read_input_tokens,
    MCP_TOOLS: (if $init == null then null
                else ([$init.tools[] | select(startswith("mcp__"))] | length) end),
    MCP_SERVERS: (if $init == null then null
                  else [$init.mcp_servers[] | "\(.name)=\(.status)"] end),
    MODEL: $model,
    TOOL_SEARCH: $toolSearch
  }')

if [ "$AS_JSON" = true ]; then
  printf '%s\n' "$OUT"
else
  printf '%s\n' "$OUT" | jq -r '
    "totale prompt      : \(.TOTAL_PROMPT_TOKENS) token",
    "  input            : \(.INPUT_TOKENS)",
    "  cache creation   : \(.CACHE_CREATION_TOKENS)",
    "  cache read       : \(.CACHE_READ_TOKENS)",
    "tool MCP in contesto: \(.MCP_TOOLS // "n/d")",
    "server MCP         : \((.MCP_SERVERS // []) | join(", "))",
    "modello            : \(.MODEL)   tool search: \(.TOOL_SEARCH)"'
fi
