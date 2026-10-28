#!/usr/bin/env bash
# auto-dev-args.sh — what an auto-dev run needs before its first agent, decided
# by a script.
#
# The run is headless: nobody is there to notice a bad argument, so each one is
# checked here, before the board moves or an agent is paid for. The task comes
# from the tracker through auto-dev-clickup.sh (or inline, with no tracker), the
# quality commands from detect-stack.sh and quality-preflight.sh unless the
# caller passed them, the merge request language from mr-meta.sh.
#
# The task text is written to a file the workflow's agents read, so nothing
# re-types it on its way: the launcher passes only the short arguments below.
#
# Usage:
#   auto-dev-args.sh --args <file> [--json]
#
# The args file, written by the runner:
#   {
#     "taskId":     "DE-123",              required
#     "outputDir":  "/abs/path",           required — outside the repository,
#                                          created when missing
#     "repos":      ["/abs/clone", …],     read by auto-dev-select only
#     "baseBranch": "origin/next",         default: the selection.json that
#                                          auto-dev-select wrote in outputDir;
#                                          must resolve here
#     "runId":      "<id>",                echoed into the result
#     "challenge":  "auto|always|never",   default auto
#     "branchType": "feat|fix|chore",      default feat
#     "tracker":    "clickup|none",        default clickup
#     "task":       { "title", "description", "url", "priority" }
#                                          required with tracker none
#     "stack":      { "lint", "typecheck", "test" }
#                                          default: detect-stack.sh, with
#                                          quality-preflight.sh for what cannot
#                                          run here
#     "unavailable": ["lint"], "unavailableReason": "<text>"
#                                          only with stack
#   }
#
# Environment, set by the runner:
#   CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS
#                       required — 0 to wait for the workflow however long it
#                       runs. Unset, claude -p stops a background workflow ten
#                       minutes after the launcher's last turn, which is the one
#                       that starts it: the run would end with no outcome
#
# With the Bash sandbox on, claude needs `--add-dir <outputDir>`: a sandboxed
# command writes only in the working directory and the directories added.
#
# Writes into outputDir:
#   task.md             the task's title and description, verbatim
#   workflow-args.json  the arguments of the dev-setup:auto-dev workflow
#   launch.json         what auto-dev-report.sh needs afterwards
#
# Keys:
#   ACCEPTED            true when the run may start
#   REASON              why it may not, empty when accepted
#   TASK_ID             the task id
#   TITLE               the task title
#   TRACKER             clickup | none
#   OUTPUT_DIR          the absolute output directory
#   TASK_FILE           the task text's file
#   WORKFLOW_ARGS       the workflow arguments, as compact JSON
#   WORKFLOW_ARGS_FILE  the same, as a file
#   LAUNCH_FILE         the launch record's file
#   PLUGIN_ROOT         the plugin root these scripts belong to
#
# Exit: 0 accepted · 3 refused (ACCEPTED=false, REASON says why) · 1 usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TASK_ID_SHAPE='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

AS_JSON=false
ARGS_FILE=""

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
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$ARGS_FILE" ] || die "--args <file> is required (see --help)"

finish_output() {
  if [ "$AS_JSON" = true ]; then
    json_emit
  else
    json_emit_text
  fi
}

json_set ACCEPTED true
json_set REASON ""

# Once the output directory is known, a refusal is written there too: the
# runner reads result.json whatever happened, and a run refused at intake is a
# result like any other.
REFUSAL_RESULT=""
TASK_ID=""
RUN_ID=""

refuse() {
  json_set ACCEPTED false
  json_set REASON "$1"
  if [ -n "$REFUSAL_RESULT" ]; then
    jq -n --arg taskId "$TASK_ID" --arg runId "$RUN_ID" --arg reason "$1" \
      '{status: "failed", stage: "intake", reason: $reason, taskId: $taskId, runId: $runId}' \
      > "$REFUSAL_RESULT" 2>/dev/null || warn "could not write $REFUSAL_RESULT"
  fi
  finish_output
  exit 3
}

