#!/usr/bin/env bash
# auto-dev-tracker.sh — the board, for an auto-dev run nobody watches.
#
# Every other flow reaches the task tracker through the `tracker` agent and the
# tracker's MCP, which authorises over OAuth — a login a person does once, in a
# browser. A disposable machine running `claude -p` has no such login, so the
# agent would find no tool and the run would fail on its first read. This
# script talks to the tracker's API instead, with a personal token from the
# environment, and needs no model at all: reading a task and moving it are
# three HTTP calls, not a reasoning step.
#
# What is the same on every tracker lives here: the command line, the
# refusals, the backlog gate, the notes, the work clock. What is the tracker's
# own — the API, the token, the status lookup, the time tracking — is a backend,
# scripts/tracker-<provider>.sh, sourced below.
#
# The token never reaches a command line, where `ps` and the logs would show
# it: curl reads its Authorization header from stdin (`--config -`), written
# there by a shell builtin.
#
# Usage:
#   auto-dev-tracker.sh --task DE-123 --read   [--json]
#   auto-dev-tracker.sh --task DE-123 --start  [--json]
#   auto-dev-tracker.sh --task DE-123 --finish --result <result.json>
#                       [--mr-url <url>] [--pushed true|false] [--json]
#   (any mode)          [--provider clickup|linear] [--config <.claude/tracker.json>]
#
#   --read     the task: name, description, status, priority, url
#   --start    the move that starts the work: IN PROGRESS, and the work clock
#   --finish   the move that ends it, from the run's result.json:
#              ready-for-mr → IN REVIEW, with the merge request link —
#              --mr-url is required; failed → BLOCKED, with why it failed and
#              what to do next — or, for a run that never started (stage select
#              or intake), what the task needs. The clock's measurement goes to
#              the tracker's own time tracking when it has one; its COMMENT
#              line goes in the comment otherwise, or when that call fails
#   --pushed   whether the runner pushed the branch of a failed run, for the
#              BLOCKED note
#   --provider the tracker; default what tracker-config.sh resolves (the
#              environment, then .claude/tracker.json)
#   --config   the project's .claude/tracker.json (setup step 6.1), default the
#              one at the root of the current repository: its `status` names
#              the board's own statuses, tried before the adapter's defaults
#   --json     emit a flat JSON object
#
# Environment: the backend's — CLICKUP_API_TOKEN and CLICKUP_TEAM_ID for
# ClickUp, LINEAR_API_KEY for Linear (see scripts/tracker-<provider>.sh).
#
# Keys:
#   TASK         the task id, as given
#   PROVIDER     clickup | linear
#   TASK_ID      the tracker's internal id
#   KEY          the task key (DE-123, ENG-42), empty when the task has none
#   NAME         the task name
#   DESCRIPTION  the description, markdown when the tracker has it
#   STATUS       the status read, or the one moved to, as the board names it
#   PRIORITY     urgent | high | normal | low, empty when unset
#   URL          the task's link
#   IS_BACKLOG   true when the task is in the board's BACKLOG status
#   MOVED_TO     the status a --start or --finish moved the task to
#   COMMENTED    true when --finish posted its comment
#   TIME_LOGGED  true when --finish logged the measured time on the task
#   MINUTES      the minutes the clock measured, empty when it measured nothing
#   REASON       why a call was refused, empty otherwise
#
# Exit: 0 done · 3 refused (no tracker, no token, a task in BACKLOG, a result
# without what --finish needs; REASON says why) · 1 an API or usage error
# (stderr)
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# The same shape the workflow validates: the id reaches a URL path here.
TASK_ID_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

# A task key is a prefix, a dash and a number; anything else is the tracker's own id.
KEY_SHAPE='^[A-Za-z][A-Za-z0-9]*-[0-9]+$'

# The tail of a failed run's output that goes on the board: enough to see the
# error, short enough that the note stays a note.
NOTE_OUTPUT_LINES=30

AS_JSON=false
MODE=""
TASK=""
RESULT=""
MR_URL=""
PUSHED=""
CONFIG=""
PROVIDER=""

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --task)
      [ $# -ge 2 ] || die "--task requires an id"
      TASK="$2"; shift 2 ;;
    --read|--start|--finish) MODE="${1#--}"; shift ;;
    --result)
      [ $# -ge 2 ] || die "--result requires a path"
      RESULT="$2"; shift 2 ;;
    --mr-url)
      [ $# -ge 2 ] || die "--mr-url requires a url"
      MR_URL="$2"; shift 2 ;;
    --pushed)
      [ $# -ge 2 ] || die "--pushed requires true or false"
      PUSHED="$2"; shift 2 ;;
    --config)
      [ $# -ge 2 ] || die "--config requires a path"
      CONFIG="$2"; shift 2 ;;
    --provider)
      [ $# -ge 2 ] || die "--provider requires a tracker"
      PROVIDER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
command -v curl >/dev/null 2>&1 || die "curl not found"
[ -n "$MODE" ] || die "one of --read, --start or --finish is required (see --help)"
[ -n "$TASK" ] || die "--task is required"

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

json_set TASK "$TASK"
json_set REASON ""

CONFIG_ARGS=()
[ -n "$CONFIG" ] && CONFIG_ARGS=(--config "$CONFIG")

# status_names <canonical> — the board's names to try, the project's first.
status_names() {
  bash "$SCRIPT_DIR/tracker-config.sh" ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} --status "$1" --json 2>/dev/null \
    | jq -r '.STATUS_NAMES // ""'
}

