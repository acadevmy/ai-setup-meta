#!/usr/bin/env bash
# task-clock.sh — the work clock of a task: stamped when the board moves to
# IN PROGRESS, read back when the merge request opens.
#
# Every flow in this plugin ends the same way — a merge request and a task in
# review — and none of them could say how long the work took. The two events
# that answer it are already in the flow, one at each end, so the only thing
# missing was somewhere to keep the first until the second happens.
#
# Why a script and not a note in the context: the elapsed time is arithmetic on
# two clock readings, and a model asked to do it at the end of a long run has
# neither the first reading nor a reason to be right about it. Worse, it has
# every incentive to produce a plausible number. An empty COMMENT here is the
# answer "the clock has nothing to report", and it is the only honest one when
# nobody stamped the start.
#
# Only an autonomous run is measured. Its interval is one sitting of work, so the
# elapsed time is the time the work took. An interactive task spans nights, CI
# waits and other tasks: its elapsed time reads like a measurement and is not
# one (76h on a task worked for a fraction of that). So the launchers start the
# clock with --measure, and the interactive flows start it without: their clock
# still says which task is in play here — the notification and merge-request
# hooks read exactly that — and its --stop reports no duration (`unmeasured`).
#
# The state lives in the repository's *common* git directory, so a worktree and
# the checkout that created it share one clock (the interactive flow stamps the
# start inside the worktree; `auto-sdd` stamps it in the launcher's checkout).
# It is never part of the working tree, so `git add -A` cannot commit it and
# `git clean` cannot delete it.
#
# Usage:
#   task-clock.sh --task DE-123 --start [--measure] [--json]
#   task-clock.sh --task DE-123 --stop   [--json]
#   task-clock.sh [--task DE-123] --status [--json]
#
#   --task <id>   the task's custom id — the clock is per task, not per branch.
#                 Required by --start and --stop, optional for --status
#   --start       open an interval; already open, it is left alone
#   --measure     with --start: the interval is a measurement, and its --stop
#                 reports the duration. Only the autonomous launchers pass it
#   --stop        close the open interval and report what it measured
#   --status      report without writing: is this task's clock running, and
#                 which clocks are open in this repository. The reader of the
#                 state, for anything that must not consume a measurement —
#                 the merge-request hook asks it whether there is still a task
#                 in progress here
#   --json        emit a flat JSON object
#
# Keys:
#   TASK            the task id, as given
#   RUNNING         true while an interval is open
#   MEASURED        true when the open interval, or the one --stop just
#                   closed, was started with --measure
#   STARTED_AT      the open interval's start, `YYYY-MM-DD HH:MM` local time
#   STOPPED_AT      when --stop closed it, same format
#   MINUTES         the interval just closed, in minutes — measured ones only
#   DURATION        the same, as `2h 15m` — empty when nothing was measured
#   TOTAL_MINUTES   every closed measured interval of this task, summed
#   TOTAL_DURATION  the same, as `2h 15m`
#   SESSIONS        how many measured intervals have closed
#   COMMENT         the line to post on the task, ready to send as the
#                   `comment` of the board's status update — empty when there
#                   is nothing to report, and then nothing is posted
#   REASON          why COMMENT is empty: no-start-stamp | already-stopped |
#                   unmeasured
#   OPEN_TASKS      every task with an open interval in this repository,
#                   space-separated — a fan-out has one per worktree, and they
#                   share the common git directory
#   OPEN_COUNT      how many they are
#   RECENT_TASKS    every task in this repository whose last event is a stop
#                   less than 300 seconds old, space-separated — never one with
#                   an open interval. A run that stops its clock and then waits
#                   for the developer (the BLOCKED move of a failed run) is still
#                   the task in play, and the notification hook names it
#   STATE_FILE      where the clock is kept — empty for a --status with no task
#
# Exit: 0 on success, including a --stop with nothing to measure · 1 usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# The same shape multi-preflight.sh and the workflow validate. Here it also
# guards a file path: `../../hooks/pre-commit` as a task id must not resolve.
TASK_ID_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

