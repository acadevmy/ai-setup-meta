#!/usr/bin/env bash
# auto-dev-checks.sh — the project's quality commands for an auto-dev run, run
# so that the agent that asked can wait for them however long they take.
#
# A Bash call has a ceiling — 600 s unless the runner raises
# BASH_MAX_TIMEOUT_MS — and a command still running there is moved to the
# background. For a subagent that is a trap: the command is killed when the
# agent gives its final answer, and the agent has no long wait of its own
# (Monitor expires at five minutes, a bare `sleep` is refused). On job
# ad-invictus-de-17941-mvs8mncb the verify agent ran `flutter test 2>&1 | tail
# -n 60`, a suite of about 13 minutes: at 600 s the call went to the
# background with an empty output file — tail writes nothing before the end —
# and a minute later the agent reported the suite red. The developer had seen
# it green.
#
# So running and waiting are two calls, and the state is on disk:
#
#   - the first call runs each command from the repository root into its own
#     log, and records each exit status as it lands. Finished within the call
#     or moved to the background, it goes on, and its answer lands in its
#     state directory;
#   - --wait blocks until that answer is there, for --budget seconds at most
#     (540: under the 600 s ceiling), and prints it — or DONE=false, which
#     means: call --wait again.
#
# A second call without --wait while a run is alive on the same tree does not
# start a second copy: it waits for that one. A run whose heartbeat stopped —
# killed, or its session gone — is answered as such: its checks were not
# proven.
#
# The commands are detect-stack.sh's, minus the ones quality-preflight.sh finds
# this environment cannot start: never installed, never replaced.
#
# Usage:
#   auto-dev-checks.sh --task <id> [--wait] [--budget <seconds>] [--json]
#
#   --task <id>         the task the run checks: it names the state directory
#   --wait              wait for the run already started; never start one
#   --budget <seconds>  how long this call waits at most (default 540)
#   --json              emit a flat JSON object
#
# Keys:
#   DONE              true once the run is over: every key below is final
#   PASSED            true when every command that started exited 0 — empty
#                     until DONE, false when the run was refused or stopped
#   LINT_STATUS       passed | failed | not-found (exit 126/127) |
#   TYPECHECK_STATUS    unavailable | absent | pending | running | stopped
#   TEST_STATUS
#   OUTPUT            per command that ran, `--- <kind>: <command> (exit N)`
#                     and the tail of its log: 40 lines for a red one, 5 for a
#                     green one, where a runner prints its summary
#   LOG_DIR           the directory that holds each command's full log
#   TREE              the tree checked: the HEAD commit, then `+<hash>` when
#                     the working tree differed from it
#   REASON            why there is no verdict: refused, or stopped
#
# Exit: 0 done, green · 4 done, a command red · 5 not done yet: call --wait
# again · 3 no verdict: refused (no declared command, a run on another tree
# still alive, nothing to wait for) or the run stopped before its end · 1 usage
# error, or not a git working tree
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
TASK=""
WAIT=false
BUDGET=540

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

need_value() {
  [ "$2" -ge 2 ] && [ -n "$3" ] || die "$1 requires a value"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --task) need_value "$1" $# "${2-}"; TASK="$2"; shift 2 ;;
    --wait) WAIT=true; shift ;;
    --budget) need_value "$1" $# "${2-}"; BUDGET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$TASK" ] || die "--task is required"
printf '%s' "$TASK" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' \
  || die "--task \"$TASK\" is not a plain identifier"
case "$BUDGET" in
  ''|*[!0-9]*) die "--budget takes whole seconds, not \"$BUDGET\"" ;;
esac

require_jq

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working tree"
cd "$ROOT" || die "cannot enter $ROOT"

DIR="$(state_dir auto-dev-checks)/$TASK" || die "cannot resolve the git directory"

KINDS="lint typecheck test"
# A live run rewrites its heartbeat every HEARTBEAT_S; one silent for STALE_S
# is gone. A waiting call looks every POLL_S.
HEARTBEAT_S=10
STALE_S=60
POLL_S=2
# The tail of a log OUTPUT carries: the failure, or the runner's summary.
RED_LINES=40
GREEN_LINES=5

now() { date +%s; }
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

# The state directory holds one file per fact, each written whole.
put() { printf '%s' "$2" > "$DIR/$1.tmp" && mv "$DIR/$1.tmp" "$DIR/$1"; }
get() { [ -f "$DIR/$1" ] && cat "$DIR/$1"; }

# The tree a run checks: HEAD, then `+<hash>` of what the working tree changes.
tree_id() {
  local head changes
  head="$(git rev-parse HEAD 2>/dev/null || printf 'none')"
  changes="$(git status --porcelain 2>/dev/null)"
  if [ -z "$changes" ]; then
    printf '%s' "$head"
    return 0
  fi
  printf '%s+%s' "$head" \
    "$({ printf '%s\n' "$changes"; git diff HEAD --binary 2>/dev/null; } | git hash-object --stdin | cut -c1-12)"
}

heartbeat_fresh() {
  local beat
  beat="$(get heartbeat)"
  [ -n "$beat" ] && [ $(( $(now) - beat )) -lt "$STALE_S" ]
}

alive() {
  [ -f "$DIR/started" ] && [ ! -f "$DIR/exit-code" ] && heartbeat_fresh
}

# ── The answer, composed from the state directory ─────────────────────────────

