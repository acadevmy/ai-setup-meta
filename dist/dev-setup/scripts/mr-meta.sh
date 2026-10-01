#!/usr/bin/env bash
# mr-meta.sh — the language, the template, the title and the labels of the merge
# request the current branch is about to open.
#
# A merge request's shape is a project decision, not a session one: the setup
# asks once which language the team reviews in and writes it, with the labels
# the team uses, to `.claude/merge-request.json`. The developers own that file —
# they change the language, add a label, drop a mapping — and every flow that
# opens a merge request reads it through here, so none of them re-derives the
# title format or guesses a label.
#
# Usage:
#   mr-meta.sh [--summary "<what was done>"] [--breaking] [--priority <p>] [--json]
#
#   --summary <text>  what the branch did, already in LANGUAGE; with it the
#                     script composes TITLE
#   --breaking        the change breaks a contract: adds labels.breaking
#   --priority <p>    the task's priority (urgent | high | normal | low): adds
#                     labels.by_priority[p]
#   --branch <name>   read this branch instead of the current one
#   --type <type>     override the type read from the branch name
#   --json            emit a flat JSON object
#
# Keys:
#   META_FILE    the metadata file read — empty when the project has none
#   LANGUAGE     it | en — the language of the title and the body; empty
#                without a metadata file, and then the template's language rules
#   TEMPLATE     the repository's own template for this host, relative to the
#                root — empty when the repository has none
#   BRANCH       the branch read
#   TYPE         its type (feat(auth)/DE-123_x -> feat)
#   CONTEXT      its context (-> auth), or empty
#   TASK_ID      its task id (-> DE-123), or empty
#   TITLE_TYPE   the type as the title spells it (-> Feat)
#   TITLE        `<TITLE_TYPE>: <summary> [<TASK_ID>]` — empty without --summary
#   LABELS       the labels to pass, comma-separated, in order: by type,
#                breaking, by priority, on open — empty without a metadata file
#
# Exits non-zero outside a repository, on a malformed metadata file, or on a
# --priority that is not one of the four.
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

SUMMARY=""
BREAKING=false
PRIORITY=""
BRANCH=""
TYPE=""
AS_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --summary)
      [ $# -ge 2 ] || die "--summary requires a value"
      SUMMARY="$2"; shift 2 ;;
    --breaking) BREAKING=true; shift ;;
    --priority)
      [ $# -ge 2 ] || die "--priority requires a value"
      PRIORITY=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]'); shift 2 ;;
    --branch)
      [ $# -ge 2 ] || die "--branch requires a name"
      BRANCH="$2"; shift 2 ;;
    --type)
      [ $# -ge 2 ] || die "--type requires a value"
      TYPE="$2"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help)
      sed -n '2,/^# ---8<---/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

case "$PRIORITY" in
  ''|urgent|high|normal|low) ;;
  *) die "invalid --priority '$PRIORITY': use urgent|high|normal|low" ;;
esac

[ "$(detect_vcs)" = "git" ] || die "not inside a git repository"
REPO_ROOT=$(repo_root)

# ── The branch ────────────────────────────────────────────────────────────────

[ -n "$BRANCH" ] || BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[ -n "$TYPE" ] || TYPE=$(branch_type "$BRANCH")
CONTEXT=$(branch_context "$BRANCH")
TASK_ID=$(branch_task_id "$BRANCH")

TITLE_TYPE=""
[ -n "$TYPE" ] && TITLE_TYPE="$(printf '%s' "${TYPE:0:1}" | tr '[:lower:]' '[:upper:]')${TYPE:1}"

TITLE=""
if [ -n "$SUMMARY" ]; then
  TITLE="$SUMMARY"
  [ -n "$TITLE_TYPE" ] && TITLE="$TITLE_TYPE: $TITLE"
  [ -n "$TASK_ID" ] && TITLE="$TITLE [$TASK_ID]"
fi

# ── The template ──────────────────────────────────────────────────────────────
#
# The host's own folder first, then the other one: a repository mirrored on
# both forges still carries the template where the setup wrote it.

GITHUB_TEMPLATE=".github/PULL_REQUEST_TEMPLATE.md"
GITLAB_TEMPLATE=".gitlab/merge_request_templates/Default.md"

case "$(git remote get-url origin 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
  *gitlab*) CANDIDATES=("$GITLAB_TEMPLATE" "$GITHUB_TEMPLATE") ;;
  *)        CANDIDATES=("$GITHUB_TEMPLATE" "$GITLAB_TEMPLATE") ;;
esac

TEMPLATE=""
for candidate in "${CANDIDATES[@]}"; do
  if [ -f "$REPO_ROOT/$candidate" ]; then
    TEMPLATE="$candidate"
    break
  fi
done

# ── The metadata ──────────────────────────────────────────────────────────────

META_FILE=""
LANGUAGE=""
LABELS=""

if [ -f "$REPO_ROOT/.claude/merge-request.json" ]; then
  META_FILE=".claude/merge-request.json"
  jq empty "$REPO_ROOT/$META_FILE" 2>/dev/null \
    || die "$META_FILE is not valid JSON: fix it, or remove it and run the setup again"

  LANGUAGE=$(jq -r '.language // "" | ascii_downcase' "$REPO_ROOT/$META_FILE")

  # Order is the reading order on the forge: what the change is, whether it
  # breaks something, how urgent it is, where it stands. A label named twice
  # is passed once, and a single name where a list belongs is read as a list of
  # one — the file is edited by hand.
  LABELS=$(jq -r \
    --arg type "$TYPE" --arg priority "$PRIORITY" --argjson breaking "$BREAKING" '
      def names: if type == "array" then . elif type == "string" then [.] else [] end;
      (.labels // {}) as $l
      | [ ($l.by_type[$type] | names),
          (if $breaking then ($l.breaking | names) else [] end),
          ($l.by_priority[$priority] | names),
          ($l.on_open | names) ]
      | flatten
      | map(select(type == "string" and . != ""))
      | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)
      | join(",")' "$REPO_ROOT/$META_FILE" 2>/dev/null) \
    || die "$META_FILE: labels must be an object of label lists"
fi

# ── Output ────────────────────────────────────────────────────────────────────

json_set META_FILE "$META_FILE"
json_set LANGUAGE "$LANGUAGE"
json_set TEMPLATE "$TEMPLATE"
json_set BRANCH "$BRANCH"
json_set TYPE "$TYPE"
json_set CONTEXT "$CONTEXT"
json_set TASK_ID "$TASK_ID"
json_set TITLE_TYPE "$TITLE_TYPE"
json_set TITLE "$TITLE"
json_set LABELS "$LABELS"

if [ "$AS_JSON" = true ]; then
  json_emit
else
  json_emit_text
fi
