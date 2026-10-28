#!/usr/bin/env bash
# auto-dev-clickup.sh — the board, for an auto-dev run nobody watches.
#
# Every other flow reaches ClickUp through the `clickup` agent and the ClickUp
# MCP, which authorises over OAuth — a login a person does once, in a browser.
# A disposable machine running `claude -p` has no such login, so the agent
# would find no tool and the run would fail on its first read. This script
# talks to the ClickUp REST API instead, with a personal token from the
# environment, and needs no model at all: reading a task and moving it are
# three HTTP calls, not a reasoning step.
#
# The token never reaches a command line, where `ps` and the logs would show
# it: curl reads its Authorization header from stdin (`--config -`), written
# there by a shell builtin.
#
# Usage:
#   auto-dev-clickup.sh --task DE-123 --read   [--json]
#   auto-dev-clickup.sh --task DE-123 --start  [--json]
#   auto-dev-clickup.sh --task DE-123 --finish --result <result.json>
#                       [--mr-url <url>] [--pushed true|false] [--json]
#   (any mode)          [--config <.claude/auto-dev.json>]
#
#   --read     the task: name, description, status, priority, url
#   --start    the move that starts the work: IN PROGRESS, and the work clock
#   --finish   the move that ends it, from the run's result.json:
#              ready-for-mr → CODE REVIEW (IN REVIEW when the list has no
#              CODE REVIEW), with the merge request link — --mr-url is required;
#              failed → BLOCKED, with why it failed and what to do next — or,
#              for a run that never started (stage select or intake), what the
#              task needs. The clock's measurement goes to ClickUp's own time
#              tracking; its COMMENT line goes in the comment only when that
#              call fails
#   --pushed   whether the runner pushed the branch of a failed run, for the
#              BLOCKED note
#   --config   the project's .claude/auto-dev.json (step 7d of the setup),
#              default the one at the root of the current repository: its
#              `status` names the board's own in_progress, in_review and blocked
#              statuses, tried before the defaults above
#   --json     emit a flat JSON object
#
# Environment:
#   CLICKUP_API_TOKEN  required — a ClickUp personal token (pk_…)
#   CLICKUP_TEAM_ID    the workspace id; required for a custom id (DE-123), which
#                      the API resolves only within a workspace
#   CLICKUP_API_BASE   default https://api.clickup.com/api/v2 — the tests point
#                      it elsewhere
#
# Keys:
#   TASK         the task id, as given
#   TASK_ID      ClickUp's internal id
#   CUSTOM_ID    the custom id (DE-123), empty when the task has none
#   NAME         the task name
#   DESCRIPTION  the description, markdown when ClickUp has it
#   STATUS       the status read, or the one moved to
#   PRIORITY     urgent | high | normal | low, empty when unset
#   URL          the task's link
#   MOVED_TO     the status a --start or --finish moved the task to
#   COMMENTED    true when --finish posted its comment
#   TIME_LOGGED  true when --finish logged the measured time on the task
#   MINUTES      the minutes the clock measured, empty when it measured nothing
#   REASON       why a call was refused, empty otherwise
#
# Exit: 0 done · 3 refused (no token, a task in BACKLOG, a result without what
# --finish needs; REASON says why) · 1 an API or usage error (stderr)
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

API_BASE="${CLICKUP_API_BASE:-https://api.clickup.com/api/v2}"
TEAM_ID="${CLICKUP_TEAM_ID:-}"

# The same shape the workflow validates: the id reaches a URL path here.
TASK_ID_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

# A custom id is a prefix, a dash and a number; anything else is ClickUp's own.
CUSTOM_ID_SHAPE='^[A-Za-z][A-Za-z0-9]*-[0-9]+$'

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

# The board's own status names, when the project wrote them (setup step 7d):
# a list whose review column is "In QA" is moved there, not refused. The
# defaults are the ClickUp contract's names, tried after.
if [ -z "$CONFIG" ]; then
  CONFIG_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$CONFIG_ROOT" ] && CONFIG="$CONFIG_ROOT/.claude/auto-dev.json"
