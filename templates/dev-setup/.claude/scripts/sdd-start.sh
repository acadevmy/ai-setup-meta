#!/usr/bin/env bash
# sdd-start.sh — resolves the branch and the paths an SDD task starts from.
#
# Single home for the branch-naming rules that used to be restated (and drift)
# in both the `sdd` and the `auto-sdd` skills.
#
# Usage:
#   sdd-start.sh --task DE-123 [--type feat] [--context auth] [--title "add refresh token"] [--json]
#   sdd-start.sh --task DE-123 --create            # also creates the branch
#   sdd-start.sh --task DE-123 --stop push --create  # and saves the stop point
#   sdd-start.sh --type fix --title "typo in the login copy" --create
#
#   --task <id>     task identifier, e.g. DE-123. Required unless --title is
#                   given: the `quick` fast path branches for a fix nobody
#                   opened a ticket for, and a branch still needs a name.
#   --type <type>   branch type: feat | fix | chore | docs | refactor | perf | test
#                   (default: feat)
#   --context <ctx> the area the work touches (auth, billing, ui); optional,
#                   slugified into the parentheses after the type
#   --title <text>  task title, in English; slugified into the branch name
#   --base <ref>    fork from this ref instead of the resolved base branch. The
#                   caller knows better than the local HEAD in a fresh worktree,
#                   which the harness branches from the remote default — `main`
#                   on plenty of projects whose work targets `next`.
#   --stop <point>  the stop point the developer chose for this task: spec |
#                   development | review | commit | push | merge-request.
#                   Saved by --create only, beside the task clock, so a
#                   resumed run reads it back instead of asking. Requires --task
#   --create        create and check out the branch (off by default: the script
#                   only reports, so a caller can show the plan first)
#   --json          emit a flat JSON object
#
# Keys:
#   BRANCH        the branch name to use, e.g. feat(auth)/DE-123_add-refresh-token
#   REPO_ROOT     absolute path of the repository root
#   SPEC_DIR      absolute path of the spec directory (<repo>/.specs)
#   VCS           git | none
#   BASE_BRANCH   the branch this work forks from: the `--base` ref when given,
#                 otherwise resolved from the repository
#   BRANCH_EXISTS true when BRANCH is already present locally
#   CREATED       true when --create actually created the branch
#   STOP_POINT    the stop point saved for this task — empty when none was
#                 ever saved (a branch cut before DE-17076): then ask
#
# Exits non-zero with neither --task nor --title, outside a repository, on an
# invalid --stop, or when --create cannot produce the branch or save the stop
# point.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

TASK_ID=""
BRANCH_TYPE="feat"
TASK_TITLE=""
CONTEXT=""
FORCED_BASE=""
STOP_POINT_ARG=""
DO_CREATE=false
AS_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --task)
      [ $# -ge 2 ] || die "--task requires an id"
      TASK_ID="$2"; shift 2 ;;
    --type)
      [ $# -ge 2 ] || die "--type requires a value"
      BRANCH_TYPE="$2"; shift 2 ;;
    --context)
      [ $# -ge 2 ] || die "--context requires a value"
      CONTEXT="$2"; shift 2 ;;
    --title)
      [ $# -ge 2 ] || die "--title requires a value"
      TASK_TITLE="$2"; shift 2 ;;
    --base)
      [ $# -ge 2 ] || die "--base requires a ref"
      FORCED_BASE="$2"; shift 2 ;;
    --stop)
      [ $# -ge 2 ] || die "--stop requires a value"
      STOP_POINT_ARG="$2"; shift 2 ;;
    --create) DO_CREATE=true; shift ;;
    --json) AS_JSON=true; shift ;;
    -h|--help)
      sed -n '2,47p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$TASK_ID" ] || [ -n "$TASK_TITLE" ] \
  || die "--task or --title is required (e.g. --task DE-123, or --title 'fix the login copy')"

case "$BRANCH_TYPE" in
  feat|fix|chore|docs|refactor|perf|test) ;;
  *) die "invalid --type '$BRANCH_TYPE': use feat|fix|chore|docs|refactor|perf|test" ;;
esac

STOP_POINTS="spec development review commit push merge-request"
case "$STOP_POINT_ARG" in
  ''|spec|development|review|commit|push|merge-request) ;;
  *) die "invalid --stop '$STOP_POINT_ARG': use one of $STOP_POINTS" ;;
esac
[ -z "$STOP_POINT_ARG" ] || [ -n "$TASK_ID" ] \
  || die "--stop requires --task: the stop point is kept per task"

