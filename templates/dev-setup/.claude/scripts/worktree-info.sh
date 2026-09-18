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
# The same question comes up one step earlier, before a fan-out: `multi-sdd`
# knows which files each task it is about to launch will touch, and no worktree
# and no spec exist yet. `--impact` feeds those estimates through the same
# comparison, so a set intersection is computed in one place whether the claim
# comes from a spec on disk or from a pre-flight estimate — and a task about to
# start is compared against the worktrees already in flight for free.
#
# Usage:
#   worktree-info.sh [--json]
#   worktree-info.sh [--json] --impact DE-1=src/a.ts,src/b.ts --impact DE-2=src/b.ts
#
#   --impact <label>=<files>   a declared file set that is not on disk yet:
#                              comma- or space-separated paths, one flag per
#                              label. The label is normally the task id, and it
#                              is what the overlap names. Repeatable.
#   --json                     emit a flat JSON object
#
# Keys:
#   WORKTREE        absolute path of the current worktree (or the main checkout)
#   WORKTREE_INDEX  its position in `git worktree list`; the main checkout is 0
#   PORT_OFFSET     the same number — the offset to add to the dev server port
#   WORKTREES       newline-separated "<path>\t<branch>" for every active worktree
#   OVERLAPS        newline-separated "<file>\t<name>,<name>" for every file more
#                   than one declarer claims — a branch for a worktree with a
#                   spec, the label for an `--impact` set
#   OVERLAP_COUNT   how many files overlap
#
# Exits non-zero outside a git repository.
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
IMPACTS=()

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --impact)
      [ $# -ge 2 ] || die "--impact requires <label>=<files>"
      case "$2" in
        *=*) IMPACTS+=("$2") ;;
        *) die "--impact takes <label>=<files>, not $(printf '%q' "$2")" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
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

# ── Declared impact, per declarer ─────────────────────────────────────────────
#
# A declarer is a task, not a checkout: "<file>, owner, display name". The owner
# is what deduplicates — a task with a worktree on disk and an `--impact`
# estimate for the same run is one declarer, so it never overlaps with itself.
# The display name is the first one seen for that owner, and worktrees are
# processed first, so a branch name wins over a bare label.
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
    PAIRS="$PAIRS$file	$task_id	$wt_branch
"
  done <<< "$(declared_files "$spec")"
done <<< "$WORKTREES"

# The estimates a fan-out declares before it starts. Comma or whitespace between
# the paths, and a leading `./` stripped: the spec extraction produces bare
# relative paths, and a key that does not match is an overlap silently missed.
for impact in ${IMPACTS+"${IMPACTS[@]}"}; do
  label="${impact%%=*}"
  [ -n "$label" ] || die "--impact needs a label before the '=' (e.g. --impact DE-1=src/a.ts)"

  while IFS= read -r file; do
    file="${file#./}"
    [ -n "$file" ] || continue
    PAIRS="$PAIRS$file	$label	$label
"
  done <<< "$(printf '%s' "${impact#*=}" | tr ', ' '\n\n')"
done

OVERLAPS=$(printf '%s' "$PAIRS" | awk -F'\t' '
  NF == 3 && !seen[$1 FS $2]++ {
    names[$1] = ($1 in names) ? names[$1] "," $3 : $3
    count[$1]++
  }
  END { for (f in count) if (count[f] > 1) print f "\t" names[f] }
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
