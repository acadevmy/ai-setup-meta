#!/usr/bin/env bash
# quality-preflight.sh — can this project check its own work, here and now?
#
# An autonomous run that cannot run the project's lint, typecheck or tests
# finds out at its last phase, after the spec, the Challenge and the whole
# implementation have been paid for: on DE-17472 that was 19 commits and about
# 145M input tokens for an outcome certain at intake. This script answers the
# question at intake, in seconds, before the board is touched or an agent
# starts. The two autonomous launchers ask it with --require-declared and
# --allow-unavailable; the setup asks it with --run, when it writes the
# declaration (step 3b).
#
# Two questions, kept apart. "Does the project say how to check its work?" is
# a project fact, and a no is always a refusal. "Can this environment run
# those commands?" is a fact about the machine: a cloud routine without PHP or
# MySQL, say. With --allow-unavailable a no there is not a refusal: the run
# goes on, the commands that cannot start are reported in UNAVAILABLE, and the
# merge request says which checks nobody ran.
#
# It reads the commands through detect-stack.sh, the one reader of
# `.claude/quality-commands.json`, and works from the repository root, where
# every consumer runs them.
#
# Usage:
#   quality-preflight.sh [--json] [--require-declared] [--allow-unavailable] [--run]
#
#   --require-declared  refuse unless the commands come from the declaration
#                       (COMMANDS_SOURCE=declared): what the autonomous
#                       launchers require
#   --allow-unavailable a program not installed, or a red declared preflight,
#                       does not refuse: the commands it affects are reported
#                       in UNAVAILABLE and the answer is ready. What the
#                       autonomous launchers pass: the run proceeds and the
#                       merge request names the checks it could not run
#   --run               also run each command once and report how it went;
#                       a red command is reported, only one that did not
#                       start (exit 126/127) is refused
#   --json              emit a flat JSON object
#
# Without --run nothing is executed except the declared preflight.
#
# Refused (exit 3, READY=false, REASON says why) when:
#   - detect-stack.sh rejects the declaration (REASON carries its cause);
#   - --require-declared is set and the commands are not declared;
#   - no command is left to run;
#   - without --allow-unavailable: the program a command starts is not
#     installed (none of them runs). A leading `VAR=value` and a leading
#     `cd <dir> &&` are skipped; a program with a `/` must be executable,
#     relative to that directory;
#   - without --allow-unavailable: the declared preflight exits non-zero
#     (OUTPUT holds its tail);
#   - with --run, a command did not start.
#
# Keys:
#   READY              true | false
#   REASON             why not, empty when ready
#   COMMANDS_SOURCE    declared | detected | none, as detect-stack.sh says
#   MISSING            one `<kind>: <program>` line per program not found
#   UNAVAILABLE        with --allow-unavailable, the kinds this environment
#                      cannot run (`lint test`): a missing program makes its
#                      own kind unavailable, a red preflight makes every
#                      declared kind unavailable
#   UNAVAILABLE_REASON one line per cause, for the merge request
#   PREFLIGHT          passed | failed | "" (none declared, or not reached)
#   OUTPUT             the tail of what failed: the preflight, a red command
#   LINT_STATUS        passed | failed | not-found | unavailable | absent
#   TYPECHECK_STATUS     (declared absent) | "" (no command, or not run)
#   TEST_STATUS
#
# Exit: 0 ready · 3 refused · 1 usage error or no jq
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
REQUIRE_DECLARED=false
RUN=false
ALLOW_UNAVAILABLE=false

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --require-declared) REQUIRE_DECLARED=true; shift ;;
    --run) RUN=true; shift ;;
    --allow-unavailable) ALLOW_UNAVAILABLE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

ROOT="$(repo_root)"
cd "$ROOT" || die "cannot enter the repository root: $ROOT"

# Keeps a reason readable: the tail is where a tool puts its summary.
MAX_OUTPUT_LINES=40

READY=true
REASON=""
COMMANDS_SOURCE=""
MISSING=""
UNAVAILABLE=""
UNAVAILABLE_REASON=""
PREFLIGHT=""
OUTPUT=""
LINT_STATUS=""
TYPECHECK_STATUS=""
TEST_STATUS=""

finish() {
  json_set READY "$READY"
  json_set REASON "$REASON"
  json_set COMMANDS_SOURCE "$COMMANDS_SOURCE"
  json_set MISSING "$MISSING"
  json_set UNAVAILABLE "$UNAVAILABLE"
  json_set UNAVAILABLE_REASON "$UNAVAILABLE_REASON"
  json_set PREFLIGHT "$PREFLIGHT"
  json_set OUTPUT "$OUTPUT"
  json_set LINT_STATUS "$LINT_STATUS"
  json_set TYPECHECK_STATUS "$TYPECHECK_STATUS"
  json_set TEST_STATUS "$TEST_STATUS"

  if [ "$AS_JSON" = true ]; then
    json_emit
  else
    json_emit_text
  fi
  [ "$READY" = true ] || exit 3
  exit 0
}