if [ -z "$PROVIDER" ]; then
  RESOLVED="$(bash "$SCRIPT_DIR/tracker-config.sh" ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"} --json 2>/dev/null)"
  PROVIDER="$(printf '%s' "$RESOLVED" | jq -r '.PROVIDER // ""' 2>/dev/null)"
  [ -n "$PROVIDER" ] \
    || refuse "the tracker configuration was refused: $(printf '%s' "$RESOLVED" | jq -r '.REASON // "see stderr"' 2>/dev/null)"
fi
# The provider is exported so the status lookups below resolve the same one.
export TRACKER_PROVIDER="$PROVIDER"
json_set PROVIDER "$PROVIDER"

case "$PROVIDER" in
  clickup|linear) ;;
  none) refuse "no task tracker is configured: set TRACKER_PROVIDER, or run the setup to write .claude/tracker.json" ;;
  *) refuse "the tracker is \"$PROVIDER\": it takes clickup or linear" ;;
esac

printf '%s' "$TASK" | grep -qE "$TASK_ID_SHAPE" \
  || refuse "\"$TASK\" is not a plain task id: it would reach a URL, so fix it on the board"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-dev.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$TMP_DIR"' EXIT

# http_call <method> <url> <auth header> [<json body>] — the body lands in
# API_BODY, the status in API_STATUS; non-zero on a transport error or an HTTP
# status of 400 and above. The header goes to curl on stdin, never in argv.
API_BODY=""
API_STATUS=""
http_call() {
  local method="$1" url="$2" header="$3" body="${4-}" out
  local curl_args=(--silent --show-error --max-time 30 --request "$method"
    --header "Content-Type: application/json" --write-out '\n%{http_code}' --config -)
  if [ -n "$body" ]; then
    printf '%s' "$body" > "$TMP_DIR/body.json"
    curl_args+=(--data-binary "@$TMP_DIR/body.json")
  fi
  out=$(printf 'header = "%s"\n' "$header" | curl "${curl_args[@]}" "$url") || {
    API_STATUS=""
    API_BODY="$out"
    return 1
  }
  API_STATUS="${out##*$'\n'}"
  API_BODY="${out%$'\n'*}"
  case "$API_STATUS" in
    [123]??) return 0 ;;
    *) return 1 ;;
  esac
}

api_error() {
  printf 'error: %s answered %s: %s\n' "$1" "${API_STATUS:-no status}" \
    "$(printf '%s' "$API_BODY" | head -c 400)" >&2
  exit 1
}

TOKEN=""
BOARD_IS_BACKLOG=false
# shellcheck source=./tracker-clickup.sh
source "$SCRIPT_DIR/tracker-$PROVIDER.sh"

backend_check
backend_read

# is_backlog — the backend knows (Linear's state type), or the board's name is
# one the map gives for BACKLOG.
is_backlog() {
  [ "$BOARD_IS_BACKLOG" = true ] && return 0
  local current name
  current="$(json_get STATUS | tr '[:lower:]' '[:upper:]')"
  while IFS= read -r name; do
    [ -n "$name" ] && [ "$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')" = "$current" ] && return 0
  done < <(status_names backlog)
  return 1
}

if is_backlog; then json_set IS_BACKLOG true; else json_set IS_BACKLOG false; fi

if [ "$MODE" = read ]; then
  finish_output
  exit 0
fi

# The clock is per task, under the key when the task has one: --start and
# --finish have to name the same clock whichever id the caller passed.
KEY="$(json_get KEY)"
CLOCK_ID="${KEY:-$TASK}"

