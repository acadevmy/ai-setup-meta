#!/usr/bin/env bash
# review-package.sh — the diff verify and review read, built once.
#
# The closure used to build the same diff twice: `spec-verifier` ran its own
# `git diff`, then `code-reviewer` ran its own. This script writes the commits,
# the stat and the diff with ten lines of context into one file, and both
# agents read that file. The diff never enters the caller's context: only the
# path does.
#
# The diff runs against the working tree, so staged and unstaged changes to
# tracked files are both in it — at closure time nothing is committed yet. An
# untracked file has no diff: the caller stages first (`git add -A`). This
# script never stages, so a standalone review does not touch the developer's
# index.
#
# The package lives in the repository's common git directory, never in the
# working tree, so `git add -A` cannot commit it. It is named after the branch,
# so two worktrees get two packages, and a rerun on the same branch overwrites
# it with what is there now.
#
# Usage:
#   review-package.sh --base <ref> [--json]
#
#   --base <ref>  the commit to diff against — the MERGE_BASE that
#                 check-prerequisites.sh returns. Required: resolving it again
#                 here would be a second answer to a question already asked
#   --json        emit a flat JSON object
#
# Keys:
#   PACKAGE        absolute path of the package file — empty when EMPTY is true
#   MERGE_BASE     the commit --base resolved to
#   EMPTY          true when the working tree has no change against --base.
#                  Decided by the diff, never by the commits: staged work with
#                  no commit is not empty, and a commit with its revert is
#   COMMITS        commits in <base>..HEAD — reported, never used to decide
#   FILES          files changed against --base (a binary file counts)
#   CHANGED_LINES  insertions plus deletions (a binary file adds 0)
#   SIZE           small | large — large above LARGE_CHANGED_LINES lines or
#                  LARGE_FILES files; empty when EMPTY is true
#
# Exit: 0 on success, an empty change included · 1 usage error, a --base that
# is not a commit, or a run outside a git repository — nothing is written and
# nothing is printed on stdout
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# A change above either threshold is `large`: the review skill promotes it to a
# stronger model. 300 lines is about the ordinary branch, 10 files several
# times the `quick` bar. Tune them here, against measured runs.
LARGE_CHANGED_LINES=300
LARGE_FILES=10

# The context the agents get around every hunk: enough to read most changes
# without opening the whole file.
DIFF_CONTEXT=10

AS_JSON=false
BASE=""

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --base)
      [ $# -ge 2 ] && [ -n "$2" ] || die "--base requires a ref"
      BASE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$BASE" ] || die "--base is required: pass the MERGE_BASE check-prerequisites.sh returns"

require_jq

[ "$(detect_vcs)" = "git" ] || die "not a git repository: the package is built from git"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "cannot resolve the git working tree"
cd "$REPO_ROOT" || die "cannot enter the repository root: $REPO_ROOT"

MERGE_BASE="$(git rev-parse --verify --quiet "${BASE}^{commit}" 2>/dev/null)" \
  || die "--base \"$BASE\" does not resolve to a commit"

# ── Where the package lives ───────────────────────────────────────────────────

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
  BRANCH="detached-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi
SLUG="$(slugify "$BRANCH" 120)"
[ -n "$SLUG" ] || SLUG="branch"

PACKAGE_DIR="$(state_dir review-package)" || die "cannot resolve the git directory"
PACKAGE="$PACKAGE_DIR/$SLUG.md"

GIT_PLAIN=(git -c color.ui=false -c core.quotepath=false)

# ── Empty or not: the diff decides ────────────────────────────────────────────

COMMITS="$(git rev-list --count "$MERGE_BASE..HEAD" 2>/dev/null)" \
  || die "cannot count the commits in $MERGE_BASE..HEAD"

"${GIT_PLAIN[@]}" diff --quiet --no-ext-diff "$MERGE_BASE" 2>/dev/null
DIFF_STATUS=$?

case "$DIFF_STATUS" in
  0)
    # Nothing to review: a package left by an earlier run would describe a
    # change that no longer exists.
    rm -f "$PACKAGE"
    json_set PACKAGE ""
    json_set MERGE_BASE "$MERGE_BASE"
    json_set EMPTY "true"
    json_set COMMITS "$COMMITS"
    json_set FILES "0"
    json_set CHANGED_LINES "0"
    json_set SIZE ""
    if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
    exit 0
    ;;
  1) ;;
  *) die "git diff against $MERGE_BASE failed" ;;
esac

# ── Counts ────────────────────────────────────────────────────────────────────
#
# --numstat prints `<added> <deleted> <path>`, with `-` for both on a binary.

NUMSTAT="$("${GIT_PLAIN[@]}" diff --numstat --no-ext-diff "$MERGE_BASE")" \
  || die "git diff --numstat against $MERGE_BASE failed"
FILES="$(printf '%s\n' "$NUMSTAT" | awk 'NF { n++ } END { print n + 0 }')"
CHANGED_LINES="$(printf '%s\n' "$NUMSTAT" \
  | awk '$1 ~ /^[0-9]+$/ { s += $1 } $2 ~ /^[0-9]+$/ { s += $2 } END { print s + 0 }')"

SIZE="small"
if [ "$CHANGED_LINES" -gt "$LARGE_CHANGED_LINES" ] || [ "$FILES" -gt "$LARGE_FILES" ]; then
  SIZE="large"
fi

# ── The package ───────────────────────────────────────────────────────────────
#
# Written beside its final name and moved into place, so a reader never sees a
# half-written package and a failure leaves the previous one untouched.

mkdir -p "$PACKAGE_DIR" || die "cannot create $PACKAGE_DIR"
TMP_PACKAGE="$PACKAGE.tmp.$$"
trap 'rm -f "$TMP_PACKAGE"' EXIT

HEAD_SHA="$(git rev-parse HEAD)"

(
  printf '# Review package\n\n'
  printf -- '- Branch: %s\n' "$BRANCH"
  printf -- '- Merge base: %s\n' "$MERGE_BASE"
  printf -- '- HEAD: %s\n' "$HEAD_SHA"
  printf -- '- Files: %s · changed lines: %s · size: %s\n' "$FILES" "$CHANGED_LINES" "$SIZE"
  printf -- '- The diff is the working tree against the merge base: staged and\n'
  printf -- '  unstaged changes are both in it, untracked files are not.\n\n'

  printf '## Commits\n\n'
  if [ "$COMMITS" -gt 0 ]; then
    "${GIT_PLAIN[@]}" log --oneline --no-decorate "$MERGE_BASE..HEAD" || exit 1
  else
    printf '(none — the change is not committed yet)\n'
  fi
  printf '\n## Stat\n\n'
  "${GIT_PLAIN[@]}" diff --stat --no-ext-diff "$MERGE_BASE" || exit 1
  printf '\n## Diff\n\n'
  "${GIT_PLAIN[@]}" diff --no-ext-diff "-U$DIFF_CONTEXT" "$MERGE_BASE" || exit 1
) > "$TMP_PACKAGE" || die "cannot write the package for $MERGE_BASE"

mv -f "$TMP_PACKAGE" "$PACKAGE" || die "cannot move the package into $PACKAGE"

# ── Output ────────────────────────────────────────────────────────────────────

json_set PACKAGE "$PACKAGE"
json_set MERGE_BASE "$MERGE_BASE"
json_set EMPTY "false"
json_set COMMITS "$COMMITS"
json_set FILES "$FILES"
json_set CHANGED_LINES "$CHANGED_LINES"
json_set SIZE "$SIZE"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