refuse() {
  READY=false
  REASON="$1"
  finish
}

tail_of() { printf '%s' "$1" | tail -n "$MAX_OUTPUT_LINES"; }

# Marks a kind as one this environment cannot run, once, with its status.
mark_unavailable() {
  case " $UNAVAILABLE " in *" $1 "*) return 0 ;; esac
  UNAVAILABLE="${UNAVAILABLE:+$UNAVAILABLE }$1"
  case "$1" in
    lint) LINT_STATUS="unavailable" ;;
    typecheck) TYPECHECK_STATUS="unavailable" ;;
    test) TEST_STATUS="unavailable" ;;
  esac
}

add_reason() { UNAVAILABLE_REASON="${UNAVAILABLE_REASON:+$UNAVAILABLE_REASON
}$1"; }

# ── The commands, from the one reader ─────────────────────────────────────────

if ! STACK=$(bash "$SCRIPT_DIR/detect-stack.sh" --json 2>/dev/null); then
  CAUSE=$(bash "$SCRIPT_DIR/detect-stack.sh" --json 2>&1 >/dev/null | sed 's/^error: //')
  refuse "the quality-commands declaration is rejected: ${CAUSE:-detect-stack.sh failed}. Fix the file, or re-run /dev-setup:setup to rewrite it."
fi

stack_get() { printf '%s' "$STACK" | jq -r --arg k "$1" '.[$k] // empty'; }

COMMANDS_SOURCE=$(stack_get COMMANDS_SOURCE)
LINT_CMD=$(stack_get LINT_CMD)
TYPECHECK_CMD=$(stack_get TYPECHECK_CMD)
TEST_CMD=$(stack_get TEST_CMD)
PREFLIGHT_CMD=$(stack_get PREFLIGHT_CMD)

# A command the declaration says the project does not have is a decision, and
# it is reported as one.
if [ "$COMMANDS_SOURCE" = declared ]; then
  [ -n "$LINT_CMD" ] || LINT_STATUS="absent"
  [ -n "$TYPECHECK_CMD" ] || TYPECHECK_STATUS="absent"
  [ -n "$TEST_CMD" ] || TEST_STATUS="absent"
fi

if [ "$REQUIRE_DECLARED" = true ] && [ "$COMMANDS_SOURCE" != declared ]; then
  refuse "the project declares no quality commands (no .claude/quality-commands.json; COMMANDS_SOURCE=${COMMANDS_SOURCE:-unknown}), and an autonomous run starts only on declared ones. Run /dev-setup:setup: step 3b proposes the commands and writes the declaration."
fi

if [ -z "$LINT_CMD$TYPECHECK_CMD$TEST_CMD" ]; then
  if [ "$COMMANDS_SOURCE" = declared ]; then
    refuse "every quality command is declared absent: nothing could check the work. Declare at least one in .claude/quality-commands.json."
  fi
  refuse "no quality command: no .claude/quality-commands.json, and detection found none for this stack. Run /dev-setup:setup to declare them (step 3b)."
fi

# ── Is every program there? ───────────────────────────────────────────────────

