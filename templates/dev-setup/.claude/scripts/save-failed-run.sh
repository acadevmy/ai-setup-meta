#!/usr/bin/env bash
# save-failed-run.sh — a failed run's work, committed and pushed past the gates.
#
# A failed auto-sdd run in a cloud session — a scheduled routine among them —
# loses everything it did when the session ends: on DE-17159 the branch stayed
# local and the board comment was the only trace. Saving it means a commit and
# a push, and the project's gates refuse both: its commands are red, which is
# why the run failed, and a pre-push hook running the suite refuses the push
# the same way. So this script commits and pushes past the project's hooks,
# and says so.
#
# The exception is narrow, and this script is what keeps it narrow — the
# `deny` rules on `--no-verify` and the anti-bypass mode of gate-commit.sh still
# refuse every other way around the gate:
#
#   - only in an ephemeral session: CLAUDE_CODE_REMOTE=true, or it refuses;
#   - only the task's own branch: a branch that carries --task as its task id,
#     never a base branch, and never a force push;
#   - only with a reason: the commit message is fixed, names the stage, says
#     the hooks were skipped, and carries the reason file verbatim — why the run
#     failed and what is missing. A commit that skipped the checks never looks
#     like one that passed them.
#
# What it saves, in order of what exists:
#
#   1. --dir, or else the worktree whose branch carries the task: everything
#      in it is committed (`git add -A`) — an empty commit when it holds nothing,
#      so the pushed branch itself says why the run failed;
#   2. else a local branch that carries the task, with no worktree: an empty
#      commit on it holding the reason, made without a checkout;
#   3. else, with --spec-file, a new branch from --base holding the spec — the
#      run wrote and argued it, and that work is what would be lost;
#   4. else nothing: it refuses, and the board note is the whole report.
#
# Usage:
#   save-failed-run.sh --task <id> --stage <stage> --reason-file <path>
#                      [--dir <worktree>]
#                      [--spec-file <path> --spec-path <path> --base <ref>
#                       --title <english title> [--type <type>]]
#                      [--remote <name>] [--json]
#
#   --task <id>          the task id the run's branch carries (DE-123)
#   --stage <stage>      where the run failed: spec, dev, verify, or broken
#                        (the workflow returned no outcome)
#   --reason-file <path> why it failed and what is missing, as plain text; `-`
#                        reads it from standard input. Required, and not empty
#   --dir <worktree>     the run's worktree — the outcome's `worktreePath`.
#                        Default: found from the task id
#   --spec-file <path>   the spec text, when no branch exists yet (case 3)
#   --spec-path <path>   where the spec goes in the repository (.specs/…)
#   --base <ref>         the fork point of the new branch — the run's baseBranch
#   --title <text>       the task title in English, for the branch name
#   --type <type>        the branch type (default: feat)
#   --remote <name>      the remote to push to (default: origin)
#   --json               emit a flat JSON object
#
# Keys:
#   SAVED       true when the commit was made
#   COMMIT      the commit it made — empty when refused
#   BRANCH      the branch it saved
#   WORKTREE    the worktree it committed in — empty for a commit without one
#   CREATED     true when the branch was created here from --spec-file
#   FILES       files the commit carries; 0 is an empty commit holding the reason
#   PUSHED      true when the branch reached the remote
#   REMOTE      the remote it pushed to
#   PUSH_ERROR  the tail of the push's own error — empty when PUSHED is true
#   REASON      why it refused — empty when SAVED is true
#
# Exit: 0 saved and pushed · 4 saved, not pushed (PUSH_ERROR says why) ·
# 3 refused — not an ephemeral session, or nothing carries the task — the keys
# still print, with REASON · 1 usage error, an empty reason, or a git failure —
# nothing is printed on stdout
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
TASK=""
STAGE=""
REASON_FILE=""
DIR=""
SPEC_FILE=""
SPEC_PATH=""
BASE=""
TITLE=""
TYPE="feat"
REMOTE="origin"

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
    --stage) need_value "$1" $# "${2-}"; STAGE="$2"; shift 2 ;;
    --reason-file) need_value "$1" $# "${2-}"; REASON_FILE="$2"; shift 2 ;;
    --dir) need_value "$1" $# "${2-}"; DIR="$2"; shift 2 ;;
    --spec-file) need_value "$1" $# "${2-}"; SPEC_FILE="$2"; shift 2 ;;
    --spec-path) need_value "$1" $# "${2-}"; SPEC_PATH="$2"; shift 2 ;;
    --base) need_value "$1" $# "${2-}"; BASE="$2"; shift 2 ;;
    --title) need_value "$1" $# "${2-}"; TITLE="$2"; shift 2 ;;
    --type) need_value "$1" $# "${2-}"; TYPE="$2"; shift 2 ;;
    --remote) need_value "$1" $# "${2-}"; REMOTE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

