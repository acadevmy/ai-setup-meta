#!/usr/bin/env bash
# session-title.sh — SessionStart (startup|resume) and UserPromptSubmit hook:
# the session is named after its task (DE-17077).
#
# `claude --resume` lists sessions by their first prompt, and the agent view
# names a background session after its title. A session working on DE-123 is
# easier to find as `DE-123 add-user-auth` than as the first thing typed in it,
# so this hook answers `sessionTitle: "<TASK_ID> <slug>"` — read from git, never
# from the board: a hook has no board access and must not get any. The slug is
# the branch text after the id and its delimiter, in English, as `sdd-start.sh`
# wrote it.
#
# Two events, because the common path cuts the branch mid-session:
#   - SessionStart, `startup` or `resume`: the branch of the payload's cwd. A
#     session opened or resumed on a task branch is titled at once.
#   - UserPromptSubmit: only the prompt that launches a single-task flow,
#     `/dev-setup:sdd|quick|auto-sdd <TASK_ID>`. The session opened on `next`
#     has run SessionStart already; this is the one moment it says which task
#     it is about. The title takes the slug of a local branch carrying the id,
#     or is the id alone. `/dev-setup:multi-sdd` is not one task, and five ids
#     do not make a name.
#
# A title the developer chose is never overwritten. `session_title` in the
# payload is the current one: one that does not start with a task id is theirs,
# and the hook stays silent; one that does is this hook's own earlier answer,
# replaced when it differs and left alone when it is already right.
#
# It stays quiet unless there is something to say and fails open: no task id,
# no `jq`, no plugin scripts, a cwd outside a repository — exit 0 with an empty
# stdout. It writes no state and never exits 2.

set -uo pipefail

TASK_ID_RE='[A-Z][A-Z0-9]*-[0-9]+'
# Held in variables: a regex with a space or a `|` cannot be written inline
# after `=~`, and a quoted one would match literally.
LAUNCH_RE="^/dev-setup:(sdd|quick|auto-sdd)[[:space:]]+($TASK_ID_RE)([^A-Za-z0-9]|\$)"
OWN_TITLE_RE="^$TASK_ID_RE( |\$)"

# ── Read the hook payload ─────────────────────────────────────────────────────

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "session-title: jq not found, session title skipped" >&2
  exit 0
fi

field() { printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty | tostring' 2>/dev/null; }

EVENT=$(field hook_event_name)
CURRENT_TITLE=$(field session_title)
HOOK_CWD=$(field cwd)

PROMPT_TASK=""
case "$EVENT" in
  SessionStart)
    case "$(field source)" in
      startup|resume) ;;
      *) exit 0 ;;
    esac
    ;;
  UserPromptSubmit)
    # The cheap filter first: this event fires on every prompt.
    PROMPT=$(field prompt)
    [[ "$PROMPT" =~ $LAUNCH_RE ]] || exit 0
    PROMPT_TASK="${BASH_REMATCH[2]}"
    ;;
  *) exit 0 ;;
esac

# A title that is not a task id is the developer's: nothing to do, whatever the
# branch says.
if [ -n "$CURRENT_TITLE" ] && ! [[ "$CURRENT_TITLE" =~ $OWN_TITLE_RE ]]; then
  exit 0
fi

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
  if [ -f "$CANDIDATE/common.sh" ]; then
    SCRIPTS_DIR="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done

[ -n "$SCRIPTS_DIR" ] || exit 0
# shellcheck source=../scripts/common.sh
source "$SCRIPTS_DIR/common.sh"

if [ -n "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# The branch text after the task id and its delimiter:
# feat(auth)/DE-123_add-user-auth -> add-user-auth, feat/DE-123-add-x -> add-x.
branch_slug() {
  printf '%s' "$1" \
    | sed -nE 's#^[a-z]+(\([a-z0-9-]+\))?/[A-Z][A-Z0-9]*-[0-9]+[_-](.+)$#\2#p'
}

# ── The title ─────────────────────────────────────────────────────────────────

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
TASK=""
SLUG=""

if [ "$EVENT" = "SessionStart" ]; then
  TASK=$(branch_task_id "$BRANCH")
  [ -n "$TASK" ] || exit 0
  SLUG=$(branch_slug "$BRANCH")
else
  TASK="$PROMPT_TASK"
  # The checked-out branch first, then any local branch carrying the id.
  while IFS= read -r CANDIDATE; do
    if [ "$(branch_task_id "$CANDIDATE")" = "$TASK" ]; then
      SLUG=$(branch_slug "$CANDIDATE")
      break
    fi
  done <<EOF
$BRANCH
$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
EOF
fi

TITLE="$TASK${SLUG:+ $SLUG}"

[ "$CURRENT_TITLE" != "$TITLE" ] || exit 0

jq -n --arg event "$EVENT" --arg title "$TITLE" \
  '{hookSpecificOutput: {hookEventName: $event, sessionTitle: $title}}'
exit 0