[ -f "$ARGS_FILE" ] || refuse "no args file at $ARGS_FILE"
jq -e 'type == "object"' "$ARGS_FILE" >/dev/null 2>&1 || refuse "$ARGS_FILE is not a JSON object"

arg() { jq -r --arg k "$1" '.[$k] // "" | if type == "string" then . else tojson end' "$ARGS_FILE"; }

TASK_ID="$(arg taskId)"
BASE="$(arg baseBranch)"
OUTPUT_DIR="$(arg outputDir)"
RUN_ID="$(arg runId)"
CHALLENGE="$(arg challenge)"; CHALLENGE="${CHALLENGE:-auto}"
BRANCH_TYPE="$(arg branchType)"; BRANCH_TYPE="${BRANCH_TYPE:-feat}"
TRACKER="$(arg tracker)"; TRACKER="${TRACKER:-clickup}"

json_set TASK_ID "$TASK_ID"
json_set TRACKER "$TRACKER"
json_set PLUGIN_ROOT "$PLUGIN_ROOT"

# ── The arguments ─────────────────────────────────────────────────────────────

[ -n "$TASK_ID" ] || refuse "taskId is required"
printf '%s' "$TASK_ID" | grep -qE "$TASK_ID_SHAPE" \
  || refuse "\"$TASK_ID\" is not a plain task id (letters, digits, dot, dash, underscore): it reaches a branch name and a shell command"
case "$CHALLENGE" in auto|always|never) ;; *) refuse "challenge is \"$CHALLENGE\": it takes auto, always or never" ;; esac
case "$BRANCH_TYPE" in feat|fix|chore) ;; *) refuse "branchType is \"$BRANCH_TYPE\": it takes feat, fix or chore" ;; esac
case "$TRACKER" in clickup|none) ;; *) refuse "tracker is \"$TRACKER\": it takes clickup or none" ;; esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || refuse "not inside a git repository: run auto-dev from the project's checkout"