# Prints the directory a command starts in and the program it starts, split by
# the unit separator: `CI=1 cd api && ./vendor/bin/pest` → `api`, `./vendor/bin/pest`.
first_program() {
  local dir="." i=0 word
  local -a words=()
  # Split on blanks whatever IFS the caller runs under: bash 3.2 expands the
  # caller's here-string with its `IFS=$'\037'` already in effect.
  local IFS=$' \t\n'
  read -r -a words <<< "$1"

  while [ "$i" -lt "${#words[@]}" ] && [[ "${words[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    i=$((i + 1))
  done

  if [ "${words[$i]:-}" = "cd" ] && [ -n "${words[$((i + 1))]:-}" ]; then
    dir="${words[$((i + 1))]}"
    case "$dir" in
      *';') dir="${dir%;}"; i=$((i + 2)) ;;
      *)
        case "${words[$((i + 2))]:-}" in
          '&&'|';') i=$((i + 3)) ;;
          *) i=$((i + 2)) ;;
        esac ;;
    esac
    while [ "$i" -lt "${#words[@]}" ] && [[ "${words[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
      i=$((i + 1))
    done
  fi

  word="${words[$i]:-}"
  dir="${dir//\"/}"; dir="${dir//\'/}"
  word="${word//\"/}"; word="${word//\'/}"
  printf '%s\037%s' "$dir" "$word"
}

# True when the program can be started. `command -v` runs in a fresh shell:
# this script's own functions would otherwise answer for a program of the same
# name.
program_found() {
  local dir="$1" word="$2" path
  [ -n "$word" ] || return 1
  case "$word" in
    */*)
      case "$word" in
        /*) path="$word" ;;
        *) case "$dir" in /*) path="$dir/$word" ;; *) path="$ROOT/$dir/$word" ;; esac ;;
      esac
      [ -f "$path" ] && [ -x "$path" ] ;;
    *) bash -c 'command -v "$1"' _ "$word" >/dev/null 2>&1 ;;
  esac
}

for KIND in lint typecheck test; do
  case "$KIND" in
    lint) CMD="$LINT_CMD" ;;
    typecheck) CMD="$TYPECHECK_CMD" ;;
    test) CMD="$TEST_CMD" ;;
  esac
  [ -n "$CMD" ] || continue
  IFS=$'\037' read -r START PROGRAM <<< "$(first_program "$CMD")"
  if ! program_found "$START" "$PROGRAM"; then
    MISSING="${MISSING:+$MISSING
}$KIND: ${PROGRAM:-(none)}"
    if [ "$ALLOW_UNAVAILABLE" = true ]; then
      mark_unavailable "$KIND"
      add_reason "$KIND: \`${PROGRAM:-(none)}\` is not installed in this environment"
    fi
  fi
done

if [ -n "$MISSING" ] && [ "$ALLOW_UNAVAILABLE" != true ]; then
  refuse "a quality command starts a program this environment does not have — $(printf '%s' "$MISSING" | tr '\n' ';' | sed 's/;/; /g'). Install it, or fix the command in .claude/quality-commands.json."
fi

# ── The declared preflight ────────────────────────────────────────────────────

if [ -n "$PREFLIGHT_CMD" ]; then
  PREFLIGHT_OUT=$(bash -c "$PREFLIGHT_CMD" 2>&1)
  PREFLIGHT_RC=$?
  if [ "$PREFLIGHT_RC" -ne 0 ]; then
    PREFLIGHT="failed"
    OUTPUT=$(tail_of "$PREFLIGHT_OUT")
    [ "$ALLOW_UNAVAILABLE" = true ] || \
      refuse "the declared preflight failed (exit $PREFLIGHT_RC): $PREFLIGHT_CMD"
    # The preflight speaks for the environment, not for one command: when it
    # says the toolchain is not here, none of the declared commands can run.
    [ -z "$LINT_CMD" ] || mark_unavailable lint
    [ -z "$TYPECHECK_CMD" ] || mark_unavailable typecheck
    [ -z "$TEST_CMD" ] || mark_unavailable test
    add_reason "the declared preflight failed (exit $PREFLIGHT_RC): $PREFLIGHT_CMD"
  else
    PREFLIGHT="passed"
  fi
fi

# ── --run: a declared command is an executed command ──────────────────────────

if [ "$RUN" = true ]; then
  NOT_STARTED=""
  for KIND in lint typecheck test; do
    case "$KIND" in
      lint) CMD="$LINT_CMD" ;;
      typecheck) CMD="$TYPECHECK_CMD" ;;
      test) CMD="$TEST_CMD" ;;
    esac
    [ -n "$CMD" ] || continue
    case " $UNAVAILABLE " in *" $KIND "*) continue ;; esac

    CMD_OUT=$(bash -c "$CMD" 2>&1)
    CMD_RC=$?
    case "$CMD_RC" in
      0) STATUS="passed" ;;
      126|127) STATUS="not-found"; NOT_STARTED="${NOT_STARTED:+$NOT_STARTED, }$KIND ($CMD)" ;;
      *) STATUS="failed" ;;
    esac
    if [ "$STATUS" != passed ]; then
      OUTPUT="${OUTPUT:+$OUTPUT
}--- $KIND: $CMD (exit $CMD_RC)
$(tail_of "$CMD_OUT")"
    fi

    case "$KIND" in
      lint) LINT_STATUS="$STATUS" ;;
      typecheck) TYPECHECK_STATUS="$STATUS" ;;
      test) TEST_STATUS="$STATUS" ;;
    esac
  done

  if [ -n "$NOT_STARTED" ]; then
    refuse "a quality command did not start (exit 126/127): $NOT_STARTED. Fix it in .claude/quality-commands.json."
  fi
fi

finish