# move_to <canonical> — every board name for it, the project's first.
move_to() {
  local names=()
  while IFS= read -r name; do
    [ -n "$name" ] && names+=("$name")
  done < <(status_names "$1")
  [ ${#names[@]} -gt 0 ] || die "no board status for $1"
  backend_move "${names[@]}"
}

# ── Start ─────────────────────────────────────────────────────────────────────
#
# BACKLOG is work nobody planned, and the backlog gate is a person saying yes to
# it. No person is here: the run refuses before the board moves.

if [ "$MODE" = start ]; then
  [ "$(json_get IS_BACKLOG)" != true ] \
    || refuse "$TASK is in BACKLOG: it was never planned, and the backlog gate needs a person — move it to the board's ready status first"
  move_to in_progress
  bash "$SCRIPT_DIR/task-clock.sh" --task "$CLOCK_ID" --start --json >/dev/null 2>&1 \
    || warn "the work clock did not start: --finish will have no time to log"
  finish_output
  exit 0
fi

# ── Finish ────────────────────────────────────────────────────────────────────

[ -n "$RESULT" ] || die "--finish requires --result <result.json>"
[ -f "$RESULT" ] || die "no result file at $RESULT"
jq -e 'type == "object" and (.status == "ready-for-mr" or .status == "failed")' "$RESULT" >/dev/null 2>&1 \
  || refuse "$RESULT is not an auto-dev result: its status is neither ready-for-mr nor failed"

STATUS_OUT="$(jq -r '.status' "$RESULT")"

if [ "$STATUS_OUT" = ready-for-mr ] && [ -z "$MR_URL" ]; then
  refuse "a ready-for-mr result moves the task to review with its merge request: pass --mr-url"
fi

CLOCK="$(bash "$SCRIPT_DIR/task-clock.sh" --task "$CLOCK_ID" --stop --json 2>/dev/null || true)"
MINUTES="$(printf '%s' "$CLOCK" | jq -r '.MINUTES // ""' 2>/dev/null)"
CLOCK_COMMENT="$(printf '%s' "$CLOCK" | jq -r '.COMMENT // ""' 2>/dev/null)"
json_set MINUTES "$MINUTES"

if [ "$STATUS_OUT" = ready-for-mr ]; then
  NOTE="$(jq -r --arg url "$MR_URL" '
    [ "auto-dev: merge request opened — \($url)",
      "Branch: \(.branch // "")",
      (if (.toConfirm // []) + (.deviations // []) | length > 0
       then "To confirm on the merge request: \(((.toConfirm // []) + (.deviations // [])) | length)" else empty end),
      (if (.openPoints // []) | length > 0 then "Open points: \(.openPoints | length)" else empty end),
      (if (.unverified // []) | length > 0
       then "Not verified here: \(.unverified | map(.kind + " (" + .command + ")") | join(", "))" else empty end)
    ] | join("\n")' "$RESULT")"
  move_to in_review
else
  # A run that never reached the workflow — no repository chosen, arguments
  # refused — has no branch and no output: the note says what the task needs.
  NOTE="$(jq -r --arg pushed "$PUSHED" --arg id "$CLOCK_ID" --argjson lines "$NOTE_OUTPUT_LINES" '
    if .stage == "select" or .stage == "intake" then
      [ "auto-dev: the run did not start (\(.stage)) — \(.reason // "no reason given")",
        (if .stage == "select"
         then "To resume: add a `repo: owner/repo` line (and `base: <branch>` when it is not the default) to the description, then move the task back to the ready status."
         else "To resume: fix the cause, then move the task back to the ready status." end)
      ] | join("\n")
    else
    [ "auto-dev: the run failed at \(.stage // "broken") — \(.reason // "no reason given")",
      (if (.notes // "") != "" then "Notes: \(.notes)" else empty end),
      (if (.checks.output // "") != ""
       then "Output (tail):\n" + ((.checks.output | split("\n")) | .[-$lines:] | join("\n")) else empty end),
      (if (.branch // "") == "" then "No branch: the dev step never created one."
       elif $pushed == "true" then "Branch on origin: \(.branch)"
       elif $pushed == "false" then "Branch \(.branch) was NOT pushed: the work is gone with the machine."
       else "Branch: \(.branch)" end),
      "To resume: fix the cause, check the branch out and run /dev-setup:sdd \($id)."
    ] | join("\n")
    end' "$RESULT")"
  move_to blocked
fi

# The measured time goes to the tracker's own time tracking when it has one;
# otherwise, or when that call fails, the clock's line goes in the comment.
TIME_LOGGED=false
if [ -n "$MINUTES" ] && [ "$MINUTES" -gt 0 ] 2>/dev/null && backend_log_time "$MINUTES"; then
  TIME_LOGGED=true
fi
json_set TIME_LOGGED "$TIME_LOGGED"

if [ "$TIME_LOGGED" = false ] && [ -n "$CLOCK_COMMENT" ]; then
  NOTE="$NOTE
$CLOCK_COMMENT"
fi

if backend_comment "$NOTE"; then
  json_set COMMENTED true
else
  json_set COMMENTED false
  warn "the comment was refused (${API_STATUS:-no status}): the task moved without its note"
fi

json_set REASON ""
finish_output
