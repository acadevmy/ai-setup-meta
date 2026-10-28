#!/usr/bin/env bash
# auto-dev-select.sh — which of a project's clones an auto-dev task belongs to,
# and the base branch it forks from.
#
# A project can span several repositories, and the job clones them all before
# anyone knows which one the task is about. The choice has to come before the
# devcontainer — each repository brings its own toolchain — so it runs on the
# host, here, with no model whenever the facts settle it:
#
#   1. a `repo: owner/repo` line in the task description names it;
#   2. only one repository was cloned.
#
# Otherwise it writes what a model needs to choose — the task and, per clone,
# its remote, README, AGENTS.md and manifests, each capped — and the
# auto-dev-select skill records the choice with --choose, or that nobody could
# make one with --block. A blocked selection moves the task to BLOCKED itself,
# with the reason: the runner then stops, and nothing else touches the board.
#
# The base branch, for the chosen clone, in this order: a `base: <branch>` line
# in the task; the model's reading of the task (--base, only when it chose);
# `base_branch` in the clone's .claude/auto-dev.json; the remote's HEAD; then
# main, master, develop. A base the task names that the clone does not have is
# a block, not a fallback: the task said where the work goes.
#
# Usage:
#   auto-dev-select.sh --args <file> [--json]
#   auto-dev-select.sh --args <file> --choose <repo path> --reason <text>
#                      [--evidence <text>]… [--base <branch>] [--json]
#   auto-dev-select.sh --args <file> --block --reason <text> [--json]
#
# The args file is the one auto-dev reads, with `repos`: the absolute paths of
# the clones. `taskId`, `outputDir`, `runId`, `tracker` and `task` as
# auto-dev-args.sh --help describes them.
#
# Writes into outputDir:
#   task.md          the task text, verbatim
#   candidates.md    what the model reads, when the facts did not settle it
#   selection.json   { status: selected | blocked | undecided, taskId, runId,
#                      repo, remote, slug, baseBranch, baseSource, source,
#                      reason, evidence[], hasDevcontainer, candidates[] }
#   result.json      a failed result at stage `select`, when blocked
#
# Keys:
#   STATUS           selected | blocked | undecided
#   REPO             the chosen clone's path, empty unless selected
#   SLUG             its owner/repo
#   BASE_BRANCH      the base it forks from, as origin/<branch>
#   BASE_SOURCE      task-line | model | config | remote-head | fallback
#   SOURCE           task-line | single | model
#   REASON           why, in one line
#   SELECTION_FILE   selection.json
#   CANDIDATES_FILE  candidates.md, when undecided
#   TASK_FILE        task.md
#
# Exit: 0 selected or undecided · 3 blocked or refused (REASON says why) ·
# 1 usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

TASK_ID_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

# What candidates.md carries per file: enough to tell repositories apart,
# bounded so that three READMEs cannot cost more than the decision is worth.
EXCERPT_LINES=40

AS_JSON=false
ARGS_FILE=""
MODE=decide
CHOSEN=""
REASON_IN=""
MODEL_BASE=""
EVIDENCE=()

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --args)
      [ $# -ge 2 ] || die "--args requires a path"
      ARGS_FILE="$2"; shift 2 ;;
    --choose)
      [ $# -ge 2 ] || die "--choose requires a repository path"
      MODE=choose; CHOSEN="$2"; shift 2 ;;
    --block) MODE=block; shift ;;
    --reason)
      [ $# -ge 2 ] || die "--reason requires a text"
      REASON_IN="$2"; shift 2 ;;
    --evidence)
      [ $# -ge 2 ] || die "--evidence requires a text"
      EVIDENCE+=("$2"); shift 2 ;;
    --base)
      [ $# -ge 2 ] || die "--base requires a branch"
      MODEL_BASE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$ARGS_FILE" ] || die "--args <file> is required (see --help)"
[ -f "$ARGS_FILE" ] || die "no args file at $ARGS_FILE"
jq -e 'type == "object"' "$ARGS_FILE" >/dev/null 2>&1 || die "$ARGS_FILE is not a JSON object"
case "$MODE" in choose|block) [ -n "$REASON_IN" ] || die "--$MODE requires --reason" ;; esac

finish_output() {
  if [ "$AS_JSON" = true ]; then
    json_emit
  else
    json_emit_text
  fi
}

