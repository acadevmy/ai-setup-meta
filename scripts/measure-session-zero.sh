#!/usr/bin/env bash
# measure-session-zero.sh — measures the prompt tokens of a session zero.
#
# It opens a `claude -p` session with a minimal prompt and reports the size of the
# prompt sent: the baseline to compare a plugin change against (registered MCP
# servers, skills, rules, AGENTS.md).
#
# Usage:
#   scripts/measure-session-zero.sh --dir <project> [--mcp-config <file>]
#                                   [--tool-search on|off] [--model <name>] [--json]
#
# The total is input_tokens + cache_creation_input_tokens + cache_read_input_tokens:
# that sum does not depend on the cache state, so two runs are comparable.
#
# Note: with --mcp-config those servers are the only ones loaded (--strict-mcp-config),
# but servers that need OAuth come back as `needs-auth` in non-interactive mode and
# contribute no tool definitions. Check MCP_SERVERS in the output before reading the
# numbers.

set -euo pipefail

DIR="."
MCP_CONFIG=""
TOOL_SEARCH="on"
MODEL="sonnet"
AS_JSON=false

die() { echo "error: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)         DIR="${2:-}"; shift 2 ;;
    --mcp-config)  MCP_CONFIG="${2:-}"; shift 2 ;;
    --tool-search) TOOL_SEARCH="${2:-}"; shift 2 ;;
    --model)       MODEL="${2:-}"; shift 2 ;;
    --json)        AS_JSON=true; shift ;;
    -h|--help)     sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unrecognised argument: $1" ;;
  esac
done

command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"
[ -d "$DIR" ] || die "directory not found: $DIR"

case "$TOOL_SEARCH" in
  on)  unset ENABLE_TOOL_SEARCH ;;
  off) export ENABLE_TOOL_SEARCH=false ;;
  *)   die "--tool-search takes 'on' or 'off' (got: $TOOL_SEARCH)" ;;
esac

ARGS=(-p "Rispondi esattamente: OK" --output-format stream-json --verbose --model "$MODEL")
if [ -n "$MCP_CONFIG" ]; then
  [ -f "$MCP_CONFIG" ] || die "--mcp-config file not found: $MCP_CONFIG"
  ARGS+=(--strict-mcp-config --mcp-config "$MCP_CONFIG")
fi

STREAM=$(cd "$DIR" && claude "${ARGS[@]}" 2>/dev/null) || die "the claude session failed"
[ -n "$STREAM" ] || die "no output from the claude session"

RESULT=$(printf '%s\n' "$STREAM" | jq -c 'select(.type == "result")' | tail -1)
INIT=$(printf '%s\n' "$STREAM" | jq -c 'select(.subtype == "init")' | tail -1)
[ -n "$RESULT" ] || die "the session produced no result message"

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