fi
status_name() {
  [ -n "$CONFIG" ] && [ -f "$CONFIG" ] || return 0
  jq -r --arg k "$1" '.status[$k] // "" | if type == "string" then . else "" end' "$CONFIG" 2>/dev/null || true
}
ST_PROGRESS="$(status_name in_progress)"
ST_REVIEW="$(status_name in_review)"
ST_BLOCKED="$(status_name blocked)"

printf '%s' "$TASK" | grep -qE "$TASK_ID_SHAPE" \
  || refuse "\"$TASK\" is not a plain task id: it would reach a URL, so fix it on the board"

# The header goes into a curl config file, so a token is checked for the one
# shape a ClickUp token has before it gets there: anything else could carry a
# second config line.
TOKEN="${CLICKUP_API_TOKEN:-}"
[ -n "$TOKEN" ] || refuse "CLICKUP_API_TOKEN is not set: the run needs a ClickUp personal token in its environment"
printf '%s' "$TOKEN" | grep -qE '^[A-Za-z0-9_-]+$' \
  || refuse "CLICKUP_API_TOKEN does not look like a ClickUp token (letters, digits, dash, underscore)"

QUERY=""
if printf '%s' "$TASK" | grep -qE "$CUSTOM_ID_SHAPE"; then
  [ -n "$TEAM_ID" ] || refuse "$TASK is a custom id, and ClickUp resolves one only within a workspace: set CLICKUP_TEAM_ID"
  QUERY="custom_task_ids=true&team_id=$TEAM_ID"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-dev.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$TMP_DIR"' EXIT

