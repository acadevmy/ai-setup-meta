#!/usr/bin/env bash
# notify.sh — Notification hook on `permission_prompt` (DE-17077).
#
# A flow of this plugin that needs the developer reaches them through an `ask`
# rule: `gh pr create` / `glab mr create` when an autonomous run is
# ready-for-mr, the BLOCKED move when it failed. Claude Code's own notification
# says "Claude needs your permission" and not for which task — with five runs
# in flight, that tells the developer nothing. This hook sends one desktop
# notification titled `dev-setup · <TASK_IDS>`, with the prompt's message as
# the body.
#
# The clocks are the noise filter, the branch only narrows. A candidate is a
# task whose work clock is open in this repository, or was stopped less than
# five minutes ago (a failed run stops its clock, then asks for the BLOCKED
# move): `task-clock.sh --status`, the reader that consumes nothing, reports
# both. No candidate, nothing to say — whatever the branch is called, since
# every tracked branch carries an id and a branch alone is not a task in play.
# The built-in notification stays the only one there. When the branch of the
# payload's cwd names one of the candidates, the title carries that one;
# otherwise it carries them all — the payload does not say which run is asking,
# and guessing would be worse than naming the set.
#
# Only `permission_prompt`. `agent_needs_input` and `agent_completed` come from
# the agent view, already named after the session (session-title.sh sets that
# name), and run in the agent view's cwd, where a branch or a clock could only
# name the wrong task. `idle_prompt` and the rest carry no decision.
#
# Delivery is the OS notifier, chosen by `uname -s`: `osascript` on Darwin, with
# the title and the body passed as argv — never interpolated into the script,
# so a message with quotes cannot break or inject into the AppleScript — and
# `notify-send` on Linux. No bell: a hook's stdio is piped to the harness, and
# ringing the terminal is what `preferredNotifChannel: "terminal_bell"` does.
#
# It fails open and prints nothing on stdout: a Notification hook has no
# decision control, so its whole effect is the side effect. No `jq`, no plugin
# scripts, a cwd outside a repository, an unsupported OS, a notifier missing or
# failing — exit 0, at most one diagnostic line on stderr.

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
  if [ -f "$CANDIDATE/task-clock.sh" ] && [ -f "$CANDIDATE/common.sh" ]; then
    SCRIPTS_DIR="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done

# ── Read the hook payload ─────────────────────────────────────────────────────

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "notify: jq not found, notification skipped" >&2
  exit 0
fi

NOTIFICATION_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
[ "$NOTIFICATION_TYPE" = "permission_prompt" ] || exit 0

MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# ── Is a task of this plugin in play here? ────────────────────────────────────

[ -n "$SCRIPTS_DIR" ] || exit 0
# shellcheck source=../scripts/common.sh
source "$SCRIPTS_DIR/common.sh"

if [ -n "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

STATUS=$(bash "$SCRIPTS_DIR/task-clock.sh" --status --json 2>/dev/null || true)
[ -n "$STATUS" ] || exit 0

CANDIDATES=$(printf '%s' "$STATUS" \
  | jq -r '[(.OPEN_TASKS // ""), (.RECENT_TASKS // "")] | map(select(. != "")) | join(" ")' \
  2>/dev/null || true)
[ -n "$CANDIDATES" ] || exit 0

# ── Which task is asking? ─────────────────────────────────────────────────────
#
# The id the branch carries, compared whole with each candidate: with DE-81 and
# DE-811 both in play, a branch named after the second never names the first.

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
BRANCH_TASK=$(branch_task_id "$BRANCH")

TASK_IDS="$CANDIDATES"
if [ -n "$BRANCH_TASK" ]; then
  for CANDIDATE in $CANDIDATES; do
    if [ "$CANDIDATE" = "$BRANCH_TASK" ]; then
      TASK_IDS="$CANDIDATE"
      break
    fi
  done
fi

TITLE="dev-setup · $TASK_IDS"

# ── Deliver it ────────────────────────────────────────────────────────────────

case "$(uname -s 2>/dev/null)" in
  Darwin)
    command -v osascript >/dev/null 2>&1 || exit 0
    osascript \
      -e 'on run argv' \
      -e 'display notification (item 2 of argv) with title (item 1 of argv)' \
      -e 'end run' \
      "$TITLE" "$MESSAGE" >/dev/null 2>&1 \
      || echo "notify: osascript failed, notification skipped" >&2
    ;;
  Linux)
    command -v notify-send >/dev/null 2>&1 || exit 0
    notify-send "$TITLE" "$MESSAGE" >/dev/null 2>&1 \
      || echo "notify: notify-send failed, notification skipped" >&2
    ;;
esac

exit 0
