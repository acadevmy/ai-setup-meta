#!/usr/bin/env bash
# auto-dev-report.sh — what an auto-dev run leaves for the runner, written by a
# script rather than a model.
#
# The runner pushes the branch, opens the merge request and closes the task
# from these files alone, so they are assembled the same way every time: the
# workflow's outcome as the launcher saved it, the launch record auto-dev-args.sh
# wrote, mr-meta.sh for the title and the labels, the repository's own merge
# request template for the body. No model reads or rewrites any of it.
#
# Usage:
#   auto-dev-report.sh --outcome <outcome.json> --launch <launch.json>
#                      [--session <session id>] [--json]
#   auto-dev-report.sh --finalize --result <result.json>
#                      --claude-result <claude -p --output-format json> [--json]
#
#   --outcome        the workflow's return value, as the launcher saved it. A
#                    missing or malformed file is a run that broke: the result
#                    says `failed` at stage `broken`, with what was there
#   --launch         the record auto-dev-args.sh wrote
#   --session        the Claude Code session id: the token use of each step is
#                    read from its transcripts. Their output counts are lower
#                    bounds — a transcript line keeps the usage of the moment it
#                    was written, and the reasoning tokens never show — so
#                    `usage.outputSource` says `transcript-lower-bound`
#   --finalize       after `claude -p` has exited: reconcile the steps' output
#                    with the per-model totals of its JSON result, which are
#                    exact. Each model's reported output is spread over the
#                    steps that used it, in proportion to what their transcripts
#                    show; `usage.outputSource` becomes `reconciled`
#   --json           emit a flat JSON object
#
# Writes next to the outcome:
#   result.json   the outcome, the merge request's title and labels, the usage
#   pr-body.md    the merge request body, on ready-for-mr only
#   spec.md       the spec, when the run failed before any branch held it
#   changes.patch a failed run's uncommitted work — tracked and untracked, the
#                 ignored files left out — as a binary diff on HEAD
#                 (`git apply` on the commit in `patchBase`)
#
# A ready-for-mr outcome is checked against git first: no commit on its branch
# over the base makes it failed at stage dev, and the commit subjects in
# result.json are the ones git holds, not the ones the Dev agent reported.
#
# Keys:
#   STATUS       ready-for-mr | failed
#   STAGE        where a failed run stopped, empty otherwise
#   RESULT_FILE  result.json
#   BODY_FILE    pr-body.md, empty when none was written
#   SPEC_FILE    spec.md, empty when none was written
#   PATCH_FILE   changes.patch, empty when none was written
#   TITLE        the merge request title, empty when there is none
#   LABELS       its labels, comma-separated
#   OUTPUT_SOURCE  transcript-lower-bound | reconciled | none
#
# Exit: 0 written · 1 usage error, or a file that cannot be read or written
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
FINALIZE=false
OUTCOME=""
LAUNCH=""
SESSION=""
RESULT=""
CLAUDE_RESULT=""

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --finalize) FINALIZE=true; shift ;;
    --outcome)
      [ $# -ge 2 ] || die "--outcome requires a path"
      OUTCOME="$2"; shift 2 ;;
    --launch)
      [ $# -ge 2 ] || die "--launch requires a path"
      LAUNCH="$2"; shift 2 ;;
    --session)
      [ $# -ge 2 ] || die "--session requires an id"
      SESSION="$2"; shift 2 ;;
    --result)
      [ $# -ge 2 ] || die "--result requires a path"
      RESULT="$2"; shift 2 ;;
    --claude-result)
      [ $# -ge 2 ] || die "--claude-result requires a path"
      CLAUDE_RESULT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

finish_output() {
  if [ "$AS_JSON" = true ]; then
    json_emit
  else
    json_emit_text
  fi
}

# ── Finalize: the exact output counts, after claude -p has exited ─────────────
#
# Each model's reported total is spread over the (step, model) pairs that used
# it, in proportion to the output their transcripts show — evenly by calls when
# the transcripts show none. The input and cache counts stay as the
# transcripts recorded them: those are exact per request.

if [ "$FINALIZE" = true ]; then
  [ -f "$RESULT" ] || die "--finalize needs --result <result.json>"
  [ -f "$CLAUDE_RESULT" ] || die "--finalize needs --claude-result <the JSON claude -p printed>"
  jq -e '.modelUsage | type == "object"' "$CLAUDE_RESULT" >/dev/null 2>&1 \
    || die "$CLAUDE_RESULT has no modelUsage: run claude -p with --output-format json"

  TMP="$(mktemp "${TMPDIR:-/tmp}/auto-dev.XXXXXX")" || die "cannot create a temporary file"
  jq --slurpfile claude "$CLAUDE_RESULT" '
    ($claude[0].modelUsage) as $reported
    | (.usage.steps // {}) as $steps
    | ([ $steps | to_entries[] | .key as $step | (.value.byModel // {}) | to_entries[]
         | {step: $step, model: .key, out: (.value.output // 0), calls: (.value.calls // 0)} ]) as $pairs
    | (reduce $pairs[] as $p ({}; .[$p.model].out += $p.out | .[$p.model].calls += $p.calls)) as $seen
    | .usage.steps = ($steps | with_entries(
        .key as $step
        | .value.byModel = ((.value.byModel // {}) | with_entries(
            .key as $model
            | ($reported[$model].outputTokens // null) as $total
            | if $total == null then .
              elif ($seen[$model].out // 0) > 0
                then .value.output = ((.value.output // 0) * $total / $seen[$model].out | round)
              elif ($seen[$model].calls // 0) > 0
                then .value.output = ((.value.calls // 0) * $total / $seen[$model].calls | round)
              else . end))
        | .value.output = ([.value.byModel[].output] | add // 0)))
    | .usage.total = {
        input: ([$reported[].inputTokens // 0] | add // 0),
        cacheWrite: ([$reported[].cacheCreationInputTokens // 0] | add // 0),
        cacheRead: ([$reported[].cacheReadInputTokens // 0] | add // 0),
        output: ([$reported[].outputTokens // 0] | add // 0),
        costUSD: ($claude[0].total_cost_usd // null),
        byModel: $reported }
    | .usage.outputSource = "reconciled"
  ' "$RESULT" > "$TMP" || { rm -f "$TMP"; die "could not reconcile $RESULT"; }
  mv "$TMP" "$RESULT"

  json_set STATUS "$(jq -r '.status // ""' "$RESULT")"
  json_set RESULT_FILE "$RESULT"
  json_set OUTPUT_SOURCE reconciled
  finish_output
  exit 0
fi

# ── Report ────────────────────────────────────────────────────────────────────

[ -n "$OUTCOME" ] || die "--outcome <outcome.json> is required (see --help)"
[ -f "$LAUNCH" ] || die "--launch <launch.json> is required: auto-dev-args.sh writes it"
jq -e 'type == "object"' "$LAUNCH" >/dev/null 2>&1 || die "$LAUNCH is not a launch record"

OUT_DIR="$(cd "$(dirname "$OUTCOME")" 2>/dev/null && pwd)" || die "no directory for $OUTCOME"
RESULT_FILE="$OUT_DIR/result.json"
BODY_FILE="$OUT_DIR/pr-body.md"
SPEC_FILE="$OUT_DIR/spec.md"
PATCH_FILE="$OUT_DIR/changes.patch"
WROTE_PATCH=""
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/auto-dev.XXXXXX")" || die "cannot create a temporary directory"
trap 'rm -rf "$TMP_DIR"' EXIT

launch() { jq -r --arg k "$1" '.[$k] // ""' "$LAUNCH"; }
REPO_ROOT="$(launch repoRoot)"
TASK_ID="$(launch taskId)"

# A run that broke — no outcome at all, or not one of the two — is a failed run
# at stage broken, whose reason is what came back.
if jq -e 'type == "object" and (.status == "ready-for-mr" or .status == "failed")' "$OUTCOME" >/dev/null 2>&1; then
  cp "$OUTCOME" "$TMP_DIR/outcome.json"
else
  RAW="$(head -c 2000 "$OUTCOME" 2>/dev/null || printf 'no outcome file')"
  jq -n --arg raw "$RAW" --arg id "$TASK_ID" \
    '{status: "failed", stage: "broken", taskId: $id,
      reason: ("the workflow came back with neither outcome: " + $raw)}' > "$TMP_DIR/outcome.json"
fi
O="$TMP_DIR/outcome.json"

STATUS="$(jq -r '.status' "$O")"
BRANCH="$(jq -r '.branch // ""' "$O")"

# ── The branch, as git holds it ───────────────────────────────────────────────
#
# The outcome carries what the Dev agent said it committed; the runner pushes
# what git holds. On job ad-dry-10281136 the commit gate refused the one commit
# and the run still came back ready-for-mr, with the work staged and the branch
# identical to its base. So git decides: a branch with no commit over the base
# is a failed run at stage dev, and the commit subjects come from git.

BASE="$(jq -r '.baseBranch // ""' "$O")"
[ -n "$BASE" ] || BASE="$(launch baseBranch)"
in_repo() { git -C "$REPO_ROOT" "$@"; }
HAS_REPO=false
if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] && in_repo rev-parse --git-dir >/dev/null 2>&1; then
  HAS_REPO=true
fi

if [ "$STATUS" = ready-for-mr ]; then
  NO_COMMIT=""
  if [ "$HAS_REPO" != true ]; then
    NO_COMMIT="the repository ${REPO_ROOT:-(none)} is not here to check the branch in"
  elif [ -z "$BRANCH" ] || ! in_repo rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
    NO_COMMIT="the branch ${BRANCH:-(none)} does not exist"
  elif [ -z "$BASE" ] || ! in_repo rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    NO_COMMIT="the base ${BASE:-(none)} does not resolve here"
  elif [ "$(in_repo rev-list --count "$BASE..refs/heads/$BRANCH")" = 0 ]; then
    NO_COMMIT="the branch $BRANCH holds no commit over $BASE: the work was not committed"
  fi

  if [ -n "$NO_COMMIT" ]; then
    jq --arg r "$NO_COMMIT" '.status = "failed" | .stage = "dev" | .reason = $r' "$O" > "$TMP_DIR/checked.json" \
      && mv "$TMP_DIR/checked.json" "$O" || die "cannot rewrite the outcome"
    STATUS=failed
  else
    in_repo log --reverse --format=%s "$BASE..refs/heads/$BRANCH" \
      | jq -R . | jq -s . > "$TMP_DIR/commits.json" \
      && jq --slurpfile c "$TMP_DIR/commits.json" '.commits = $c[0]' "$O" > "$TMP_DIR/checked.json" \
      && mv "$TMP_DIR/checked.json" "$O" || die "cannot rewrite the outcome"
  fi
fi

# A failed run's uncommitted work is saved as a patch on HEAD, so the machine
# can go without taking it along. The index is a scratch copy: the checkout is
# left exactly as the run left it.
PATCH_BASE=""
if [ "$STATUS" = failed ] && [ "$HAS_REPO" = true ] && PATCH_BASE="$(in_repo rev-parse --verify --quiet HEAD)"; then
  export GIT_INDEX_FILE="$TMP_DIR/index"
  if in_repo read-tree HEAD && in_repo add -A >/dev/null 2>&1 \
     && in_repo diff --cached --binary HEAD > "$TMP_DIR/changes.patch"; then
    [ -s "$TMP_DIR/changes.patch" ] && cp "$TMP_DIR/changes.patch" "$PATCH_FILE" && WROTE_PATCH="$PATCH_FILE"
  else
    warn "could not save the uncommitted work of $REPO_ROOT as a patch"
  fi
  unset GIT_INDEX_FILE
fi
[ -n "$WROTE_PATCH" ] || PATCH_BASE=""

# ── The merge request: title and labels ───────────────────────────────────────

TITLE=""
LABELS=""
LANGUAGE=""
TEMPLATE=""
UNCHECKED_AT_COMMIT=""
SUMMARY="$(jq -r '.mr.summary // ""' "$O")"
if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ]; then
  MR_ARGS=(--json)
  [ -n "$BRANCH" ] && MR_ARGS+=(--branch "$BRANCH")
  [ -n "$SUMMARY" ] && MR_ARGS+=(--summary "$SUMMARY")
  PRIORITY="$(launch priority)"
  [ -n "$PRIORITY" ] && MR_ARGS+=(--priority "$PRIORITY")
  if META="$(cd "$REPO_ROOT" && bash "$SCRIPT_DIR/mr-meta.sh" "${MR_ARGS[@]}")"; then
    TITLE="$(printf '%s' "$META" | jq -r '.TITLE // ""')"
    LABELS="$(printf '%s' "$META" | jq -r '.LABELS // ""')"
    LANGUAGE="$(printf '%s' "$META" | jq -r '.LANGUAGE // ""')"
    TEMPLATE="$(printf '%s' "$META" | jq -r '.TEMPLATE // ""')"
    UNCHECKED_AT_COMMIT="$(printf '%s' "$META" | jq -r '.UNCHECKED_AT_COMMIT // ""')"
  else
    warn "mr-meta.sh failed: the result carries no merge request title or labels"
  fi
fi

# ── Usage, from the session's transcripts ─────────────────────────────────────
#
# A step is recognised by the first line its prompt opens with, which this
# plugin's workflow writes; the session's own transcript is the launcher. Per
# request, the largest count any of its lines carries is kept.

USAGE='{"steps": {}, "total": null, "outputSource": "none"}'
if [ -n "$SESSION" ]; then
  CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  MAIN="$(find "$CONFIG_DIR/projects" -maxdepth 2 -name "$SESSION.jsonl" 2>/dev/null | head -1)"
  if [ -z "$MAIN" ]; then
    warn "no transcript for session $SESSION under $CONFIG_DIR/projects: the result carries no usage"
  else
    : > "$TMP_DIR/files"
    printf '%s\n' "$MAIN" >> "$TMP_DIR/files"
    if [ -d "${MAIN%.jsonl}" ]; then
      find "${MAIN%.jsonl}" -name '*.jsonl' ! -name 'journal.jsonl' >> "$TMP_DIR/files" 2>/dev/null
    fi
    : > "$TMP_DIR/per-file.jsonl"
    while IFS= read -r FILE; do
      [ -n "$FILE" ] || continue
      IS_MAIN=false
      [ "$FILE" = "$MAIN" ] && IS_MAIN=true
      jq -cs --argjson main "$IS_MAIN" '
        . as $all
        | ([$all[] | select(.type == "user")] | first | .message.content
           | if type == "string" then . elif type == "array" then (map(select(.type == "text") | .text) | join("\n")) else "" end
          ) as $first
        | (if $main then "launcher"
           elif ($first // "" | contains("You are writing the technical spec")) then "spec"
           elif ($first // "" | contains("You review a technical spec")) then "challenge"
           elif ($first // "" | contains("You wrote the technical spec below")) then "revise"
           elif ($first // "" | contains("Implement one task in the repository")) then "dev"
           elif ($first // "" | contains("Run the quality commands of this project")) then "verify"
           else "other" end) as $step
        | [$all[] | select(.type == "assistant" and .message.id != null and .message.usage != null)
           | {id: .message.id, model: (.message.model // "unknown"), u: .message.usage}]
        | group_by(.id)
        | map({model: .[0].model,
               input: (map(.u.input_tokens // 0) | max),
               cacheWrite: (map(.u.cache_creation_input_tokens // 0) | max),
               cacheRead: (map(.u.cache_read_input_tokens // 0) | max),
               output: (map(.u.output_tokens // 0) | max)})
        | group_by(.model)
        | map({step: $step, model: .[0].model, calls: length,
               input: (map(.input) | add), cacheWrite: (map(.cacheWrite) | add),
               cacheRead: (map(.cacheRead) | add), output: (map(.output) | add)})
        | .[]
      ' "$FILE" >> "$TMP_DIR/per-file.jsonl" 2>/dev/null || warn "could not read the transcript $FILE"
    done < "$TMP_DIR/files"

    USAGE="$(jq -cs '
      def sum(k): map(.[k]) | add // 0;
      (group_by(.step) | map({key: .[0].step, value: {
          calls: sum("calls"), input: sum("input"), cacheWrite: sum("cacheWrite"),
          cacheRead: sum("cacheRead"), output: sum("output"),
          models: (map(.model) | unique),
          byModel: (group_by(.model) | map({key: .[0].model, value: {
            calls: sum("calls"), input: sum("input"), cacheWrite: sum("cacheWrite"),
            cacheRead: sum("cacheRead"), output: sum("output")}}) | from_entries)}})
       | from_entries) as $steps
      | {steps: $steps,
         total: {calls: sum("calls"), input: sum("input"), cacheWrite: sum("cacheWrite"),
                 cacheRead: sum("cacheRead"), output: sum("output")},
         outputSource: "transcript-lower-bound"}
    ' "$TMP_DIR/per-file.jsonl")"
  fi
fi

# ── result.json ───────────────────────────────────────────────────────────────

NOW="$(date +%s)"
jq -n --slurpfile o "$O" --slurpfile l "$LAUNCH" --argjson usage "$USAGE" \
  --arg title "$TITLE" --arg labels "$LABELS" --arg language "$LANGUAGE" --arg template "$TEMPLATE" \
  --arg unchecked "$UNCHECKED_AT_COMMIT" \
  --arg body "$( [ "$STATUS" = ready-for-mr ] && printf '%s' "$BODY_FILE" )" \
  --arg patch "$WROTE_PATCH" --arg patchBase "$PATCH_BASE" \
  --argjson now "$NOW" '
  ($o[0]) as $o | ($l[0]) as $l
  | {
      status: $o.status,
      stage: ($o.stage // ""),
      reason: ($o.reason // ""),
      taskId: ($o.taskId // $l.taskId),
      runId: ($l.runId // ""),
      branch: ($o.branch // ""),
      baseBranch: ($o.baseBranch // $l.baseBranch),
      commits: ($o.commits // []),
      filesChanged: ($o.filesChanged // []),
      spec: {path: ($o.spec.path // ""), reqs: ($o.spec.reqs // [])},
      contextPack: ($o.contextPack // []),
      challenge: ($o.challenge // null),
      toConfirm: ($o.toConfirm // []),
      deviations: ($o.deviations // []),
      openPoints: ($o.openPoints // []),
      applied: ($o.applied // []),
      unchecked: ($o.unchecked // []),
      unverified: ($o.unverified // []),
      checks: {ran: ($o.ran // []), absent: ($o.absent // []), output: ($o.output // "")},
      notes: ($o.notes // ""),
      patchFile: $patch,
      patchBase: $patchBase,
      mr: {title: $title, labels: ($labels | split(",") | map(select(. != ""))),
           language: $language, template: $template, bodyFile: $body,
           summary: ($o.mr.summary // ""),
           uncheckedAtCommit: ($unchecked | split("\n") | map(select(. != "")))},
      usage: $usage,
      startedAt: ($l.startedAt // null),
      finishedAt: $now,
      durationSeconds: (if $l.startedAt then $now - $l.startedAt else null end),
      pluginVersion: ($l.pluginVersion // "")
    }' > "$RESULT_FILE" || die "cannot write $RESULT_FILE"

# ── spec.md: the spec of a run that failed before any branch held it ──────────

WROTE_SPEC=""
if jq -e '.spec.markdown | type == "string" and . != ""' "$O" >/dev/null 2>&1; then
  jq -r '.spec.markdown' "$O" > "$SPEC_FILE" && WROTE_SPEC="$SPEC_FILE"
fi

# ── pr-body.md ────────────────────────────────────────────────────────────────
#
# What run-outcomes.md says this kind of run owes a reviewer who was not
# watching goes first — what nobody verified, what nobody confirmed, what the
# Challenge left open — then the repository's own template, with its
# description and test sections filled in and every other section left as the
# team wrote it.

WROTE_BODY=""
if [ "$STATUS" = ready-for-mr ]; then
  if [ "$LANGUAGE" = it ]; then
    LABELS_JSON='{
      "uncheckedAtCommit": "Test non completati al commit",
      "uncheckedAtCommitIntro": "Il gate del commit ha esaurito il tempo e ha lasciato passare il commit prima che questi controlli finissero. L'\''output dei comandi di qualità più sotto viene dalla verifica del run.",
      "notVerified": "Non verificato",
      "notVerifiedIntro": "Questi comandi non sono stati eseguiti da questo run: chi fa il merge li esegue, o aspetta la CI.",
      "toConfirm": "Da confermare",
      "toConfirmIntro": "Scelte che il run ha fatto al posto del task: nessuno le ha ancora viste.",
      "reading": "Lettura scelta", "deviation": "Scostamento dal task",
      "openPoints": "Punti aperti", "suggested": "Proposta", "grounds": "Fondamento",
      "answer": "Risposta della spec", "noAnswer": "nessuna risposta",
      "applied": "Challenge: proposte applicate alla spec", "skipped": "Challenge non eseguita",
      "unchecked": "Focus mai verificati, il reviewer non ha risposto",
      "terminal": "Da terminale", "app": "Nell'\''applicazione", "output": "Output dei comandi di qualità",
      "noOutput": "Nessun comando è stato eseguito: vedi Non verificato.",
      "description": "Descrizione", "test": "Come è stata testata?", "task": "Task",
      "by": "Aperta da auto-dev"
    }'
  else
    LABELS_JSON='{
      "uncheckedAtCommit": "Tests not completed at commit",
      "uncheckedAtCommitIntro": "The commit gate ran out of time and let the commit through before these checks finished. The quality commands output further down comes from the run'\''s own verification.",
      "notVerified": "Not verified",
      "notVerifiedIntro": "These commands did not run in this run: whoever merges runs them, or waits for the CI.",
      "toConfirm": "To confirm",
      "toConfirmIntro": "Choices the run made on the task'\''s behalf: nobody has seen them yet.",
      "reading": "Reading taken", "deviation": "Departure from the task",
      "openPoints": "Open points", "suggested": "Suggested", "grounds": "Grounds",
      "answer": "The spec'\''s answer", "noAnswer": "no answer",
      "applied": "Challenge: proposals applied to the spec", "skipped": "Challenge not run",
      "unchecked": "Focuses never checked, the reviewer did not answer",
      "terminal": "From the terminal", "app": "In the application", "output": "Quality commands output",
      "noOutput": "No command ran: see Not verified.",
      "description": "Description", "test": "How was it tested?", "task": "Task",
      "by": "Opened by auto-dev"
    }'
  fi

  jq -r --argjson L "$LABELS_JSON" --arg unchecked "$UNCHECKED_AT_COMMIT" '
    [ (if $unchecked != "" then
         "## \($L.uncheckedAtCommit)\n\n\($L.uncheckedAtCommitIntro)\n\n"
         + ($unchecked | split("\n") | map(select(. != "") | "- " + .) | join("\n"))
       else empty end),
      (if (.unverified // []) | length > 0 then
         "## \($L.notVerified)\n\n\($L.notVerifiedIntro)\n\n"
         + (.unverified | map("- **\(.kind)** `\(.command)` — \(.reason)") | join("\n"))
       else empty end),
      (if ((.toConfirm // []) + (.deviations // [])) | length > 0 then
         "## \($L.toConfirm)\n\n\($L.toConfirmIntro)\n\n"
         + (((.toConfirm // []) | map("- \($L.reading): \(.)"))
            + ((.deviations // []) | map("- \($L.deviation): \(.)")) | join("\n"))
       else empty end),
      (if (.openPoints // []) | length > 0 then
         "## \($L.openPoints)\n\n"
         + (.openPoints | map("- **[\(.lens)]** \(.reason)\n  - \($L.suggested): \(.suggestion // "—")\n  - \($L.grounds): \(.grounds // "—")\n  - \($L.answer): \(if (.answer // "") == "" then $L.noAnswer else .answer end)") | join("\n"))
       else empty end),
      ( [ (if (.challenge.ran // false) then "\($L.applied): \((.applied // []) | length)."
           elif (.challenge.skipped // "") != "" then "\($L.skipped): \(.challenge.skipped)."
           else empty end),
          (if (.unchecked // []) | length > 0 then "\($L.unchecked): \(.unchecked | join(", "))." else empty end)
        ] | map("> " + .) | join("\n") | select(. != "") )
    ] | join("\n\n")' "$O" > "$TMP_DIR/top.md"

  jq -r --argjson L "$LABELS_JSON" --arg url "$(launch url)" '
    (.mr.description // "") + "\n\n"
    + "**Issue:** " + (if $url != "" then "[\(.taskId)](\($url))" else .taskId end) + "\n"
    + "**Spec:** `\(.spec.path // "")`"' "$O" > "$TMP_DIR/description.md"

  jq -r --argjson L "$LABELS_JSON" '
    [ (if (.mr.howToTest.terminal // []) | length > 0 then
         "**\($L.terminal)**\n\n```bash\n" + (.mr.howToTest.terminal | join("\n")) + "\n```"
       else empty end),
      (if (.mr.howToTest.app // []) | length > 0 then
         "**\($L.app)**\n\n" + (.mr.howToTest.app | to_entries | map("\(.key + 1). \(.value)") | join("\n"))
       else empty end),
      "**\($L.output)**\n\n"
      + (if (.output // "") != "" then "```text\n" + .output + "\n```" else $L.noOutput end)
    ] | join("\n\n")' "$O" > "$TMP_DIR/test.md"

  printf '## %s\n\n- [%s](%s)\n' "$(printf '%s' "$LABELS_JSON" | jq -r .task)" "$TASK_ID" "$(launch url)" > "$TMP_DIR/task.md"

  # The repository's template, its description and test sections replaced; with
  # no template, the fallback body of vcs-ops' merge-request.md, shortened to
  # what this run can fill.
  TEMPLATE_PATH=""
  [ -n "$TEMPLATE" ] && [ -f "$REPO_ROOT/$TEMPLATE" ] && TEMPLATE_PATH="$REPO_ROOT/$TEMPLATE"
  DESC_HEADING="$(printf '%s' "$LABELS_JSON" | jq -r .description)"
  TEST_HEADING="$(printf '%s' "$LABELS_JSON" | jq -r .test)"

  {
    if [ -s "$TMP_DIR/top.md" ]; then
      cat "$TMP_DIR/top.md"
      printf '\n\n'
    fi
    if [ -n "$TEMPLATE_PATH" ]; then
      awk -v desc="$TMP_DIR/description.md" -v test="$TMP_DIR/test.md" \
          -v desc_heading="$DESC_HEADING" -v test_heading="$TEST_HEADING" '
        function emit(file,   line) {
          print ""
          while ((getline line < file) > 0) print line
          close(file)
          print ""
        }
        /^## / {
          skipping = 0
          low = tolower($0)
          if (!desc_done && low ~ /^##[ \t]+(descrizione|description|what changed|cosa cambia)/) {
            print; emit(desc); desc_done = 1; skipping = 1; next
          }
          if (!test_done && low ~ /^##[ \t]+(come .*test|how .*test)/) {
            print; emit(test); test_done = 1; skipping = 1; next
          }
        }
        skipping { next }
        { print }
        END {
          if (!desc_done) { print ""; print "## " desc_heading; emit(desc) }
          if (!test_done) { print ""; print "## " test_heading; emit(test) }
        }' "$TEMPLATE_PATH"
    else
      printf '## %s\n\n' "$DESC_HEADING"
      cat "$TMP_DIR/description.md"
      printf '\n\n## %s\n\n' "$TEST_HEADING"
      cat "$TMP_DIR/test.md"
      printf '\n\n'
      cat "$TMP_DIR/task.md"
    fi
    printf '\n---\n%s · %s\n' "$(printf '%s' "$LABELS_JSON" | jq -r .by)" "$(launch runId)"
  } > "$BODY_FILE" || die "cannot write $BODY_FILE"
  WROTE_BODY="$BODY_FILE"
fi

json_set STATUS "$STATUS"
json_set STAGE "$(jq -r '.stage // ""' "$O")"
json_set RESULT_FILE "$RESULT_FILE"
json_set BODY_FILE "$WROTE_BODY"
json_set SPEC_FILE "$WROTE_SPEC"
json_set PATCH_FILE "$WROTE_PATCH"
json_set TITLE "$TITLE"
json_set LABELS "$LABELS"
json_set OUTPUT_SOURCE "$(printf '%s' "$USAGE" | jq -r '.outputSource')"

finish_output