VCS=$(detect_vcs)
[ "$VCS" = "git" ] || die "not inside a git repository: SDD needs version control"

REPO_ROOT=$(repo_root)

# ── Branch name ───────────────────────────────────────────────────────────────
#
# <type>[(<context>)]/<TASK_ID>_<slug> — feat(auth)/DE-123_add-refresh-token.
# The task id is kept verbatim, and the underscore is what separates it from the
# slug, so the tooling that reads it back out of the branch name (spec lookup,
# MR title) finds it with branch_task_id in common.sh. The context is optional:
# a change with no single area gets none rather than an invented one. Without a
# task id it is <type>[(<context>)]/<slug>: check-prerequisites.sh then reports
# an empty TASK_ID, which is the honest answer — there is no task.

if [ -n "$TASK_ID" ] && ! [[ "$TASK_ID" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  die "invalid --task '$TASK_ID': expected a plain identifier such as DE-123"
fi

SLUG=""
[ -n "$TASK_TITLE" ] && SLUG=$(slugify "$TASK_TITLE")

PREFIX="$BRANCH_TYPE"
if [ -n "$CONTEXT" ]; then
  CONTEXT_SLUG=$(slugify "$CONTEXT" 20)
  [ -n "$CONTEXT_SLUG" ] || die "--context '$CONTEXT' slugifies to nothing usable in a branch name"
  PREFIX="$BRANCH_TYPE($CONTEXT_SLUG)"
fi

if [ -n "$TASK_ID" ] && [ -n "$SLUG" ]; then
  BRANCH="$PREFIX/${TASK_ID}_$SLUG"
elif [ -n "$TASK_ID" ]; then
  BRANCH="$PREFIX/$TASK_ID"
else
  BRANCH="$PREFIX/$SLUG"
fi

[ "$BRANCH" != "$PREFIX/" ] || die "--title '$TASK_TITLE' slugifies to nothing usable as a branch name"

BRANCH_EXISTS=false
git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null 2>&1 && BRANCH_EXISTS=true

if [ -n "$FORCED_BASE" ]; then
  git rev-parse --verify --quiet "$FORCED_BASE" >/dev/null 2>&1 \
    || die "--base '$FORCED_BASE' is not a ref in this repository"
  BASE_BRANCH="$FORCED_BASE"
else
  BASE_BRANCH=$(detect_base_branch || true)
fi

# ── Optional branch creation ──────────────────────────────────────────────────

CREATED=false
if [ "$DO_CREATE" = true ]; then
  if [ "$BRANCH_EXISTS" = true ]; then
    git checkout "$BRANCH" >/dev/null 2>&1 || die "cannot check out the existing branch $BRANCH"
  else
    if [ -n "$BASE_BRANCH" ]; then
      git checkout -b "$BRANCH" "$BASE_BRANCH" >/dev/null 2>&1 \
        || die "cannot create $BRANCH from $BASE_BRANCH"
    else
      git checkout -b "$BRANCH" >/dev/null 2>&1 \
        || die "cannot create $BRANCH from the current HEAD"
    fi
    CREATED=true
  fi
fi

# ── Stop point ────────────────────────────────────────────────────────────────
#
# Beside the clock, in state_dir (common.sh). Written on --create only, so the
# report-only call stays read-only; --create on an existing branch with --stop
# is how a resumed run replaces it.

STOP_POINT=""
if [ -n "$TASK_ID" ]; then
  STOP_FILE="$(state_dir stop-point)/$TASK_ID" || die "cannot resolve the git directory"
  if [ "$DO_CREATE" = true ] && [ -n "$STOP_POINT_ARG" ]; then
    { mkdir -p "${STOP_FILE%/*}" && printf '%s\n' "$STOP_POINT_ARG" > "$STOP_FILE"; } 2>/dev/null \
      || die "cannot save the stop point in $STOP_FILE"
  fi
  [ -f "$STOP_FILE" ] && read -r STOP_POINT < "$STOP_FILE"
fi

# ── Output ────────────────────────────────────────────────────────────────────

json_set BRANCH "$BRANCH"
json_set REPO_ROOT "$REPO_ROOT"
json_set SPEC_DIR "$REPO_ROOT/.specs"
json_set VCS "$VCS"
json_set BASE_BRANCH "$BASE_BRANCH"
json_set BRANCH_EXISTS "$BRANCH_EXISTS"
json_set CREATED "$CREATED"
json_set STOP_POINT "$STOP_POINT"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
