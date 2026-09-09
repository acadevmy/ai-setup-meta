#!/usr/bin/env bash
# worktree-info.sh — what the other active worktrees are doing.
#
# Two questions a session working in a worktree has to answer and cannot answer
# from its own checkout:
#
#   Which port do I start the dev server on? Every worktree of the same project
#   runs the same `dev` script, so they collide on the same port. PORT_OFFSET is
#   this worktree's position in `git worktree list` — add it to the project's
#   base port and two sessions never fight over it.
#
#   Is another worktree touching my files? Each active worktree declares the
#   files it will touch in its spec's `## Impact` section. Where two of them
#   declare the same file, the merge is going to hurt, and knowing that now is
#   worth more than discovering it at rebase time.
#
# Best-effort by design: the answer is a warning, never a gate. A worktree
# without a spec contributes nothing and is not an error.
#
# Usage:
#   worktree-info.sh [--json]
#
# Keys:
#   WORKTREE        absolute path of the current worktree (or the main checkout)
#   WORKTREE_INDEX  its position in `git worktree list`; the main checkout is 0
#   PORT_OFFSET     the same number — the offset to add to the dev server port
#   WORKTREES       newline-separated "<path>\t<branch>" for every active worktree
#   OVERLAPS        newline-separated "<file>\t<branch>,<branch>" for every file
#                   more than one worktree declares in its spec
#   OVERLAP_COUNT   how many files overlap
#
# Exits non-zero outside a git repository.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    -h|--help)
      sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ "$(detect_vcs)" = "git" ] || die "not inside a git repository"

CURRENT=$(git rev-parse --show-toplevel 2>/dev/null) || die "cannot resolve the working tree root"

# ── The active worktrees ──────────────────────────────────────────────────────
#
# `--porcelain` is the only stable format: one `worktree <path>` line per entry,
# followed by its `branch refs/heads/<name>` when it has one. The first entry is
# always the main checkout.

WORKTREES=$(git worktree list --porcelain 2>/dev/null | awk '
  /^worktree / { path = substr($0, 10); branch = "(detached)" }
  /^branch /   { branch = substr($0, 8); sub("^refs/heads/", "", branch) }
  /^$/         { if (path != "") { print path "\t" branch; path = "" } }
  END          { if (path != "") print path "\t" branch }
')

WORKTREE_INDEX=$(printf '%s\n' "$WORKTREES" | awk -F'\t' -v cur="$CURRENT" '
  $1 == cur { print NR - 1; found = 1; exit }
  END { if (!found) print 0 }
')

# ── Declared impact, per worktree ─────────────────────────────────────────────
#
# The spec is found the way check-prerequisites.sh finds it: the task id out of
# the branch name, then .specs/<TASK_ID>-*.md inside that worktree.

declared_files() {
  local spec="$1"
  awk '
    /^##[[:space:]]/ { in_impact = ($0 ~ /^##[[:space:]]+Impact/); next }
    in_impact && /[Dd]ependencies/ { next }
    in_impact { print }
  ' "$spec" \
    | grep -o -E '[A-Za-z0-9_][A-Za-z0-9_/.-]*\.[A-Za-z0-9]+' \
    | LC_ALL=C sort -u
}

PAIRS=""
while IFS=$'\t' read -r wt_path wt_branch; do
  [ -n "$wt_path" ] || continue
  [ -d "$wt_path/.specs" ] || continue

  task_id=$(printf '%s' "$wt_branch" \
    | sed -n 's|^[a-z]*/\([A-Z][A-Z0-9]*-[0-9]\{1,\}\).*|\1|p')
  [ -n "$task_id" ] || continue

  spec=$(find "$wt_path/.specs" -maxdepth 1 -name "$task_id-*.md" \
    -not -name '*-plan.md' 2>/dev/null | LC_ALL=C sort | tail -1)
  [ -n "$spec" ] && [ -f "$spec" ] || continue

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    PAIRS="$PAIRS$file	$wt_branch
"
  done <<< "$(declared_files "$spec")"
done <<< "$WORKTREES"

OVERLAPS=$(printf '%s' "$PAIRS" | awk -F'\t' '
  NF == 2 && !seen[$0]++ {
    branches[$1] = ($1 in branches) ? branches[$1] "," $2 : $2
    count[$1]++
  }
  END { for (f in count) if (count[f] > 1) print f "\t" branches[f] }
' | LC_ALL=C sort)

OVERLAP_COUNT=0
[ -n "$OVERLAPS" ] && OVERLAP_COUNT=$(printf '%s\n' "$OVERLAPS" | grep -c .)

# ── Output ────────────────────────────────────────────────────────────────────

json_set WORKTREE "$CURRENT"
json_set WORKTREE_INDEX "$WORKTREE_INDEX"
json_set PORT_OFFSET "$WORKTREE_INDEX"
json_set WORKTREES "$WORKTREES"
json_set OVERLAPS "$OVERLAPS"
json_set OVERLAP_COUNT "$OVERLAP_COUNT"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