# The output directory sits outside the repository: the dev agent stages
# everything with `git add -A`, and the run's own files must not ride its commit.
case "$OUTPUT_DIR" in
  /*) ;;
  *) refuse "outputDir must be an absolute path, not \"$OUTPUT_DIR\"" ;;
esac
mkdir -p "$OUTPUT_DIR" 2>/dev/null || refuse "outputDir $OUTPUT_DIR cannot be created"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
ROOT_REAL="$(cd "$ROOT" && pwd -P)"
case "$OUTPUT_DIR/" in
  "$ROOT_REAL"/*) refuse "outputDir $OUTPUT_DIR is inside the repository: the dev commit would carry the run's files" ;;
esac
[ -w "$OUTPUT_DIR" ] \
  || refuse "outputDir $OUTPUT_DIR is not writable — with the Bash sandbox on, start claude with --add-dir $OUTPUT_DIR"
json_set OUTPUT_DIR "$OUTPUT_DIR"
REFUSAL_RESULT="$OUTPUT_DIR/result.json"

# The launcher's last turn is the one that starts the workflow, and claude -p
# stops a background task ten minutes after the last turn: on job
# ad-dry-10281436 a run in a devcontainer was stopped in Dev, with no outcome,
# no result and the money spent. So the runner lifts that ceiling, and a run
# without it is refused here, before anything is paid for.
case "${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-}" in
  "") refuse "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS is not set: claude -p would stop the workflow ten minutes after the launcher's last turn, with no outcome. Start claude with CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0, and let the job's own timeout bound the run" ;;
  *[!0-9]*) refuse "CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS is \"$CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS\": it takes milliseconds, 0 to wait however long the run takes" ;;
esac

# ── The base branch ───────────────────────────────────────────────────────────
#
# Passed, or chosen together with the repository by auto-dev-select, whose
# selection.json sits in the output directory. A selection made for another
# repository than this checkout is refused: the runner opened the wrong one.

# owner/repo from a remote URL, credentials dropped — as auto-dev-select.sh
# computes it, so the two compare equal.
remote_slug() {
  printf '%s' "$1" \
    | sed -E 's#^[a-zA-Z+]+://##; s#^[^@/]+@##; s#^[^/:]*\.[^/:]*[:/]##; s#^[^/:.]+:##; s#\.git$##; s#/+$##' \
    | tr '[:upper:]' '[:lower:]'
}

SELECTION="$OUTPUT_DIR/selection.json"
if [ -z "$BASE" ] && [ -f "$SELECTION" ]; then
  [ "$(jq -r '.status // ""' "$SELECTION" 2>/dev/null)" = selected ] \
    || refuse "$SELECTION does not hold a selected repository: the selection blocked, or never ran to the end"
  BASE="$(jq -r '.baseBranch // ""' "$SELECTION")"
  WANT="$(jq -r '.slug // ""' "$SELECTION")"
  HAVE="$(remote_slug "$(git remote get-url origin 2>/dev/null || true)")"
  [ -z "$WANT" ] || [ "$WANT" = "$HAVE" ] \
    || refuse "the selection chose $WANT, and this checkout is ${HAVE:-a clone with no origin}: start auto-dev in the chosen repository"
fi
[ -n "$BASE" ] || refuse "no base branch: pass baseBranch, or run /dev-setup:auto-dev-select first — the run never guesses the fork point"
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null \
  || refuse "baseBranch $BASE does not resolve in this checkout: fetch it first"

# ── The task ──────────────────────────────────────────────────────────────────

if [ "$TRACKER" = clickup ]; then
  BOARD="$(bash "$SCRIPT_DIR/auto-dev-clickup.sh" --task "$TASK_ID" --read --json)"
  BOARD_EXIT=$?
  if [ "$BOARD_EXIT" -ne 0 ]; then
    REASON="$(printf '%s' "$BOARD" | jq -r '.REASON // ""' 2>/dev/null)"
    refuse "the task could not be read from ClickUp: ${REASON:-see stderr}"
  fi
  board() { printf '%s' "$BOARD" | jq -r --arg k "$1" '.[$k] // ""'; }
  [ "$(board STATUS)" != BACKLOG ] \
    || refuse "$TASK_ID is in BACKLOG: it was never planned into a sprint, and the backlog gate needs a person — plan it into SPRINT first"
  TITLE="$(board NAME)"
  DESCRIPTION="$(board DESCRIPTION)"
  URL="$(board URL)"
  PRIORITY="$(board PRIORITY)"
else
  TITLE="$(jq -r '.task.title // ""' "$ARGS_FILE")"
  DESCRIPTION="$(jq -r '.task.description // ""' "$ARGS_FILE")"
  URL="$(jq -r '.task.url // ""' "$ARGS_FILE")"
  PRIORITY="$(jq -r '.task.priority // ""' "$ARGS_FILE")"
  [ -n "$TITLE" ] || refuse "tracker none needs the task inline: task.title is required"
fi
json_set TITLE "$TITLE"

case "$PRIORITY" in urgent|high|normal|low|"") ;; *) PRIORITY="" ;; esac

# ── The quality commands ──────────────────────────────────────────────────────

if jq -e '.stack | type == "object"' "$ARGS_FILE" >/dev/null 2>&1; then
  STACK="$(jq -c '.stack | {lint: (.lint // ""), typecheck: (.typecheck // ""), test: (.test // "")}' "$ARGS_FILE")"
  UNAVAILABLE="$(jq -c '.unavailable // [] | map(select(type == "string"))' "$ARGS_FILE")"
  UNAVAILABLE_REASON="$(arg unavailableReason)"
else
  DETECTED="$(bash "$SCRIPT_DIR/detect-stack.sh" --json)" \
    || refuse "detect-stack.sh rejected the project's quality declaration: see its stderr"
  STACK="$(printf '%s' "$DETECTED" | jq -c '{lint: .LINT_CMD, typecheck: .TYPECHECK_CMD, test: .TEST_CMD}')"
  PREFLIGHT="$(bash "$SCRIPT_DIR/quality-preflight.sh" --require-declared --allow-unavailable --json)"
  PREFLIGHT_EXIT=$?
  if [ "$PREFLIGHT_EXIT" -ne 0 ]; then
    refuse "quality-preflight.sh refused: $(printf '%s' "$PREFLIGHT" | jq -r '.REASON // "see its stderr"' 2>/dev/null)"
  fi
  UNAVAILABLE="$(printf '%s' "$PREFLIGHT" | jq -c '.UNAVAILABLE | split(" ") | map(select(. != ""))')"
  UNAVAILABLE_REASON="$(printf '%s' "$PREFLIGHT" | jq -r '[.UNAVAILABLE_REASON, .OUTPUT] | map(select(. != "")) | join("\n")')"
fi

printf '%s' "$STACK" | jq -e '[.lint, .typecheck, .test] | map(select(. != "")) | length > 0' >/dev/null \
  || refuse "no quality command: lint, typecheck and test are all empty, so the run could not verify its own work — declare them in .claude/quality-commands.json (/dev-setup:setup, step 3b)"

# ── The merge request language ────────────────────────────────────────────────

META="$(bash "$SCRIPT_DIR/mr-meta.sh" --json)" \
  || refuse "mr-meta.sh failed: the project's .claude/merge-request.json is malformed (see its stderr)"
LANGUAGE="$(printf '%s' "$META" | jq -r '.LANGUAGE // ""')"

# ── The files ─────────────────────────────────────────────────────────────────

TASK_FILE="$OUTPUT_DIR/task.md"
printf '# %s\n\n%s\n' "$TITLE" "$DESCRIPTION" > "$TASK_FILE" || refuse "cannot write $TASK_FILE"

WORKFLOW_ARGS="$(jq -nc \
  --arg taskId "$TASK_ID" --arg title "$TITLE" --arg taskFile "$TASK_FILE" \
  --arg url "$URL" --arg priority "$PRIORITY" --arg pluginRoot "$PLUGIN_ROOT" \
  --arg baseBranch "$BASE" --arg branchType "$BRANCH_TYPE" --arg language "$LANGUAGE" \
  --arg challenge "$CHALLENGE" --argjson stack "$STACK" --argjson unavailable "$UNAVAILABLE" \
  --arg unavailableReason "$UNAVAILABLE_REASON" \
  '{taskId: $taskId, title: $title, taskFile: $taskFile, url: $url, priority: $priority,
    pluginRoot: $pluginRoot, baseBranch: $baseBranch, branchType: $branchType,
    language: $language, challenge: $challenge, stack: $stack,
    unavailable: $unavailable, unavailableReason: $unavailableReason}')"
WORKFLOW_ARGS_FILE="$OUTPUT_DIR/workflow-args.json"
printf '%s\n' "$WORKFLOW_ARGS" > "$WORKFLOW_ARGS_FILE"

PLUGIN_VERSION="$(jq -r '.version // ""' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || true)"
LAUNCH_FILE="$OUTPUT_DIR/launch.json"
jq -n --arg taskId "$TASK_ID" --arg runId "$RUN_ID" --arg title "$TITLE" --arg url "$URL" \
  --arg priority "$PRIORITY" --arg tracker "$TRACKER" --arg baseBranch "$BASE" \
  --arg branchType "$BRANCH_TYPE" --arg outputDir "$OUTPUT_DIR" --arg repoRoot "$ROOT_REAL" \
  --arg pluginRoot "$PLUGIN_ROOT" --arg pluginVersion "$PLUGIN_VERSION" \
  --argjson startedAt "$(date +%s)" \
  '$ARGS.named' > "$LAUNCH_FILE"

json_set TASK_FILE "$TASK_FILE"
json_set WORKFLOW_ARGS "$WORKFLOW_ARGS"
json_set WORKFLOW_ARGS_FILE "$WORKFLOW_ARGS_FILE"
json_set LAUNCH_FILE "$LAUNCH_FILE"

finish_output
