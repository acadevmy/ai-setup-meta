#!/usr/bin/env bash
# multi-preflight.sh — the gate in front of a multi-task fan-out.
#
# `multi-sdd` starts one background run per task, each in its own worktree. The
# cap on how many is not a suggestion: five parallel runs already produce more
# spec, code and merge request than one person can review, and the sixth is
# where the session stops being a control tower and starts being a backlog.
#
# A number in prose gets re-read charitably ("six is close enough"). A number
# here is a number: the caller runs this before it launches anything, and a
# refusal is exit 3 with the reason, not a paragraph the model can weigh.
#
# The task ids are checked too, and for the same reason the workflow checks
# them: an id from the board reaches a branch name, a file path and a shell
# command inside an agent prompt. Catching a malformed one here costs nothing;
# catching it after four runs have started costs four worktrees.
#
# Usage:
#   multi-preflight.sh [--json] DE-1 DE-2 DE-3
#   multi-preflight.sh [--json] --task DE-1 --task DE-2
#   multi-preflight.sh [--json] --from-sprint 3
#
#   <id>…                 the task ids, as positional arguments
#   --task <id>           the same, one flag per id (both forms may be mixed)
#   --from-sprint <n>     no ids yet: validate `n` against the cap, then come
#                         back with the ids the board returned
#   --json                emit a flat JSON object
#
# Keys:
#   ACCEPTED     true when the fan-out may start
#   REASON       why it may not, empty when accepted
#   COUNT        how many task ids were given
#   TASKS        newline-separated task ids, in the order given
#   CAP          the maximum number of parallel runs
#   FROM_SPRINT  the count asked of the board, empty when ids were given
#
# Exit: 0 accepted · 3 refused (ACCEPTED=false, REASON says why) · 1 usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# The cap, in one place. The message, the docs and the check all read it here,
# so they cannot drift apart.
CAP=5

# The same shape the auto-sdd workflow validates: letters, digits, dot, dash,
# underscore, first character alphanumeric.
TASK_ID_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

AS_JSON=false
FROM_SPRINT=""
IDS=()

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --task)
      [ $# -ge 2 ] || die "--task requires an id"
      IDS+=("$2"); shift 2 ;;
    --from-sprint)
      [ $# -ge 2 ] || die "--from-sprint requires a count"
      FROM_SPRINT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown argument: $1 (see --help)" ;;
    *) IDS+=("$1"); shift ;;
  esac
done

require_jq

# ── The verdict ───────────────────────────────────────────────────────────────

COUNT=${#IDS[@]}
ACCEPTED=true
REASON=""

refuse() {
  ACCEPTED=false
  REASON="$1"
}

if [ -n "$FROM_SPRINT" ] && [ "$COUNT" -gt 0 ]; then
  refuse "both task ids and --from-sprint were given, and they are two different intakes: pass the ids, or ask the board for them, not both"
elif [ -n "$FROM_SPRINT" ]; then
  if ! printf '%s' "$FROM_SPRINT" | grep -qE '^[0-9]+$'; then
    refuse "--from-sprint takes a count, not \"$FROM_SPRINT\""
  elif [ "$FROM_SPRINT" -lt 1 ]; then
    refuse "--from-sprint $FROM_SPRINT asks for no task at all: ask for 1 to $CAP"
  elif [ "$FROM_SPRINT" -gt "$CAP" ]; then
    refuse "--from-sprint $FROM_SPRINT is over the cap of $CAP parallel runs: the review queue, not the tooling, is the limit"
  fi
elif [ "$COUNT" -eq 0 ]; then
  refuse "no task to work on: name 1 to $CAP task ids, or use --from-sprint <n> to take them from the board"
elif [ "$COUNT" -gt "$CAP" ]; then
  refuse "$COUNT tasks is over the cap of $CAP parallel runs: five runs already produce more spec, code and merge request than one person reviews in a sitting, so drop $((COUNT - CAP)) and run them in a second round"
fi

# Shape and duplicates, checked only once the count is sane: a list of six ids
# is refused for being six, and naming a malformed one as well would bury that.
if [ "$ACCEPTED" = true ] && [ "$COUNT" -gt 0 ]; then
  for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    if ! printf '%s' "$id" | grep -qE "$TASK_ID_SHAPE"; then
      refuse "\"$id\" is not a plain task id (letters, digits, dot, dash, underscore): it would reach a branch name and a shell command, so fix it on the board rather than working around it"
      break
    fi
    for j in "${!IDS[@]}"; do
      [ "$j" -ge "$i" ] && continue
      if [ "${IDS[$j]}" = "$id" ]; then
        refuse "$id is listed twice: two runs on one task would fight over the same branch"
        break 2
      fi
    done
  done
fi

# ── Output ────────────────────────────────────────────────────────────────────

TASKS=""
if [ "$COUNT" -gt 0 ]; then
  TASKS=$(printf '%s\n' "${IDS[@]}")
fi

json_set ACCEPTED "$ACCEPTED"
json_set REASON "$REASON"
json_set COUNT "$COUNT"
json_set TASKS "$TASKS"
json_set CAP "$CAP"
json_set FROM_SPRINT "$FROM_SPRINT"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi

[ "$ACCEPTED" = true ] || exit 3