# ── Arguments ─────────────────────────────────────────────────────────────────

[ -n "$TASK" ] || die "--task is required"
# The same shape the workflow accepts: the id reaches a commit subject.
printf '%s' "$TASK" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' \
  || die "--task \"$TASK\" is not a plain identifier"
case "$STAGE" in
  spec|dev|verify|broken) ;;
  "") die "--stage is required: spec, dev, verify or broken" ;;
  *) die "--stage \"$STAGE\" is not spec, dev, verify or broken" ;;
esac
[ -n "$REASON_FILE" ] || die "--reason-file is required: a skipped gate has to say why"

if [ "$REASON_FILE" = "-" ]; then
  REASON_TEXT="$(cat)"
else
  [ -f "$REASON_FILE" ] || die "--reason-file \"$REASON_FILE\" does not exist"
  REASON_TEXT="$(cat "$REASON_FILE")"
fi
[ -n "$(printf '%s' "$REASON_TEXT" | tr -d '[:space:]')" ] \
  || die "the reason is empty: a skipped gate has to say why the run failed"

if [ -n "$SPEC_FILE" ]; then
  [ -f "$SPEC_FILE" ] || die "--spec-file \"$SPEC_FILE\" does not exist"
  [ -n "$SPEC_PATH" ] && [ -n "$BASE" ] && [ -n "$TITLE" ] \
    || die "--spec-file needs --spec-path, --base and --title"
  case "$SPEC_PATH" in
    /*|..|../*|*/../*|*/..) die "--spec-path \"$SPEC_PATH\" has to stay inside the repository" ;;
  esac
fi
printf '%s' "$REMOTE" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' \
  || die "--remote \"$REMOTE\" is not a remote name"

require_jq

if [ -n "$DIR" ]; then
  [ -d "$DIR" ] || die "--dir \"$DIR\" is not a directory"
  cd "$DIR" || die "cannot enter $DIR"
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git working tree"

BRANCH=""
WORKTREE=""
CREATED="false"

emit() {
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
}

set_keys() {
  json_set SAVED "$1"
  json_set COMMIT "${2-}"
  json_set BRANCH "$BRANCH"
  json_set WORKTREE "$WORKTREE"
  json_set CREATED "$CREATED"
  json_set FILES "${3:-0}"
  json_set PUSHED "${4:-false}"
  json_set REMOTE "$REMOTE"
  json_set PUSH_ERROR "${5-}"
  json_set REASON "${6-}"
}

refuse() {
  set_keys false "" 0 false "" "$1"
  emit
  exit 3
}

carries_task() {
  [ -n "$1" ] && [ "$(branch_task_id "$1")" = "$TASK" ]
}

# ── The narrow case ───────────────────────────────────────────────────────────

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] \
  || refuse "not an ephemeral session (CLAUDE_CODE_REMOTE is not true): the worktree survives here, and the gates stay"

# ── What there is to save ─────────────────────────────────────────────────────

if [ -n "$DIR" ]; then
  # 1, named: the run's worktree, and it has to be on the task's branch.
  BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$BRANCH" ] || refuse "HEAD is detached in $DIR: the run's work lives on its branch"
  carries_task "$BRANCH" \
    || refuse "branch $BRANCH does not carry the task id $TASK: only the task's own branch is saved this way"
  WORKTREE="$(git rev-parse --show-toplevel)"
else
  # 1, found: the worktree whose branch carries the task.
  CANDIDATE_TREE=""
  while IFS= read -r LINE; do
    case "$LINE" in
      "worktree "*) CANDIDATE_TREE="${LINE#worktree }" ;;
      "branch refs/heads/"*)
        if [ -z "$WORKTREE" ] && carries_task "${LINE#branch refs/heads/}"; then
          BRANCH="${LINE#branch refs/heads/}"
          WORKTREE="$CANDIDATE_TREE"
        fi
        ;;
    esac
  done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF
  # 2: a branch with no worktree, the most recent first.
  if [ -z "$BRANCH" ]; then
    while IFS= read -r CANDIDATE; do
      if carries_task "$CANDIDATE"; then BRANCH="$CANDIDATE"; break; fi
    done <<EOF
