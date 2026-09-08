#!/usr/bin/env bash
# check-prerequisites.sh — collects what verify/review need before they run.
#
# The base branch is resolved from the repository through `git merge-base`, never
# hard-coded: `git diff main...HEAD` on a project that targets `next` (or
# `develop`) reports the whole delta between the two long-lived branches, which
# is what produced the false "Unexpected files" in verify.
#
# Usage:
#   check-prerequisites.sh [--json] [--task DE-123] [--base <ref>] [--require-spec]
#
#   --json           emit a flat JSON object
#   --task <id>      look the spec up for this task id instead of deriving it
#                    from the current branch name
#   --base <ref>     force the base ref instead of resolving it
#   --require-spec   exit non-zero when no spec was found
#
# Keys:
#   SPEC            absolute path of the spec file, or "" when absent
#   PLAN            absolute path of the plan file, or "" when absent
#   CHANGED_FILES   newline-separated list of files changed against the merge
#                   base, or "" when the branch has no changes of its own
#   AVAILABLE_DOCS  comma-separated governance docs present at the repo root
#                   (CONSTITUTION.md, REGISTRY.md, AGENTS.md, README.md)
#   BASE_BRANCH     the resolved base ref, e.g. origin/next
#   MERGE_BASE      the commit the branch forked from — the diff anchor
#   BRANCH          the current branch
#   TASK_ID         the task id in use, or ""
#   SPEC_STATUS     the spec's frontmatter status (draft|approved|implemented), or ""

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

AS_JSON=false
TASK_ID=""
FORCED_BASE=""
REQUIRE_SPEC=false

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --task)
      [ $# -ge 2 ] || die "--task requires an id"
      TASK_ID="$2"; shift 2 ;;
    --base)
      [ $# -ge 2 ] || die "--base requires a ref"
      FORCED_BASE="$2"; shift 2 ;;
    --require-spec) REQUIRE_SPEC=true; shift ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

VCS=$(detect_vcs)
[ "$VCS" = "git" ] || die "not inside a git repository"

REPO_ROOT=$(repo_root)
cd "$REPO_ROOT" || die "cannot enter the repository root: $REPO_ROOT"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# ── Task id ───────────────────────────────────────────────────────────────────
#
# From the branch name when not given: feat/DE-123-slug -> DE-123.

if [ -z "$TASK_ID" ] && [ -n "$BRANCH" ]; then
  TASK_ID=$(printf '%s' "$BRANCH" \
    | sed -n 's|^[a-z]*/\([A-Z][A-Z0-9]*-[0-9]\{1,\}\).*|\1|p')
fi

# ── Base branch and merge base ────────────────────────────────────────────────

if [ -n "$FORCED_BASE" ]; then
  BASE_BRANCH="$FORCED_BASE"
else
  BASE_BRANCH=$(detect_base_branch || true)
fi

MERGE_BASE=""
if [ -n "$BASE_BRANCH" ]; then
  MERGE_BASE=$(merge_base_with "$BASE_BRANCH" || true)
  if [ -z "$MERGE_BASE" ]; then
    warn "no merge base between HEAD and $BASE_BRANCH: falling back to the diff against HEAD's parent"
  fi
fi

# ── Changed files ─────────────────────────────────────────────────────────────
#
# Against the merge base, so the list holds this branch's own commits only.
# Uncommitted work is included: verify runs before the commit too.

CHANGED_FILES=""
if [ -n "$MERGE_BASE" ]; then
  CHANGED_FILES=$(git diff --name-only "$MERGE_BASE" 2>/dev/null || true)
elif git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
  CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null || true)
else
  CHANGED_FILES=$(git diff --name-only 2>/dev/null || true)
fi

# Untracked files are part of the change set: a brand-new source file has no
# diff against the merge base until it is staged.
UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
if [ -n "$UNTRACKED" ]; then
  if [ -n "$CHANGED_FILES" ]; then
    CHANGED_FILES=$(printf '%s\n%s' "$CHANGED_FILES" "$UNTRACKED" | LC_ALL=C sort -u)
  else
    CHANGED_FILES="$UNTRACKED"
  fi
fi

# ── Spec and plan ─────────────────────────────────────────────────────────────
#
# Convention: .specs/<TASK_ID>-<slug>.md for the spec, with the plan either in
# the same file or alongside it as <TASK_ID>-<slug>-plan.md. The newest match
# wins when several exist.

SPEC=""
PLAN=""
SPEC_STATUS=""

if [ -n "$TASK_ID" ] && [ -d "$REPO_ROOT/.specs" ]; then
  # LC_ALL=C on every sort in this script: the keys it prints are a contract, and
  # locale collation would order them differently from one machine to the next.
  SPEC=$(find "$REPO_ROOT/.specs" -maxdepth 1 -name "$TASK_ID-*.md" \
    -not -name '*-plan.md' 2>/dev/null | LC_ALL=C sort | tail -1)
  PLAN=$(find "$REPO_ROOT/.specs" -maxdepth 1 -name "$TASK_ID-*-plan.md" \
    2>/dev/null | LC_ALL=C sort | tail -1)
fi

if [ -n "$SPEC" ] && [ -f "$SPEC" ]; then
  # Frontmatter status, read from the first 20 lines only.
  SPEC_STATUS=$(sed -n '1,20p' "$SPEC" \
    | sed -n 's/^status:[[:space:]]*\([a-zA-Z-]\{1,\}\).*/\1/p' | head -1)
  # A spec holding its own "## Implementation plan" section is its own plan.
  if [ -z "$PLAN" ] && grep -qi '^## *\(implementation \)\?plan' "$SPEC" 2>/dev/null; then
    PLAN="$SPEC"
  fi
else
  SPEC=""
fi

if [ "$REQUIRE_SPEC" = true ] && [ -z "$SPEC" ]; then
  die "no spec found for ${TASK_ID:-the current branch} under $REPO_ROOT/.specs"
fi

# ── Available governance docs ─────────────────────────────────────────────────

AVAILABLE_DOCS=""
for doc in CONSTITUTION.md REGISTRY.md AGENTS.md CLAUDE.md README.md; do
  if [ -f "$REPO_ROOT/$doc" ]; then
    if [ -z "$AVAILABLE_DOCS" ]; then
      AVAILABLE_DOCS="$doc"
    else
      AVAILABLE_DOCS="$AVAILABLE_DOCS,$doc"
    fi
  fi
done

# ── Output ────────────────────────────────────────────────────────────────────

json_set SPEC "$SPEC"
json_set PLAN "$PLAN"
json_set CHANGED_FILES "$CHANGED_FILES"
json_set AVAILABLE_DOCS "$AVAILABLE_DOCS"
json_set BASE_BRANCH "$BASE_BRANCH"
json_set MERGE_BASE "$MERGE_BASE"
json_set BRANCH "$BRANCH"
json_set TASK_ID "$TASK_ID"
json_set SPEC_STATUS "$SPEC_STATUS"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