answer() {
  local kind status lines ending out="" red=false passed="" code=5
  # Placed first, so the verdict leads the answer; set for real below.
  json_set DONE false
  json_set PASSED ""
  for kind in $KINDS; do
    status="$(get "$kind.status")"
    json_set "$(upper "$kind")_STATUS" "$status"
    case "$status" in
      passed) lines=$GREEN_LINES ;;
      failed|not-found|stopped) lines=$RED_LINES ;;
      *) continue ;;
    esac
    [ "$status" = failed ] && red=true
    if [ -f "$DIR/$kind.rc" ]; then ending="exit $(get "$kind.rc")"; else ending="$status"; fi
    out="${out:+$out
}--- $kind: $(get "$kind.cmd") ($ending)
$(tail -n "$lines" "$DIR/$kind.log" 2>/dev/null)"
  done

  if [ -f "$DIR/exit-code" ]; then
    code="$(get exit-code)"
    if [ -n "$(get reason)" ]; then passed=false
    elif [ "$red" = true ]; then passed=false
    else passed=true
    fi
    json_set DONE true
  else
    json_set DONE false
  fi
  json_set PASSED "$passed"
  json_set OUTPUT "$out"
  json_set LOG_DIR "$DIR"
  json_set TREE "$(get tree)"
  json_set REASON "$(get reason)"

  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
  exit "$code"
}

# A refusal of this call that leaves the state directory alone: a live run's
# files are its own.
refuse_call() {
  local kind
  json_set DONE false
  json_set PASSED ""
  for kind in $KINDS; do json_set "$(upper "$kind")_STATUS" ""; done
  json_set OUTPUT ""
  json_set LOG_DIR "$DIR"
  json_set TREE "$(tree_id)"
  json_set REASON "$1"
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
  exit 3
}

# A run that stopped without its answer is answered for it: what was running
# was not proven.
mark_stopped() {
  local kind
  for kind in $KINDS; do
    [ "$(get "$kind.status")" = running ] && put "$kind.status" stopped
  done
  put reason "the run stopped before its end — killed, or its session ended: the checks were not proven"
  put exit-code 3
}

wait_for_run() {
  local deadline
  deadline=$(( $(now) + BUDGET ))
  while :; do
    [ -f "$DIR/exit-code" ] && answer
    heartbeat_fresh || { mark_stopped; answer; }
    [ "$(now)" -lt "$deadline" ] || answer
    sleep "$POLL_S"
  done
}

# ── --wait: never starts anything ─────────────────────────────────────────────

if [ "$WAIT" = true ]; then
  [ -f "$DIR/started" ] \
    || refuse_call "no run to wait for: start one with auto-dev-checks.sh --task $TASK, without --wait"
  wait_for_run
fi

# ── A run already going ───────────────────────────────────────────────────────

TREE="$(tree_id)"
if alive; then
  [ "$(get tree)" = "$TREE" ] && wait_for_run
  refuse_call "a run started on another state of the tree ($(get tree)) is still going: wait for it with --wait, then run this again"
fi

# ── A new run ─────────────────────────────────────────────────────────────────

rm -rf "$DIR"
mkdir -p "$DIR" || die "cannot create $DIR"
put started "$(now)"
put tree "$TREE"
put heartbeat "$(now)"

# The heartbeat outlives nothing: it stops with this script, killed or not.
beat() {
  while kill -0 "$1" 2>/dev/null; do
    put heartbeat "$(now)"
    sleep "$HEARTBEAT_S"
  done
}
beat "$$" &
BEAT_PID=$!
trap 'kill "$BEAT_PID" 2>/dev/null' EXIT

refuse_run() {
  put reason "$1"
  put exit-code 3
  answer
}

STACK="$(bash "$SCRIPT_DIR/detect-stack.sh" --json 2>/dev/null)" \
  || refuse_run "detect-stack.sh rejects the project's quality-commands declaration: the checks cannot be read"
PRE="$(bash "$SCRIPT_DIR/quality-preflight.sh" --require-declared --allow-unavailable --json 2>/dev/null)"
PRE_STATUS=$?
pre_get() { printf '%s' "$PRE" | jq -r --arg k "$1" '.[$k] // ""'; }
[ "$PRE_STATUS" -eq 0 ] || refuse_run "quality-preflight.sh refuses: $(pre_get REASON)"
UNAVAILABLE=" $(pre_get UNAVAILABLE) "

for KIND in $KINDS; do
  CMD="$(printf '%s' "$STACK" | jq -r --arg k "$(upper "$KIND")_CMD" '.[$k] // ""')"
  if [ -z "$CMD" ]; then
    put "$KIND.status" absent
    continue
  fi
  put "$KIND.cmd" "$CMD"
  case "$UNAVAILABLE" in
    *" $KIND "*) put "$KIND.status" unavailable ;;
    *) put "$KIND.status" pending ;;
  esac
done

RED=false
for KIND in $KINDS; do
  [ "$(get "$KIND.status")" = pending ] || continue
  put "$KIND.status" running
  bash -c "$(get "$KIND.cmd")" > "$DIR/$KIND.log" 2>&1 < /dev/null
  RC=$?
  put "$KIND.rc" "$RC"
  case "$RC" in
    0) put "$KIND.status" passed ;;
    126|127) put "$KIND.status" not-found ;;
    *) put "$KIND.status" failed; RED=true ;;
  esac
done

if [ "$RED" = true ]; then put exit-code 4; else put exit-code 0; fi
answer