AS_JSON=false
TASK=""
MODE=""
MEASURE=false

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
    --start|--stop|--status)
      [ -z "$MODE" ] || die "--start, --stop and --status are separate calls, not one"
      MODE="${1#--}"; shift ;;
    --measure) MEASURE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

[ -n "$MODE" ] || die "nothing to do: pass --start, --stop or --status (see --help)"
# Whether an interval is a measurement is decided once, when it opens.
if [ "$MEASURE" = true ] && [ "$MODE" != "start" ]; then
  die "--measure goes with --start: an interval is measured from the moment it opens"
fi
# --status answers for the repository when no task is named, which is how a
# caller that does not know the task id — the merge-request hook — finds out
# there is one in progress at all.
if [ "$MODE" != "status" ]; then
  [ -n "$TASK" ] || die "--task is required: the clock is kept per task id"
fi
if [ -n "$TASK" ]; then
  printf '%s' "$TASK" | grep -qE "$TASK_ID_SHAPE" \
    || die "\"$TASK\" is not a plain task id (letters, digits, dot, dash, underscore)"
fi

# ── Where the clock lives ─────────────────────────────────────────────────────

[ "$(detect_vcs)" = "git" ] \
  || die "not a git repository: the work clock is kept in the repository's git directory"

STATE_DIR="$(state_dir task-clock)" || die "cannot resolve the git directory"
STATE_FILE=""
[ -n "$TASK" ] && STATE_FILE="$STATE_DIR/$TASK.log"

# ── Reading the log ───────────────────────────────────────────────────────────
#
# One line per event, tab-separated:
#   start <epoch> <YYYY-MM-DD HH:MM> [measured]
#   stop  <epoch> <YYYY-MM-DD HH:MM> <minutes>
#
# The epoch is what the arithmetic uses and the stamp is what a human reads:
# BSD `date` cannot parse back what GNU `date` prints, so nothing here ever
# parses a formatted date. A start with no fourth field is an unmeasured one:
# its stop carries no minutes, and it counts in no total.

OPEN_EPOCH=""
OPEN_STAMP=""
OPEN_MEASURED=false
CLOSED_MINUTES=0
SESSIONS=0
EVER_STOPPED=false

read_log() {
  [ -f "$STATE_FILE" ] || return 0
  local kind epoch stamp extra
  while IFS=$'\t' read -r kind epoch stamp extra; do
    case "$kind" in
      start)
        OPEN_EPOCH="$epoch"
        OPEN_STAMP="$stamp"
        OPEN_MEASURED=false
        [ "$extra" = "measured" ] && OPEN_MEASURED=true
        ;;
      stop)
        [ -n "$OPEN_EPOCH" ] || continue
        EVER_STOPPED=true
        if [ "$OPEN_MEASURED" = true ]; then
          CLOSED_MINUTES=$((CLOSED_MINUTES + ${extra:-0}))
          SESSIONS=$((SESSIONS + 1))
        fi
        OPEN_EPOCH=""
        OPEN_STAMP=""
        OPEN_MEASURED=false
        ;;
    esac
  done < "$STATE_FILE"
}

# The open interval's stamp for any log, or the empty string when the clock is
# closed. Same file format as read_log, read without touching the globals: the
# repository scan below needs an answer per task, not the running totals.
open_stamp_of() {
  local file="$1" kind epoch stamp minutes open=""
  [ -f "$file" ] || return 0
  while IFS=$'\t' read -r kind epoch stamp minutes; do
    case "$kind" in
      start) open="$stamp" ;;
      stop) open="" ;;
    esac
  done < "$file"
  printf '%s' "$open"
}

