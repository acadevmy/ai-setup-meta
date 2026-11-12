#!/usr/bin/env bash
# tracker-clickup.sh — the ClickUp backend of auto-dev-tracker.sh.
#
# Sourced, never run: auto-dev-tracker.sh owns the command line, the refusals,
# the notes and the clock, and calls the five functions below. This file holds
# only what is ClickUp's — the REST API, the token, the custom id lookup and the
# time tracking.
#
# Environment:
#   CLICKUP_API_TOKEN  required — a ClickUp personal token (pk_…)
#   CLICKUP_TEAM_ID    the workspace id; required for a custom id (DE-123), which
#                      the API resolves only within a workspace
#   CLICKUP_API_BASE   default https://api.clickup.com/api/v2 — the tests point
#                      it elsewhere
#
# Functions: backend_check, backend_read, backend_move <name>…,
# backend_comment <text>, backend_log_time <minutes>

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "tracker-clickup.sh is sourced by auto-dev-tracker.sh, not run" >&2
  exit 1
fi

CLICKUP_BASE="${CLICKUP_API_BASE:-https://api.clickup.com/api/v2}"
CLICKUP_TEAM="${CLICKUP_TEAM_ID:-}"
CLICKUP_QUERY=""

backend_check() {
  # The header goes into a curl config file, so a token is checked for the one
  # shape a ClickUp token has before it gets there: anything else could carry a
  # second config line.
  TOKEN="${CLICKUP_API_TOKEN:-}"
  [ -n "$TOKEN" ] || refuse "CLICKUP_API_TOKEN is not set: the run needs a ClickUp personal token in its environment"
  printf '%s' "$TOKEN" | grep -qE '^[A-Za-z0-9_-]+$' \
    || refuse "CLICKUP_API_TOKEN does not look like a ClickUp token (letters, digits, dash, underscore)"
  if printf '%s' "$TASK" | grep -qE "$KEY_SHAPE"; then
    [ -n "$CLICKUP_TEAM" ] || refuse "$TASK is a custom id, and ClickUp resolves one only within a workspace: set CLICKUP_TEAM_ID"
    CLICKUP_QUERY="custom_task_ids=true&team_id=$CLICKUP_TEAM"
  fi
}

clickup_api() {
  http_call "$1" "$CLICKUP_BASE$2" "Authorization: $TOKEN" "${3-}"
}

clickup_task_path() {
  printf '/task/%s%s%s' "$TASK" "$1" "${CLICKUP_QUERY:+?$CLICKUP_QUERY}"
}

backend_read() {
  local path task_json
  path="$(clickup_task_path "")"
  if [ -n "$CLICKUP_QUERY" ]; then
    path="$path&include_markdown_description=true"
  else
    path="$path?include_markdown_description=true"
  fi
  clickup_api GET "$path" || api_error "ClickUp GET task"
  task_json="$API_BODY"
  printf '%s' "$task_json" | jq -e 'type == "object" and has("id")' >/dev/null 2>&1 \
    || { API_STATUS="$API_STATUS (no task in the answer)"; api_error "ClickUp GET task"; }

  json_set TASK_ID "$(printf '%s' "$task_json" | jq -r '.id // ""')"
  json_set KEY "$(printf '%s' "$task_json" | jq -r '.custom_id // ""')"
  json_set NAME "$(printf '%s' "$task_json" | jq -r '.name // ""')"
  json_set DESCRIPTION "$(printf '%s' "$task_json" \
    | jq -r '[.markdown_description, .description, .text_content] | map(select(. != null and . != "")) | first // ""')"
  json_set STATUS "$(printf '%s' "$task_json" | jq -r '.status.status // "" | ascii_upcase')"
  json_set PRIORITY "$(printf '%s' "$task_json" | jq -r '.priority.priority // "" | ascii_downcase')"
  json_set URL "$(printf '%s' "$task_json" | jq -r '.url // ""')"
  # shellcheck disable=SC2034  # read by auto-dev-tracker.sh
  BOARD_IS_BACKLOG=false
  CLICKUP_TEAM="${CLICKUP_TEAM:-$(printf '%s' "$task_json" | jq -r '.team_id // ""')}"
}

# A move is a PUT of the status name, each candidate in order: a list without
# the first name refuses it, and the next one is tried.
backend_move() {
  local status
  for status in "$@"; do
    if clickup_api PUT "$(clickup_task_path "")" "$(jq -n --arg s "$status" '{status: $s}')"; then
      json_set MOVED_TO "$status"
      json_set STATUS "$status"
      return 0
    fi
  done
  api_error "ClickUp PUT status ($*)"
}

backend_comment() {
  clickup_api POST "$(clickup_task_path /comment)" "$(jq -n --arg t "$1" '{comment_text: $t, notify_all: false}')"
}

# The measured time goes to ClickUp's own tracking, where the board's cost
# fields read it. Its start is computed back from now: the clock measured the
# interval, and the run ends here.
backend_log_time() {
  local minutes="$1" duration_ms start_ms
  [ -n "$CLICKUP_TEAM" ] || return 1
  duration_ms=$((minutes * 60000))
  start_ms=$(( $(date +%s) * 1000 - duration_ms ))
  clickup_api POST "/team/$CLICKUP_TEAM/time_entries" "$(jq -n \
    --arg tid "$(json_get TASK_ID)" --argjson start "$start_ms" --argjson duration "$duration_ms" \
    '{tid: $tid, start: $start, duration: $duration, description: "auto-dev run"}')" || {
    warn "the time entry was refused (${API_STATUS:-no status}): the clock line goes in the comment instead"
    return 1
  }
}
