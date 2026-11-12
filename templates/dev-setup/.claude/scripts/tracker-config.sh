#!/usr/bin/env bash
# tracker-config.sh — which task tracker this project uses, and the board names
# of the canonical statuses.
#
# The tracker is a project choice (ClickUp, Linear, or none), written by the
# setup into .claude/tracker.json. Every flow and every script that touches the
# board asks this script instead of reading that file its own way, so the
# resolution order lives in one place: the environment, then the file, then a
# project configured before the file existed — CLICKUP_SETUP_LIST_ID, which
# still means ClickUp with that list — then nothing. The third source the contract names — the values the plugin's
# userConfig substitutes into the `tracker` skill — is visible to a model only,
# never to a script, so a script that finds nothing here answers `none`.
#
# Usage:
#   tracker-config.sh [--config <path>] [--status <canonical>] [--json]
#
#   --config   the tracker.json to read, default .claude/tracker.json at the
#              root of the current repository
#   --status   one of backlog, ready, in_progress, in_review, done, blocked:
#              STATUS_NAMES carries the board's names for it, one per line,
#              in the order a move tries them — the project's first, then the
#              adapter's default
#   --json     emit a flat JSON object
#
# Environment:
#   TRACKER_PROVIDER   clickup | linear | none — wins over the file
#   TRACKER_LIST_ID    the list (ClickUp list id, Linear team key) — wins over
#                      the file's first one
#   CLICKUP_SETUP_LIST_ID  the variable every project used before tracker.json:
#                      with neither of the above nor the file, ClickUp and this
#                      list — so an existing project needs no step to keep working
#
# Keys:
#   PROVIDER       clickup | linear | none
#   LIST_ID        the default list: the first of LISTS
#   LISTS          every list, comma-separated
#   SOURCE         env | file | legacy | none — where PROVIDER came from
#   CONFIG_FILE    the tracker.json read, empty when there was none
#   STATUS_NAMES   with --status: the names to try, newline-separated
#   REASON         why the configuration was refused, empty otherwise
#
# Exit: 0 resolved (none included) · 3 refused: an unknown provider or a
# tracker.json that is not valid JSON (REASON says which) · 1 a usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
CONFIG=""
STATUS_KEY=""

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --config)
      [ $# -ge 2 ] || die "--config requires a path"
      CONFIG="$2"; shift 2 ;;
    --status)
      [ $# -ge 2 ] || die "--status requires a canonical status"
      STATUS_KEY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

finish_output() {
  if [ "$AS_JSON" = true ]; then
    json_emit
  else
    json_emit_text
  fi
}

refuse() {
  json_set REASON "$1"
  finish_output
  exit 3
}

case "$STATUS_KEY" in
  ""|backlog|ready|in_progress|in_review|done|blocked) ;;
  *) die "--status takes backlog, ready, in_progress, in_review, done or blocked" ;;
esac

for key in PROVIDER LIST_ID LISTS SOURCE CONFIG_FILE STATUS_NAMES REASON; do
  json_set "$key" ""
done

if [ -z "$CONFIG" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$ROOT" ] && CONFIG="$ROOT/.claude/tracker.json"
fi

FILE_PROVIDER=""
FILE_LISTS=""
if [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; then
  jq -e 'type == "object"' "$CONFIG" >/dev/null 2>&1 \
    || refuse "$CONFIG is not a JSON object: fix it or run the setup again"
  json_set CONFIG_FILE "$CONFIG"
  FILE_PROVIDER="$(jq -r '.provider // "" | ascii_downcase' "$CONFIG")"
  FILE_LISTS="$(jq -r '[.lists // [] | if type == "array" then .[] else . end | tostring] | join(",")' "$CONFIG")"
fi

PROVIDER="$(printf '%s' "${TRACKER_PROVIDER:-}" | tr '[:upper:]' '[:lower:]')"
if [ -n "$PROVIDER" ]; then
  SOURCE="env"
elif [ -n "$FILE_PROVIDER" ]; then
  PROVIDER="$FILE_PROVIDER"; SOURCE="file"
elif [ -n "${CLICKUP_SETUP_LIST_ID:-}" ]; then
  PROVIDER="clickup"; SOURCE="legacy"; FILE_LISTS="$CLICKUP_SETUP_LIST_ID"
else
  PROVIDER="none"; SOURCE="none"
fi

case "$PROVIDER" in
  clickup|linear|none) ;;
  *) refuse "the tracker is \"$PROVIDER\": it takes clickup, linear or none" ;;
esac

LISTS="$FILE_LISTS"
if [ -n "${TRACKER_LIST_ID:-}" ]; then
  LISTS="$TRACKER_LIST_ID"
fi
[ "$PROVIDER" = none ] && LISTS=""

json_set PROVIDER "$PROVIDER"
json_set SOURCE "$SOURCE"
json_set LISTS "$LISTS"
json_set LIST_ID "${LISTS%%,*}"

# The adapter's default names, the ones the setup proposes. The project's map
# comes first; the default stays behind it, so a board renamed halfway still
# finds the column the adapter knows.
default_status_names() {
  case "$1:$2" in
    clickup:backlog) echo BACKLOG ;;
    clickup:ready) echo SPRINT ;;
    clickup:in_progress) echo "IN PROGRESS" ;;
    clickup:in_review) printf 'CODE REVIEW\nIN REVIEW\n' ;;
    clickup:done) echo DONE ;;
    clickup:blocked) echo BLOCKED ;;
    linear:backlog) echo Backlog ;;
    linear:ready) echo Todo ;;
    linear:in_progress) echo "In Progress" ;;
    linear:in_review) echo "In Review" ;;
    linear:done) echo Done ;;
    linear:blocked) echo Blocked ;;
  esac
}

if [ -n "$STATUS_KEY" ] && [ "$PROVIDER" != none ]; then
  NAMES=""
  if [ -n "$(json_get CONFIG_FILE)" ]; then
    NAMES="$(jq -r --arg k "$STATUS_KEY" \
      '.status[$k] // empty | if type == "array" then .[] else . end | select(type == "string" and . != "")' \
      "$CONFIG" 2>/dev/null || true)"
  fi
  DEFAULTS="$(default_status_names "$PROVIDER" "$STATUS_KEY")"
  # Case-insensitive de-duplication, the project's names first.
  json_set STATUS_NAMES "$(printf '%s\n%s\n' "$NAMES" "$DEFAULTS" \
    | awk 'NF && !seen[tolower($0)]++')"
fi

finish_output