$(git for-each-ref --sort=-committerdate --format='%(refname:short)' refs/heads 2>/dev/null)
EOF
  fi
fi

# 3: no branch at all, but a spec — a branch of its own, in a worktree of its
# own, so whatever checkout the session is on is never touched.
if [ -z "$BRANCH" ] && [ -n "$SPEC_FILE" ]; then
  BRANCH="$(bash "$SCRIPT_DIR/sdd-start.sh" --task "$TASK" --type "$TYPE" --title "$TITLE" \
    --base "$BASE" --json 2>/dev/null | jq -r '.BRANCH // empty')"
  carries_task "$BRANCH" || die "sdd-start.sh named no branch for $TASK"
  git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null \
    || die "--base \"$BASE\" does not resolve to a commit"
  WORKTREE="${TMPDIR:-/tmp}/dev-setup-failed-run-$(slugify "$TASK" 64)"
  [ ! -e "$WORKTREE" ] || die "$WORKTREE already exists: remove it, or pass --dir"
  git worktree add --quiet -b "$BRANCH" "$WORKTREE" "$BASE" >/dev/null 2>&1 \
    || die "cannot create the branch $BRANCH from $BASE"
  mkdir -p "$WORKTREE/$(dirname "$SPEC_PATH")" || die "cannot create the spec directory"
  cp "$SPEC_FILE" "$WORKTREE/$SPEC_PATH" || die "cannot write the spec to $SPEC_PATH"
  CREATED="true"
fi

# 4: nothing carries the task.
[ -n "$BRANCH" ] \
  || refuse "no branch carries the task id $TASK, and no spec was given: nothing to save"

# ── The commit ────────────────────────────────────────────────────────────────

MESSAGE="$(printf '%s\n\n%s\n%s\n%s\n\n%s\n' \
  "chore: save the unfinished work of a failed run [$TASK]" \
  "The auto-sdd run failed at the $STAGE stage, in a cloud session whose disk" \
  "goes when it ends. This commit and its push skipped the project's hooks on" \
  "purpose so the work survives the session: nothing in it was checked." \
  "$REASON_TEXT")"

OLD="$(git rev-parse --verify --quiet "refs/heads/$BRANCH")" || die "branch $BRANCH has no commit"

if [ -n "$WORKTREE" ]; then
  git -C "$WORKTREE" add -A || die "git add failed in $WORKTREE"
  FILES="$(git -C "$WORKTREE" diff --cached --name-only | grep -c . || true)"
  # Every hook path at once: --no-verify skips pre-commit and commit-msg, and
  # an empty hooks path covers whatever a manager installed under another name.
  printf '%s\n' "$MESSAGE" \
    | git -C "$WORKTREE" -c core.hooksPath=/dev/null commit --no-verify --allow-empty --quiet -F - \
    || die "git commit failed in $WORKTREE"
  COMMIT="$(git -C "$WORKTREE" rev-parse HEAD)"
else
  # No worktree, nothing uncommitted: the commit is made from the branch's own
  # tree, with no checkout — and plumbing runs no hook.
  FILES=0
  COMMIT="$(printf '%s\n' "$MESSAGE" | git commit-tree "${OLD}^{tree}" -p "$OLD" -F -)" \
    || die "cannot write the commit on $BRANCH"
  git update-ref "refs/heads/$BRANCH" "$COMMIT" "$OLD" || die "cannot move $BRANCH to the new commit"
fi

# ── The push ──────────────────────────────────────────────────────────────────
#
# Past a pre-push hook for the same reason as the commit. Never forced: a
# remote branch that moved on is reported, not overwritten.

PUSH_LOG="$(git -c core.hooksPath=/dev/null push --no-verify --quiet -u "$REMOTE" \
  "refs/heads/$BRANCH:refs/heads/$BRANCH" 2>&1)"
PUSH_STATUS=$?

if [ "$PUSH_STATUS" -eq 0 ]; then
  set_keys true "$COMMIT" "$FILES" true "" ""
  emit
  exit 0
fi

set_keys true "$COMMIT" "$FILES" false "$(printf '%s\n' "$PUSH_LOG" | tail -5)" ""
emit
exit 4
