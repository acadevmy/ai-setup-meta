#!/usr/bin/env bash
# post-merge-request.sh — PostToolUse hook on `gh pr create` / `glab mr create`.
#
# Every flow here ends with the same two calls: stop the task's work clock, and
# move the task to CODE REVIEW. Both live in the closure step of the skill that
# opened the merge request — which is fine right up to the moment the merge
# request is opened by something else.
#
# That moment is not hypothetical. On DE-16879 the push failed (the remote was
# still empty), the session was cleared, and the branch was pushed and the pull
# request opened later through `vcs-ops` alone. `vcs-ops` knows nothing about a
# board or a clock, so the task stayed IN PROGRESS with its clock running and
# nothing anywhere said otherwise: the obligation had been carried in the
# context of a flow, and the context was gone.
#
# So it is carried by the event instead. Whatever opened the merge request, in
# whatever session, this hook fires on the command that created it and says
# what is left to do.
#
# It reports and it does not mutate: `--status` reads the clock, `--stop` is the
# measurement and belongs to the caller that posts it. A hook that stopped the
# clock itself would hand the duration to a session that may never post it, and
# the flow's own `--stop` would then find nothing to report.
#
# It stays quiet unless there is something to say: no merge request created (no
# URL in the output), no clock open in this repository, no `jq` — exit 0,
# silently. An open clock means a flow of this plugin moved a task to
# IN PROGRESS here, which is the only case where the board is waiting.
#
# Exit 2 is the channel, not a verdict on the command: on PostToolUse it is
# what puts the message in front of the model (stdout there reaches the debug
# log only). The merge request was created and stays created.

set -uo pipefail

# ── Locate the plugin scripts ─────────────────────────────────────────────────
#
# Same three candidates as the other hooks: the plugin root when the harness
# exports it, then the source template layout, then the built one.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR=""

for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts" \
  "$HOOK_DIR/../../scripts" \
  "$HOOK_DIR/../scripts"; do
  if [ -f "$CANDIDATE/task-clock.sh" ]; then
    SCRIPTS_DIR="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done

# ── Read the hook payload ─────────────────────────────────────────────────────

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "post-merge-request: jq not found, board reminder skipped" >&2
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
# The session's working directory: in a worktree it is the worktree root, while
# $CLAUDE_PROJECT_DIR stays at the main checkout. The clock is shared between
# them (it lives in the common git directory), but the branch is not.
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
# Bash returns an object on some versions and a string on others; both are only
# ever searched for a URL.
RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response // empty | if type == "string" then . else tojson end')

[ "$TOOL_NAME" = "Bash" ] || exit 0
[ -n "$COMMAND" ] || exit 0

# ── Is this a merge request being opened? ─────────────────────────────────────
#
# The scan runs on the command with every quoted string removed: a pull request
# body explaining how to run `gh pr create` must not read as one.

strip_quoted() {
  printf '%s' "$1" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g'
}

SCAN=$(strip_quoted "$COMMAND")

printf '%s' "$SCAN" | grep -Eq '(^|[;&|]|&&|\|\|)[[:space:]]*(env[[:space:]]+[^;&|]*)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(gh[[:space:]]+pr|glab[[:space:]]+mr)([[:space:]]+-[^[:space:]]+)*[[:space:]]+create([[:space:]]|$)' \
  || exit 0

# ── Did it create one? ────────────────────────────────────────────────────────
#
# The URL the command printed is the proof, and it is also what the message
# quotes back. No URL: the call failed, or it only opened a browser — either
# way there is nothing to close yet.

MR_URL=$(printf '%s' "$RESPONSE" \
  | grep -Eo 'https://[^[:space:]"'"'"'\\]+/(pull|merge_requests)/[0-9]+' \
  | head -1)

[ -n "$MR_URL" ] || exit 0

# ── Is a task still in progress here? ─────────────────────────────────────────

[ -n "$SCRIPTS_DIR" ] || exit 0

if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" || exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

STATUS=$(bash "$SCRIPTS_DIR/task-clock.sh" --status --json 2>/dev/null || true)
[ -n "$STATUS" ] || exit 0

OPEN_TASKS=$(printf '%s' "$STATUS" | jq -r '.OPEN_TASKS // empty')
[ -n "$OPEN_TASKS" ] || exit 0

# ── Which task is this merge request closing? ─────────────────────────────────
#
# One open clock is the answer. With several — a fan-out shares the common git
# directory across its worktrees — the branch and the merge request title carry
# the id, and whichever of the open ones they name wins. If nothing names one,
# they are all reported and the caller picks: guessing would move the wrong task.

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# Matched between delimiters, never as a bare substring: with DE-81 and DE-811
# both open, a branch named after the second one must not close the first.
TASK=""
for CANDIDATE in $OPEN_TASKS; do
  if printf '%s' "$BRANCH $COMMAND" \
     | grep -qE "(^|[^A-Za-z0-9])$(printf '%s' "$CANDIDATE" | sed 's/[.[\*^$\/]/\\&/g')([^A-Za-z0-9]|$)"; then
    TASK="$CANDIDATE"
    break
  fi
done

if [ -z "$TASK" ]; then
  set -- $OPEN_TASKS
  [ $# -eq 1 ] && TASK="$1"
fi

CLOCK_CMD="bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh\""
CONTRACT='${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md'

# ── The reminder ──────────────────────────────────────────────────────────────

if [ -z "$TASK" ]; then
  printf 'post-merge-request: %s is open, and these tasks still have a work clock running here: %s.

The flow is not finished for the one this merge request closes. For that task:
  1. %s --task <id> --stop --json
  2. move it to CODE REVIEW (IN REVIEW where the list has no CODE REVIEW) with
     COMMENT as the comment, verbatim — the clickup agent, per
     %s
Do not guess which one: if the merge request does not say, ask.
' "$MR_URL" "$OPEN_TASKS" "$CLOCK_CMD" "$CONTRACT" >&2
  exit 2
fi

STARTED_AT=$(bash "$SCRIPTS_DIR/task-clock.sh" --task "$TASK" --status --json 2>/dev/null \
  | jq -r '.STARTED_AT // empty' 2>/dev/null || true)

printf 'post-merge-request: %s is open, and %s is still IN PROGRESS%s.

The flow is not finished. Two calls, now, in this turn:
  1. %s --task %s --stop --json
  2. move %s to CODE REVIEW (IN REVIEW where the list has no CODE REVIEW) with
     COMMENT as the comment, verbatim — the clickup agent, per
     %s
An empty COMMENT means the clock has nothing to report: move the task anyway,
and say so in one line. Never write a duration yourself.
' "$MR_URL" "$TASK" "${STARTED_AT:+ — its work clock has been running since $STARTED_AT}" \
  "$CLOCK_CMD" "$TASK" "$TASK" "$CONTRACT" >&2

exit 2