arg() { jq -r --arg k "$1" '.[$k] // "" | if type == "string" then . else tojson end' "$ARGS_FILE"; }

TASK_ID="$(arg taskId)"
RUN_ID="$(arg runId)"
OUTPUT_DIR="$(arg outputDir)"
TRACKER="$(arg tracker)"; TRACKER="${TRACKER:-clickup}"

printf '%s' "$TASK_ID" | grep -qE "$TASK_ID_SHAPE" || die "taskId \"$TASK_ID\" is missing or not a plain task id"
case "$OUTPUT_DIR" in /*) ;; *) die "outputDir must be an absolute path" ;; esac
mkdir -p "$OUTPUT_DIR" 2>/dev/null || die "outputDir $OUTPUT_DIR cannot be created"
case "$TRACKER" in clickup|none) ;; *) die "tracker is \"$TRACKER\": it takes clickup or none" ;; esac

SELECTION_FILE="$OUTPUT_DIR/selection.json"
TASK_FILE="$OUTPUT_DIR/task.md"
CANDIDATES_FILE="$OUTPUT_DIR/candidates.md"

# ── The clones ────────────────────────────────────────────────────────────────

# owner/repo from a remote URL — or from what a task line names, which may be a
# URL or already owner/repo — with any credential in it dropped: a clone made
# with a token in its URL must not leak it into selection.json. A host is
# recognised by its dot (github.com) or, scp-style, by a colon (gitlab:grp/x).
remote_slug() {
  printf '%s' "$1" \
    | sed -E 's#^[a-zA-Z+]+://##; s#^[^@/]+@##; s#^[^/:]*\.[^/:]*[:/]##; s#^[^/:.]+:##; s#\.git$##; s#/+$##' \
    | tr '[:upper:]' '[:lower:]'
}
remote_clean() {
  printf '%s' "$1" | sed -E 's#^([a-zA-Z+]+://)[^@/]+@#\1#'
}

REPOS=()
while IFS= read -r REPO; do
  [ -n "$REPO" ] && REPOS+=("$REPO")
done <<EOF
$(jq -r '.repos // [] | .[] | select(type == "string")' "$ARGS_FILE")
EOF
[ ${#REPOS[@]} -gt 0 ] || die "repos is empty: pass the absolute paths of the project's clones"

CANDIDATES_JSON='[]'
for REPO in "${REPOS[@]}"; do
  case "$REPO" in /*) ;; *) die "repos entry \"$REPO\" is not an absolute path" ;; esac
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "repos entry $REPO is not a git clone"
  URL="$(git -C "$REPO" remote get-url origin 2>/dev/null || true)"
  CANDIDATES_JSON="$(printf '%s' "$CANDIDATES_JSON" | jq -c --arg repo "$REPO" \
    --arg slug "$(remote_slug "$URL")" --arg remote "$(remote_clean "$URL")" \
    '. + [{repo: $repo, slug: $slug, remote: $remote}]')"
done

# ── The task ──────────────────────────────────────────────────────────────────

if [ "$TRACKER" = clickup ]; then
  BOARD="$(bash "$SCRIPT_DIR/auto-dev-clickup.sh" --task "$TASK_ID" --read --json)" \
    || die "the task could not be read from ClickUp: $(printf '%s' "$BOARD" | jq -r '.REASON // "see stderr"' 2>/dev/null)"
  TITLE="$(printf '%s' "$BOARD" | jq -r '.NAME // ""')"
  DESCRIPTION="$(printf '%s' "$BOARD" | jq -r '.DESCRIPTION // ""')"
else
  TITLE="$(jq -r '.task.title // ""' "$ARGS_FILE")"
  DESCRIPTION="$(jq -r '.task.description // ""' "$ARGS_FILE")"
fi
printf '# %s\n\n%s\n' "$TITLE" "$DESCRIPTION" > "$TASK_FILE" || die "cannot write $TASK_FILE"

# A `key: value` line of the description, markdown emphasis allowed around the
# key (`**repo:** owner/repo`), first match only.
task_line() {
  printf '%s\n' "$DESCRIPTION" \
    | sed -nE "s#^[[:space:]>*_-]*$1[*_]*:[*_]*[[:space:]]*([^[:space:]]+)[[:space:]]*\$#\\1#Ip" \
    | head -1 | sed -E 's#[`*_]##g'
}

# ── The record ────────────────────────────────────────────────────────────────

write_selection() {
  local status="$1" repo="$2" source="$3" reason="$4" base="$5" base_source="$6"
  local slug="" remote="" devcontainer=false evidence='[]'
  if [ -n "$repo" ]; then
    slug="$(printf '%s' "$CANDIDATES_JSON" | jq -r --arg r "$repo" 'map(select(.repo == $r)) | first | .slug // ""')"
    remote="$(printf '%s' "$CANDIDATES_JSON" | jq -r --arg r "$repo" 'map(select(.repo == $r)) | first | .remote // ""')"
    { [ -d "$repo/.devcontainer" ] || [ -f "$repo/.devcontainer.json" ]; } && devcontainer=true
  fi
  if [ ${#EVIDENCE[@]} -gt 0 ]; then
    evidence="$(printf '%s\n' "${EVIDENCE[@]}" | jq -R . | jq -cs .)"
  fi
  jq -n --arg status "$status" --arg taskId "$TASK_ID" --arg runId "$RUN_ID" \
    --arg repo "$repo" --arg remote "$remote" --arg slug "$slug" \
    --arg baseBranch "$base" --arg baseSource "$base_source" --arg source "$source" \
    --arg reason "$reason" --argjson evidence "$evidence" --argjson hasDevcontainer "$devcontainer" \
    --argjson candidates "$CANDIDATES_JSON" \
    '$ARGS.named' > "$SELECTION_FILE" || die "cannot write $SELECTION_FILE"

  json_set STATUS "$status"
  json_set REPO "$repo"
  json_set SLUG "$slug"
  json_set BASE_BRANCH "$base"
  json_set BASE_SOURCE "$base_source"
  json_set SOURCE "$source"
  json_set REASON "$reason"
  json_set SELECTION_FILE "$SELECTION_FILE"
  json_set TASK_FILE "$TASK_FILE"
}

# A blocked selection is a failed run at stage `select`: result.json says so,
# and the task moves to BLOCKED with the reason, so whoever picks it up knows
# what to add to the task.
block() {
  write_selection blocked "" "" "$1" "" ""
  jq -n --arg taskId "$TASK_ID" --arg runId "$RUN_ID" --arg reason "$1" \
    '{status: "failed", stage: "select", reason: $reason, taskId: $taskId, runId: $runId}' \
    > "$OUTPUT_DIR/result.json" || die "cannot write $OUTPUT_DIR/result.json"
  if [ "$TRACKER" = clickup ]; then
    bash "$SCRIPT_DIR/auto-dev-clickup.sh" --task "$TASK_ID" --finish \
      --result "$OUTPUT_DIR/result.json" --json >/dev/null \
      || warn "the task could not be moved to BLOCKED: the runner has to say so on the board"
  fi
  finish_output
  exit 3
}

# The base for one clone, in the order the header gives. Prints
# `<origin/branch> <source>`, or nothing when a base the task names is missing.
resolve_base() {
  local repo="$1" named config head candidate
  has() { git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$1" >/dev/null; }

  named="$(task_line base)"
  named="${named#origin/}"
  if [ -n "$named" ]; then
    has "$named" && { printf 'origin/%s task-line' "$named"; return 0; }
    return 1
  fi
  if [ -n "$MODEL_BASE" ]; then
    candidate="${MODEL_BASE#origin/}"
    has "$candidate" && { printf 'origin/%s model' "$candidate"; return 0; }
    warn "the model read base $MODEL_BASE from the task, and the clone has no such branch: falling back"
  fi
  if [ -f "$repo/.claude/auto-dev.json" ]; then
    config="$(jq -r '.base_branch // ""' "$repo/.claude/auto-dev.json" 2>/dev/null || true)"
    config="${config#origin/}"
    if [ -n "$config" ] && has "$config"; then
      printf 'origin/%s config' "$config"; return 0
    fi
  fi
  head="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$head" ]; then
    printf '%s remote-head' "$head"; return 0
  fi
  for candidate in main master develop; do
    has "$candidate" && { printf 'origin/%s fallback' "$candidate"; return 0; }
  done
  printf ' fallback'
}

select_repo() {
  local repo="$1" source="$2" reason="$3" base base_source resolved
  if ! resolved="$(resolve_base "$repo")"; then
    block "the task names base $(task_line base), and $(printf '%s' "$CANDIDATES_JSON" | jq -r --arg r "$repo" 'map(select(.repo == $r)) | first | .slug') has no such branch on origin"
  fi
  base="${resolved% *}"
  base_source="${resolved##* }"
  [ -n "$base" ] || block "no base branch for $repo: the task names none, .claude/auto-dev.json has none, and origin has no HEAD, main, master or develop"
  # Ready means the project declared how it checks its work: without that,
  # auto-dev refuses at intake, after the devcontainer was paid for.
  [ -f "$repo/.claude/quality-commands.json" ] \
    || block "$(printf '%s' "$CANDIDATES_JSON" | jq -r --arg r "$repo" 'map(select(.repo == $r)) | first | .slug') declares no quality commands (.claude/quality-commands.json): run /dev-setup:setup there, step 3b"
  write_selection selected "$repo" "$source" "$reason" "$base" "$base_source"
  finish_output
  exit 0
}

# ── The modes ─────────────────────────────────────────────────────────────────

if [ "$MODE" = block ]; then
  block "$REASON_IN"
fi

if [ "$MODE" = choose ]; then
  printf '%s' "$CANDIDATES_JSON" | jq -e --arg r "$CHOSEN" 'any(.repo == $r)' >/dev/null \
    || die "--choose $CHOSEN is not one of the repos in $ARGS_FILE"
  select_repo "$CHOSEN" model "$REASON_IN"
fi

NAMED_REPO="$(task_line repo)"
if [ -n "$NAMED_REPO" ]; then
  WANT="$(remote_slug "$NAMED_REPO")"
  MATCH="$(printf '%s' "$CANDIDATES_JSON" | jq -r --arg w "$WANT" \
    '[.[] | select(.slug == $w or (.slug | endswith("/" + $w)))] | if length == 1 then .[0].repo else "" end')"
  [ -n "$MATCH" ] || block "the task names repo $NAMED_REPO, and none of the clones — or more than one — is that repository: $(printf '%s' "$CANDIDATES_JSON" | jq -r 'map(.slug) | join(", ")')"
  EVIDENCE+=("repo: $NAMED_REPO in the task description")
  select_repo "$MATCH" task-line "the task description names $NAMED_REPO"
fi

if [ ${#REPOS[@]} -eq 1 ]; then
  select_repo "${REPOS[0]}" single "the project has one repository"
fi

# ── Undecided: what the model reads ───────────────────────────────────────────

excerpt() {
  [ -f "$1" ] || return 0
  printf '\n### %s (first %s lines)\n\n' "$2" "$EXCERPT_LINES"
  head -n "$EXCERPT_LINES" "$1"
}

{
  printf '# The candidates for %s\n\n' "$TASK_ID"
  printf 'The task is in %s. Choose the one repository it belongs to.\n' "$TASK_FILE"
  for REPO in "${REPOS[@]}"; do
    SLUG="$(printf '%s' "$CANDIDATES_JSON" | jq -r --arg r "$REPO" 'map(select(.repo == $r)) | first | .slug')"
    printf '\n## %s\n\npath: %s\n' "$SLUG" "$REPO"
    printf 'quality commands declared: %s\n' "$([ -f "$REPO/.claude/quality-commands.json" ] && echo yes || echo no)"
    printf 'top level: %s\n' "$(find "$REPO" -mindepth 1 -maxdepth 1 ! -name '.git' -exec basename {} \; 2>/dev/null | LC_ALL=C sort | head -30 | tr '\n' ' ')"
    excerpt "$REPO/README.md" README.md
    excerpt "$REPO/AGENTS.md" AGENTS.md
    for MANIFEST in package.json composer.json pubspec.yaml go.mod pyproject.toml Cargo.toml; do
      excerpt "$REPO/$MANIFEST" "$MANIFEST"
    done
  done
} > "$CANDIDATES_FILE" || die "cannot write $CANDIDATES_FILE"

write_selection undecided "" "" "the task names no repository and the project has ${#REPOS[@]}: a model chooses from $CANDIDATES_FILE" "" ""
json_set CANDIDATES_FILE "$CANDIDATES_FILE"
finish_output