# api <method> <path> [<json body>] — the body lands in API_BODY, the status in
# API_STATUS; non-zero on a transport error or an HTTP status of 400 and above.
API_BODY=""
API_STATUS=""
api() {
  local method="$1" path="$2" body="${3-}" out
  local curl_args=(--silent --show-error --max-time 30 --request "$method"
    --header "Content-Type: application/json" --write-out '\n%{http_code}' --config -)
  if [ -n "$body" ]; then
    printf '%s' "$body" > "$TMP_DIR/body.json"
    curl_args+=(--data-binary "@$TMP_DIR/body.json")
  fi
  out=$(printf 'header = "Authorization: %s"\n' "$TOKEN" | curl "${curl_args[@]}" "$API_BASE$path") || {
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

task_path() {
  printf '/task/%s%s%s' "$TASK" "$1" "${QUERY:+?$QUERY}"
}

api_error() {
  printf 'error: ClickUp %s answered %s: %s\n' "$1" "${API_STATUS:-no status}" \
    "$(printf '%s' "$API_BODY" | head -c 400)" >&2
  exit 1
}

# ── Read ──────────────────────────────────────────────────────────────────────

read_task() {
  local path
  path="$(task_path "")"
  if [ -n "$QUERY" ]; then
    path="$path&include_markdown_description=true"
  else
    path="$path?include_markdown_description=true"
  fi
  api GET "$path" || api_error "GET task"
  TASK_JSON="$API_BODY"
  printf '%s' "$TASK_JSON" | jq -e 'type == "object" and has("id")' >/dev/null 2>&1 \
    || { API_STATUS="$API_STATUS (no task in the answer)"; api_error "GET task"; }

  json_set TASK_ID "$(printf '%s' "$TASK_JSON" | jq -r '.id // ""')"
  json_set CUSTOM_ID "$(printf '%s' "$TASK_JSON" | jq -r '.custom_id // ""')"
  json_set NAME "$(printf '%s' "$TASK_JSON" | jq -r '.name // ""')"
  json_set DESCRIPTION "$(printf '%s' "$TASK_JSON" \
    | jq -r '[.markdown_description, .description, .text_content] | map(select(. != null and . != "")) | first // ""')"
  json_set STATUS "$(printf '%s' "$TASK_JSON" | jq -r '.status.status // "" | ascii_upcase')"
  json_set PRIORITY "$(printf '%s' "$TASK_JSON" | jq -r '.priority.priority // "" | ascii_downcase')"
  json_set URL "$(printf '%s' "$TASK_JSON" | jq -r '.url // ""')"
  TEAM_ID="${TEAM_ID:-$(printf '%s' "$TASK_JSON" | jq -r '.team_id // ""')}"
}

# A move is a PUT of the status name. The fallback is the board's: a list
# without CODE REVIEW has IN REVIEW (the ClickUp contract's transitions).
move_to() {
  local status
  for status in "$@"; do
    if api PUT "$(task_path "")" "$(jq -n --arg s "$status" '{status: $s}')"; then
      json_set MOVED_TO "$status"
      json_set STATUS "$status"
      return 0
    fi
  done
  api_error "PUT status ($*)"
}

comment() {
  api POST "$(task_path /comment)" "$(jq -n --arg t "$1" '{comment_text: $t, notify_all: false}')"
}

read_task

if [ "$MODE" = read ]; then
  finish_output
  exit 0
fi

# The clock is per task, under the custom id when the task has one: --start and
# --finish have to name the same clock whichever id the caller passed.
CUSTOM="$(json_get CUSTOM_ID)"
CLOCK_ID="${CUSTOM:-$TASK}"

# ── Start ─────────────────────────────────────────────────────────────────────
#
# BACKLOG is work nobody planned into a sprint, and the backlog gate is a person
# saying yes to it. No person is here: the run refuses before the board moves.

if [ "$MODE" = start ]; then
  [ "$(json_get STATUS)" != BACKLOG ] \
    || refuse "$TASK is in BACKLOG: it was never planned into a sprint, and the backlog gate needs a person — plan it into SPRINT first"
  move_to ${ST_PROGRESS:+"$ST_PROGRESS"} "IN PROGRESS"
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
  move_to ${ST_REVIEW:+"$ST_REVIEW"} "CODE REVIEW" "IN REVIEW"
else
  # A run that never reached the workflow — no repository chosen, arguments
  # refused — has no branch and no output: the note says what the task needs.
  NOTE="$(jq -r --arg pushed "$PUSHED" --arg id "$CLOCK_ID" --argjson lines "$NOTE_OUTPUT_LINES" '
    if .stage == "select" or .stage == "intake" then
      [ "auto-dev: the run did not start (\(.stage)) — \(.reason // "no reason given")",
        (if .stage == "select"
         then "To resume: add a `repo: owner/repo` line (and `base: <branch>` when it is not the default) to the description, then move the task back to SPRINT."
         else "To resume: fix the cause, then move the task back to SPRINT." end)
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
  move_to ${ST_BLOCKED:+"$ST_BLOCKED"} "BLOCKED"
fi

# The measured time goes to ClickUp's own tracking, where the board's cost
# fields read it. Its start is computed back from now: the clock measured the
# interval, and the run ends here.
TIME_LOGGED=false
if [ -n "$MINUTES" ] && [ "$MINUTES" -gt 0 ] 2>/dev/null && [ -n "$TEAM_ID" ]; then
  DURATION_MS=$((MINUTES * 60000))
  START_MS=$(( $(date +%s) * 1000 - DURATION_MS ))
  if api POST "/team/$TEAM_ID/time_entries" "$(jq -n \
       --arg tid "$(json_get TASK_ID)" --argjson start "$START_MS" --argjson duration "$DURATION_MS" \
       '{tid: $tid, start: $start, duration: $duration, description: "auto-dev run"}')"; then
    TIME_LOGGED=true
  else
    warn "the time entry was refused (${API_STATUS:-no status}): the clock line goes in the comment instead"
  fi
fi
json_set TIME_LOGGED "$TIME_LOGGED"

if [ "$TIME_LOGGED" = false ] && [ -n "$CLOCK_COMMENT" ]; then
  NOTE="$NOTE
$CLOCK_COMMENT"
fi

if comment "$NOTE"; then
  json_set COMMENTED true
else
  json_set COMMENTED false
  warn "the comment was refused (${API_STATUS:-no status}): the task moved without its note"
fi

json_set REASON ""
finish_output
