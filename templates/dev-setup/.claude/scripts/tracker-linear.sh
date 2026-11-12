#!/usr/bin/env bash
# tracker-linear.sh — the Linear backend of auto-dev-tracker.sh.
#
# Sourced, never run: auto-dev-tracker.sh owns the command line, the refusals,
# the notes and the clock, and calls the five functions below. This file holds
# only what is Linear's — the GraphQL API, the key, the team's workflow states.
#
# Linear has no time tracking: backend_log_time answers 1, and the clock's line
# travels in the closing comment, as the contract says for a tracker without it.
#
# Environment:
#   LINEAR_API_KEY   required — a Linear personal API key (lin_api_…)
#   LINEAR_API_URL   default https://api.linear.app/graphql — the tests point it
#                    elsewhere
#
# Functions: backend_check, backend_read, backend_move <name>…,
# backend_comment <text>, backend_log_time <minutes>

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "tracker-linear.sh is sourced by auto-dev-tracker.sh, not run" >&2
  exit 1
fi

LINEAR_URL="${LINEAR_API_URL:-https://api.linear.app/graphql}"
LINEAR_ISSUE_ID=""
LINEAR_STATES="[]"

backend_check() {
  # A personal key goes in the header as it is, with no scheme. It reaches a
  # curl config file, so it is checked for its shape first.
  TOKEN="${LINEAR_API_KEY:-}"
  [ -n "$TOKEN" ] || refuse "LINEAR_API_KEY is not set: the run needs a Linear personal API key in its environment"
  printf '%s' "$TOKEN" | grep -qE '^[A-Za-z0-9_-]+$' \
    || refuse "LINEAR_API_KEY does not look like a Linear key (letters, digits, dash, underscore)"
}

# gql <query> <variables json> — the answer's .data lands in API_BODY; non-zero
# on a transport error, an HTTP error, or a GraphQL `errors` array.
gql() {
  local payload
  payload="$(jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}')"
  http_call POST "$LINEAR_URL" "Authorization: $TOKEN" "$payload" || return 1
  if printf '%s' "$API_BODY" | jq -e '(.errors // []) | length > 0' >/dev/null 2>&1; then
    API_STATUS="$API_STATUS (GraphQL: $(printf '%s' "$API_BODY" | jq -r '[.errors[].message] | join("; ")'))"
    return 1
  fi
  API_BODY="$(printf '%s' "$API_BODY" | jq -c '.data // {}')"
}

backend_read() {
  local issue
  gql 'query($id: String!) { issue(id: $id) { id identifier title description url priority
         state { name type } team { key states { nodes { id name type } } } } }' \
      "$(jq -n --arg id "$TASK" '{id: $id}')" || api_error "Linear issue"
  issue="$(printf '%s' "$API_BODY" | jq -c '.issue // empty')"
  [ -n "$issue" ] || { API_STATUS="$API_STATUS (no issue in the answer)"; api_error "Linear issue"; }

  LINEAR_ISSUE_ID="$(printf '%s' "$issue" | jq -r '.id')"
  LINEAR_STATES="$(printf '%s' "$issue" | jq -c '.team.states.nodes // []')"
  json_set TASK_ID "$LINEAR_ISSUE_ID"
  json_set KEY "$(printf '%s' "$issue" | jq -r '.identifier // ""')"
  json_set NAME "$(printf '%s' "$issue" | jq -r '.title // ""')"
  json_set DESCRIPTION "$(printf '%s' "$issue" | jq -r '.description // ""')"
  json_set STATUS "$(printf '%s' "$issue" | jq -r '.state.name // "" | ascii_upcase')"
  json_set PRIORITY "$(printf '%s' "$issue" \
    | jq -r '{"1": "urgent", "2": "high", "3": "normal", "4": "low"}[(.priority // 0) | tostring] // ""')"
  json_set URL "$(printf '%s' "$issue" | jq -r '.url // ""')"
  # Linear says what a state is, whatever the team calls it.
  if [ "$(printf '%s' "$issue" | jq -r '.state.type // ""')" = backlog ]; then
    BOARD_IS_BACKLOG=true
  else
    BOARD_IS_BACKLOG=false
  fi
}

# A move is the id of the team's state with that name, each candidate in order,
# case-insensitively. A name the team does not have is skipped, not invented.
backend_move() {
  local status state_id
  for status in "$@"; do
    state_id="$(printf '%s' "$LINEAR_STATES" \
      | jq -r --arg n "$status" '[.[] | select((.name | ascii_downcase) == ($n | ascii_downcase))][0].id // ""')"
    [ -n "$state_id" ] || continue
    if gql 'mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: { stateId: $s }) { success issue { state { name } } } }' \
         "$(jq -n --arg id "$LINEAR_ISSUE_ID" --arg s "$state_id" '{id: $id, s: $s}')" \
       && [ "$(printf '%s' "$API_BODY" | jq -r '.issueUpdate.success')" = true ]; then
      json_set MOVED_TO "$(printf '%s' "$API_BODY" | jq -r --arg n "$status" '.issueUpdate.issue.state.name // $n')"
      json_set STATUS "$(json_get MOVED_TO | tr '[:lower:]' '[:upper:]')"
      return 0
    fi
    api_error "Linear issueUpdate ($status)"
  done
  printf 'error: Linear team has no state named %s — set the status in .claude/tracker.json\n' "$*" >&2
  exit 1
}

backend_comment() {
  gql 'mutation($id: String!, $b: String!) { commentCreate(input: { issueId: $id, body: $b }) { success } }' \
      "$(jq -n --arg id "$LINEAR_ISSUE_ID" --arg b "$1" '{id: $id, b: $b}')" \
    && [ "$(printf '%s' "$API_BODY" | jq -r '.commentCreate.success')" = true ]
}

backend_log_time() {
  return 1
}