# The epoch of a log's last event when that event is a stop, or the empty
# string. Same file format again, read without touching the globals.
last_stop_epoch_of() {
  local file="$1" kind epoch stamp minutes last=""
  [ -f "$file" ] || return 0
  while IFS=$'\t' read -r kind epoch stamp minutes; do
    case "$kind" in
      start) last="" ;;
      stop) last="$epoch" ;;
    esac
  done < "$file"
  printf '%s' "$last"
}

# Minutes between two epochs, rounded to the nearest minute. An interval that
# closed is never reported as 0m: a one-line fix takes seconds, and "0m" reads
# as a broken clock rather than as a fast job.
minutes_between() {
  local from="$1" to="$2" seconds minutes
  seconds=$((to - from))
  [ "$seconds" -gt 0 ] || { printf '1'; return 0; }
  minutes=$(((seconds + 30) / 60))
  [ "$minutes" -ge 1 ] || minutes=1
  printf '%s' "$minutes"
}

# Minutes as `2h 15m`, `2h`, `15m`. Empty input stays empty: the callers pass a
# duration straight into the report, and "0m" would claim a measurement.
format_duration() {
  local total="${1:-}" hours minutes
  [ -n "$total" ] || return 0
  hours=$((total / 60))
  minutes=$((total % 60))
  if [ "$hours" -gt 0 ] && [ "$minutes" -gt 0 ]; then
    printf '%dh %dm' "$hours" "$minutes"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh' "$hours"
  else
    printf '%dm' "$minutes"
  fi
}

read_log

NOW_EPOCH="$(date +%s)"
NOW_STAMP="$(date '+%Y-%m-%d %H:%M')"

STARTED_AT=""
STOPPED_AT=""
MINUTES=""
DURATION=""
COMMENT=""
REASON=""
RUNNING=false
MEASURED=false

case "$MODE" in
  start)
    if [ -n "$OPEN_EPOCH" ]; then
      # A resumed flow re-runs intake. The first stamp is the real one, so it
      # stands: overwriting it would silently discard the work already done.
      # So does its kind: a second --start cannot turn it into a measurement.
      STARTED_AT="$OPEN_STAMP"
      MEASURED="$OPEN_MEASURED"
      REASON="already-running"
    else
      mkdir -p "$STATE_DIR" \
        || die "cannot write the clock in $STATE_DIR"
      START_LINE="$(printf 'start\t%s\t%s' "$NOW_EPOCH" "$NOW_STAMP")"
      [ "$MEASURE" = true ] && START_LINE="$(printf '%s\tmeasured' "$START_LINE")"
      printf '%s\n' "$START_LINE" >> "$STATE_FILE" \
        || die "cannot write the clock in $STATE_FILE"
      STARTED_AT="$NOW_STAMP"
      MEASURED="$MEASURE"
    fi
    RUNNING=true
    ;;

  stop)
    if [ -n "$OPEN_EPOCH" ] && [ "$OPEN_MEASURED" = false ]; then
      # The task leaves play, so the hooks stop naming it, and nothing is
      # reported: the elapsed time of an interactive task is not its work time.
      printf 'stop\t%s\t%s\t\n' "$NOW_EPOCH" "$NOW_STAMP" >> "$STATE_FILE" \
        || die "cannot write the clock in $STATE_FILE"
      STARTED_AT="$OPEN_STAMP"
      STOPPED_AT="$NOW_STAMP"
      REASON="unmeasured"
    elif [ -n "$OPEN_EPOCH" ]; then
      MINUTES="$(minutes_between "$OPEN_EPOCH" "$NOW_EPOCH")"
      printf 'stop\t%s\t%s\t%s\n' "$NOW_EPOCH" "$NOW_STAMP" "$MINUTES" >> "$STATE_FILE" \
        || die "cannot write the clock in $STATE_FILE"
      STARTED_AT="$OPEN_STAMP"
      STOPPED_AT="$NOW_STAMP"
      MEASURED=true
      DURATION="$(format_duration "$MINUTES")"
      CLOSED_MINUTES=$((CLOSED_MINUTES + MINUTES))
      SESSIONS=$((SESSIONS + 1))
      COMMENT="Time in progress: $DURATION ($STARTED_AT → $STOPPED_AT)"
      if [ "$SESSIONS" -gt 1 ]; then
        COMMENT="$COMMENT — $(format_duration "$CLOSED_MINUTES") total over $SESSIONS sessions"
      fi
    elif [ "$EVER_STOPPED" = true ]; then
      REASON="already-stopped"
    else
      REASON="no-start-stamp"
    fi
    ;;

  status)
    # Reports, writes nothing. A caller that only wants to know whether work is
    # still open must not be the one that closes it: --stop is a measurement,
    # and taking it twice is how a duration gets lost.
    if [ -n "$OPEN_EPOCH" ]; then
      STARTED_AT="$OPEN_STAMP"
      RUNNING=true
      MEASURED="$OPEN_MEASURED"
    elif [ -n "$TASK" ] && [ "$EVER_STOPPED" = false ]; then
      REASON="no-start-stamp"
    elif [ -n "$TASK" ]; then
      REASON="already-stopped"
    fi
    ;;
