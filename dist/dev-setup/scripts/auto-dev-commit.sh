#!/usr/bin/env bash
# auto-dev-commit.sh — the one commit of an auto-dev run, when this environment
# cannot start some of the project's quality commands.
#
# auto-dev-args.sh marks a declared command `unavailable` when its program is
# not installed here, and the run goes on: the merge request lists the checks
# nobody ran. The commit gate does not know that list. In full-gate mode it runs
# every declared command, the missing program exits 127, and the commit is
# refused however good the work is: on job ad-dry-10281136 (a Flutter app, a
# host with no dart) the run ended with its work staged and nothing on the
# branch.
#
# This script is that gate minus what cannot start, and nothing more:
#
#   - it asks quality-preflight.sh itself which commands cannot run here — the
#     list in the run's arguments is not trusted;
#   - it refuses when nothing is unavailable, and when the project has a hook
#     manager: there `git commit` works, and the gate runs as it always does;
#   - it refuses on a branch that does not carry --task;
#   - it runs every other declared command, and a red one refuses the commit
#     with the tail of its output, as the gate would;
#   - it commits with `git commit`, the project's own git hooks running — never
#     --no-verify, never a hook override.
#
# Usage:
#   auto-dev-commit.sh --task <id> --message <subject> [--json]
#
#   --task <id>        the task id the branch carries (DE-123)
#   --message <text>   the commit subject: Conventional Commits, with the task id
#   --json             emit a flat JSON object
#
# Stages everything first (`git add -A`), as the run's one commit does.
#
# Keys:
#   COMMITTED           true when the commit was made
#   COMMIT              its hash — empty otherwise
#   BRANCH              the branch
#   RAN                 the kinds that ran, all green (`lint typecheck`)
#   SKIPPED             the kinds this environment cannot run: not run
#   UNAVAILABLE_REASON  why, one line per cause — what the merge request says
#   OUTPUT              the tail of what refused the commit: a red command, git
#   REASON              why there is no commit — empty when COMMITTED is true
#
# Exit: 0 committed · 4 not committed: a command is red, or git refused the
# commit (OUTPUT holds it) — fix it and run again · 3 refused: nothing is
# unavailable, a hook manager, not the task's branch, nothing to commit — the
# keys still print, with REASON · 1 usage error, or not a git working tree
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
TASK=""
MESSAGE=""

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
    --message) need_value "$1" $# "${2-}"; MESSAGE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

# ── Arguments ─────────────────────────────────────────────────────────────────

[ -n "$TASK" ] || die "--task is required"
printf '%s' "$TASK" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' \
  || die "--task \"$TASK\" is not a plain identifier"
[ -n "$(printf '%s' "$MESSAGE" | tr -d '[:space:]')" ] || die "--message is required: the commit subject"
case "$MESSAGE" in
  *"$TASK"*) ;;
  *) die "--message has to carry the task id $TASK" ;;
esac

require_jq

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git working tree"
cd "$ROOT" || die "cannot enter $ROOT"

BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
RAN=""
SKIPPED=""
UNAVAILABLE_REASON=""
OUTPUT=""

emit() {
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
}

set_keys() {
  json_set COMMITTED "$1"
  json_set COMMIT "${2-}"
  json_set BRANCH "$BRANCH"
  json_set RAN "$RAN"
  json_set SKIPPED "$SKIPPED"
  json_set UNAVAILABLE_REASON "$UNAVAILABLE_REASON"
  json_set OUTPUT "$OUTPUT"
  json_set REASON "${3-}"
}

# $1 exit status, $2 the reason.
stop() {
  set_keys false "" "$2"
  emit
  exit "$1"
}

# ── The narrow case ───────────────────────────────────────────────────────────

[ "$(branch_task_id "$BRANCH")" = "$TASK" ] \
  || stop 3 "the branch ${BRANCH:-(detached HEAD)} does not carry $TASK: this script commits on the task's own branch only"

STACK="$(bash "$SCRIPT_DIR/detect-stack.sh" --json 2>/dev/null)" \
  || stop 3 "detect-stack.sh rejects the project's quality-commands declaration: commit with git commit, and read what the gate says"
HOOK_MANAGER="$(printf '%s' "$STACK" | jq -r '.HOOK_MANAGER // ""')"
[ -z "$HOOK_MANAGER" ] \
  || stop 3 "the project runs its own checks through $HOOK_MANAGER, and the commit gate leaves them to it: commit with git commit"

PRE="$(bash "$SCRIPT_DIR/quality-preflight.sh" --require-declared --allow-unavailable --json 2>/dev/null)"
PRE_STATUS=$?
pre_get() { printf '%s' "$PRE" | jq -r --arg k "$1" '.[$k] // ""'; }
[ "$PRE_STATUS" -eq 0 ] || stop 3 "quality-preflight.sh refuses: $(pre_get REASON)"
SKIPPED="$(pre_get UNAVAILABLE)"
UNAVAILABLE_REASON="$(pre_get UNAVAILABLE_REASON)"
[ -n "$SKIPPED" ] \
  || stop 3 "every declared command can run here: commit with git commit, and the commit gate runs them"

git add -A || die "git add -A failed"
if git diff --cached --quiet; then
  stop 3 "nothing to commit: the working tree matches HEAD"
fi

# ── The gate, minus what cannot start ─────────────────────────────────────────
#
# quality-preflight.sh --run runs each declared command once, from the
# repository root, and skips the unavailable ones — the same commands the gate
# reads from detect-stack.sh.

PRE="$(bash "$SCRIPT_DIR/quality-preflight.sh" --require-declared --allow-unavailable --run --json 2>/dev/null)"
PRE_STATUS=$?
OUTPUT="$(pre_get OUTPUT)"
[ "$PRE_STATUS" -eq 0 ] || stop 3 "quality-preflight.sh refuses: $(pre_get REASON)"

RED=""
for KIND in lint typecheck test; do
  KEY="$(printf '%s' "$KIND" | tr '[:lower:]' '[:upper:]')_STATUS"
  case "$(pre_get "$KEY")" in
    passed) RAN="${RAN:+$RAN }$KIND" ;;
    failed) RED="${RED:+$RED, }$KIND" ;;
  esac
done
[ -z "$RED" ] || stop 4 "not committed: $RED failed — fix what OUTPUT shows and run this again"

# ── The commit ────────────────────────────────────────────────────────────────

COMMIT_OUT="$(git commit --quiet -m "$MESSAGE" 2>&1)"
COMMIT_STATUS=$?
if [ "$COMMIT_STATUS" -ne 0 ]; then
  OUTPUT="$(printf '%s' "$COMMIT_OUT" | tail -n 40)"
  stop 4 "not committed: git commit exited $COMMIT_STATUS — a project git hook, most likely; OUTPUT holds what it said"
fi

OUTPUT=""
set_keys true "$(git rev-parse HEAD)" ""
emit
exit 0
