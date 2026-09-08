#!/usr/bin/env bash
# sdd-start.sh — resolves the branch and the paths an SDD task starts from.
#
# Single home for the branch-naming rules that used to be restated (and drift)
# in both the `sdd` and the `auto-sdd` skills.
#
# Usage:
#   sdd-start.sh --task DE-123 [--type feat] [--title "add refresh token"] [--json]
#   sdd-start.sh --task DE-123 --create            # also creates the branch
#
#   --task <id>     task identifier, e.g. DE-123 (required)
#   --type <type>   branch type: feat | fix | chore | docs | refactor | perf | test
#                   (default: feat)
#   --title <text>  task title; slugified into the branch name
#   --create        create and check out the branch (off by default: the script
#                   only reports, so a caller can show the plan first)
#   --json          emit a flat JSON object
#
# Keys:
#   BRANCH        the branch name to use, e.g. feat/DE-123-add-refresh-token
#   REPO_ROOT     absolute path of the repository root
#   SPEC_DIR      absolute path of the spec directory (<repo>/.specs)
#   VCS           git | none
#   BASE_BRANCH   the branch this work forks from, resolved from the repository
#   BRANCH_EXISTS true when BRANCH is already present locally
#   CREATED       true when --create actually created the branch
#
# Exits non-zero on a missing --task, outside a repository, or when --create
# cannot produce the branch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

TASK_ID=""
BRANCH_TYPE="feat"
TASK_TITLE=""
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
    --title)
      [ $# -ge 2 ] || die "--title requires a value"
      TASK_TITLE="$2"; shift 2 ;;
    --create) DO_CREATE=true; shift ;;
    --json) AS_JSON=true; shift ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$TASK_ID" ] || die "--task is required (e.g. --task DE-123)"

case "$BRANCH_TYPE" in
  feat|fix|chore|docs|refactor|perf|test) ;;
  *) die "invalid --type '$BRANCH_TYPE': use feat|fix|chore|docs|refactor|perf|test" ;;
esac

VCS=$(detect_vcs)
[ "$VCS" = "git" ] || die "not inside a git repository: SDD needs version control"

REPO_ROOT=$(repo_root)

# ── Branch name ───────────────────────────────────────────────────────────────
#
# <type>/<TASK_ID>-<slug>, with the task id kept verbatim so the tooling that
# greps it back out of the branch name (spec lookup, MR title) keeps working.

SLUG=""
[ -n "$TASK_TITLE" ] && SLUG=$(slugify "$TASK_TITLE")

if [ -n "$SLUG" ]; then
  BRANCH="$BRANCH_TYPE/$TASK_ID-$SLUG"
else
  BRANCH="$BRANCH_TYPE/$TASK_ID"
fi

BRANCH_EXISTS=false
git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null 2>&1 && BRANCH_EXISTS=true

BASE_BRANCH=$(detect_base_branch || true)

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

# ── Output ────────────────────────────────────────────────────────────────────

json_set BRANCH "$BRANCH"
json_set REPO_ROOT "$REPO_ROOT"
json_set SPEC_DIR "$REPO_ROOT/.specs"
json_set VCS "$VCS"
json_set BASE_BRANCH "$BASE_BRANCH"
json_set BRANCH_EXISTS "$BRANCH_EXISTS"
json_set CREATED "$CREATED"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