esac

# ── What is open in this repository ───────────────────────────────────────────
#
# Reported in every mode, after the mutation: the answer is about the clocks,
# not about the call. A fan-out keeps one log per task and every worktree shares
# the common git directory, so this is the whole repository's view.

#
# RECENT_TASKS is the same pass looking the other way: a clock stopped less than
# RECENT_WINDOW seconds ago. A failed run stops its clock and then asks for the
# BLOCKED move, so for those few seconds it is still the task the developer is
# being called back for — and the reader still writes nothing.

RECENT_WINDOW=300
OPEN_TASKS=""
OPEN_COUNT=0
RECENT_TASKS=""
if [ -d "$STATE_DIR" ]; then
  for LOG in "$STATE_DIR"/*.log; do
    [ -f "$LOG" ] || continue
    if [ -n "$(open_stamp_of "$LOG")" ]; then
      OPEN_TASKS="${OPEN_TASKS:+$OPEN_TASKS }$(basename "$LOG" .log)"
      OPEN_COUNT=$((OPEN_COUNT + 1))
      continue
    fi
    LAST_STOP="$(last_stop_epoch_of "$LOG")"
    case "$LAST_STOP" in
      ''|*[!0-9]*) continue ;;
    esac
    [ $((NOW_EPOCH - LAST_STOP)) -lt "$RECENT_WINDOW" ] || continue
    RECENT_TASKS="${RECENT_TASKS:+$RECENT_TASKS }$(basename "$LOG" .log)"
  done
fi

# ── Output ────────────────────────────────────────────────────────────────────

TOTAL_MINUTES=""
TOTAL_DURATION=""
if [ "$SESSIONS" -gt 0 ]; then
  TOTAL_MINUTES="$CLOSED_MINUTES"
  TOTAL_DURATION="$(format_duration "$CLOSED_MINUTES")"
fi

json_set TASK "$TASK"
json_set RUNNING "$RUNNING"
json_set MEASURED "$MEASURED"
json_set STARTED_AT "$STARTED_AT"
json_set STOPPED_AT "$STOPPED_AT"
json_set MINUTES "$MINUTES"
json_set DURATION "$DURATION"
json_set TOTAL_MINUTES "$TOTAL_MINUTES"
json_set TOTAL_DURATION "$TOTAL_DURATION"
json_set SESSIONS "$SESSIONS"
json_set COMMENT "$COMMENT"
json_set REASON "$REASON"
json_set OPEN_TASKS "$OPEN_TASKS"
json_set OPEN_COUNT "$OPEN_COUNT"
json_set RECENT_TASKS "$RECENT_TASKS"
json_set STATE_FILE "$STATE_FILE"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
