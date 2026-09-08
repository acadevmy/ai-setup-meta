#!/usr/bin/env bash
# gate-commit.sh — PreToolUse gate on `git commit`.
#
# The "run the tests before committing" rule used to be prose in a skill, which
# means it held only while the model chose to follow it. Here it is a mechanism:
# the hook runs, and a failure denies the tool call.
#
# Adaptive (decision 9). Two modes, picked from what the project already owns:
#
#   anti-bypass — the project has a hook manager (husky, lefthook,
#     simple-git-hooks, a custom core.hooksPath). Its own tooling already runs
#     the per-commit checks on the staged files, usually far faster than a full
#     suite. This hook then only refuses the attempts to go around that tooling,
#     and runs no check of its own: no double execution.
#
#   full gate — no hook manager. This hook runs LINT_CMD, TYPECHECK_CMD and
#     TEST_CMD as reported by detect-stack.sh, and denies with the tail of the
#     real output as the reason.
#
# The full test suite is not the per-commit gate by design: it belongs at the MR
# boundary (the workflow's verify phase) and in CI, which stays the final gate.
#
# Fail-open: when the hook cannot do its job (no jq, detect-stack.sh missing) it
# warns on stderr and lets the call through. The deny rules in settings.json
# cover `--no-verify`/`-n` at the permission layer regardless of this hook, and
# CI is the backstop — a quality gate that blocks every commit on a broken
# toolchain would be worse than one that reports it.

set -uo pipefail

# ── Locate the plugin scripts ─────────────────────────────────────────────────
#
# The layout differs between the source template (.claude/hooks + .claude/scripts)
# and the built plugin (hooks/scripts + scripts). Both are resolved here so the
# hook is testable in place.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR=""

for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts" \
  "$HOOK_DIR/../../scripts" \
  "$HOOK_DIR/../scripts"; do
  if [ -f "$CANDIDATE/detect-stack.sh" ]; then
    SCRIPTS_DIR="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done

# ── Read the hook payload ─────────────────────────────────────────────────────

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "gate-commit: jq not found, commit gate skipped" >&2
  exit 0
fi

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Only Bash calls carry a command to inspect.
[ "$TOOL_NAME" = "Bash" ] || exit 0
[ -n "$COMMAND" ] || exit 0

# ── Is this a commit? ─────────────────────────────────────────────────────────
#
# Matches `git commit`, and `git <global flags> commit` (which is how a
# core.hooksPath override is smuggled in). A command that merely mentions the
# word commit (`git log --format=%H`, `echo commit`) must not trigger the gate.

is_git_commit() {
  printf '%s' "$1" | grep -Eq '(^|[;&|]|&&|\|\|)[[:space:]]*(env[[:space:]]+[^;&|]*)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+commit([[:space:]]|$)'
}

is_git_commit "$COMMAND" || exit 0

# ── Deny helper ───────────────────────────────────────────────────────────────

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# ── Anti-bypass (both modes) ──────────────────────────────────────────────────
#
# Skipping the hooks is the one way a red suite reaches a commit anyway, so the
# attempt is refused whichever mode is active.
#
# The scan runs on the command with every quoted string removed: a commit
# message is free text, and `-m "disable HUSKY=0 fallback"` must not read as an
# attempt to set it.

strip_quoted() {
  printf '%s' "$1" | sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g'
}

SCAN=$(strip_quoted "$COMMAND")

BYPASS_REASON=""

case " $SCAN " in
  *--no-verify*)  BYPASS_REASON="the commit skips the git hooks (--no-verify)" ;;
  *" -n "*)       BYPASS_REASON="the commit skips the git hooks (-n)" ;;
esac

if [ -z "$BYPASS_REASON" ]; then
  case "$SCAN" in
    *HUSKY=0*)                 BYPASS_REASON="HUSKY=0 disables the project's husky hooks" ;;
    *LEFTHOOK=0*)              BYPASS_REASON="LEFTHOOK=0 disables the project's lefthook hooks" ;;
    *SKIP_SIMPLE_GIT_HOOKS=1*) BYPASS_REASON="SKIP_SIMPLE_GIT_HOOKS=1 disables the project's git hooks" ;;
    *core.hooksPath*)          BYPASS_REASON="the commit redirects core.hooksPath, disabling the project's hooks" ;;
    *GIT_CONFIG_COUNT*|*GIT_CONFIG_KEY*) BYPASS_REASON="the commit injects git config through GIT_CONFIG_* to alter the hooks" ;;
    *LEFTHOOK_EXCLUDE*)        BYPASS_REASON="LEFTHOOK_EXCLUDE skips part of the project's hooks" ;;
  esac
fi

if [ -n "$BYPASS_REASON" ]; then
  deny "Commit refused: $BYPASS_REASON.

The project's quality gate is not optional. Fix what the hooks report, then
commit normally. If a hook is itself broken, say so and fix the hook — do not
work around it."
fi

# ── Stack detection ───────────────────────────────────────────────────────────

if [ -z "$SCRIPTS_DIR" ]; then
  echo "gate-commit: detect-stack.sh not found, commit gate skipped" >&2
  exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$REPO_ROOT" ] || exit 0
cd "$REPO_ROOT" || exit 0

STACK=$(bash "$SCRIPTS_DIR/detect-stack.sh" --json 2>/dev/null || true)
if [ -z "$STACK" ]; then
  echo "gate-commit: stack detection failed, commit gate skipped" >&2
  exit 0
fi

stack_get() { printf '%s' "$STACK" | jq -r --arg k "$1" '.[$k] // empty'; }

HOOK_MANAGER=$(stack_get HOOK_MANAGER)

# ── Mode: anti-bypass ─────────────────────────────────────────────────────────
#
# The project's own tooling owns the per-commit checks. Nothing more to run.

if [ -n "$HOOK_MANAGER" ]; then
  echo "gate-commit: $HOOK_MANAGER detected, per-commit checks delegated to the project" >&2
  exit 0
fi

# ── Mode: full gate ───────────────────────────────────────────────────────────

LINT_CMD=$(stack_get LINT_CMD)
TYPECHECK_CMD=$(stack_get TYPECHECK_CMD)
TEST_CMD=$(stack_get TEST_CMD)

# Nothing staged and no --amend/--all: git itself will refuse the commit, so
# there is no point paying for a suite run first.
case "$SCAN" in
  *--amend*|*--all*|*" -a "*) ;;
  *)
    if git diff --cached --quiet 2>/dev/null; then
      echo "gate-commit: nothing staged, gate skipped" >&2
      exit 0
    fi
    ;;
esac

if [ -z "$LINT_CMD" ] && [ -z "$TYPECHECK_CMD" ] && [ -z "$TEST_CMD" ]; then
  echo "gate-commit: no quality command detected for this stack, nothing to gate" >&2
  exit 0
fi

# Keeps the reason readable: the tail is where a runner puts the failure summary.
MAX_OUTPUT_LINES=40

run_check() {
  local label="$1" cmd="$2" output status
  [ -n "$cmd" ] || return 0

  output=$(eval "$cmd" 2>&1)
  status=$?

  if [ "$status" -ne 0 ]; then
    deny "Commit refused: $label failed.

Command: $cmd
Exit code: $status

$(printf '%s' "$output" | tail -n "$MAX_OUTPUT_LINES")

Fix the failures above and commit again. Do not skip the gate."
  fi
  return 0
}

run_check "lint" "$LINT_CMD"
run_check "type check" "$TYPECHECK_CMD"
run_check "tests" "$TEST_CMD"

echo "gate-commit: lint, type check and tests green" >&2
exit 0
