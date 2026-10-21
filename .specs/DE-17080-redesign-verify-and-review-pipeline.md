# Spec: [dev-setup] Redesign the verify and review pipeline [DE-17080]

> Status: approved
> Task: https://app.clickup.com/t/869fb17gk
> Branch: `feat/DE-17080_redesign-the-verify-and-review-pipeline`
> Created: 2026-10-07
> Approved: 2026-10-07

## Context

Step 3 of the `sdd` closure (`templates/dev-setup/.claude/skills/sdd/reference/closure.md`) invokes `verify`, and step 4 invokes `review` after it. Each launches its own agent, and each agent builds its own diff: `agents/verify.md:53-54` runs `git diff <MERGE_BASE> --stat` and `git diff <MERGE_BASE>`, and `agents/review.md:28` runs `git diff <BASE_BRANCH>` and then "for each modified file, read the full content". The `code-reviewer` runs on `model: fable` with `effort: max` whatever the size of the diff. Its output contract has no cap on warnings and no requirement that a finding says how to prove it. Nothing re-checks a finding before it blocks the merge. The `---VERIFY-RESULT---` block in `skills/verify/reference/checks.md` lists every REQ, every test and every decision with its evidence even on a pass, and `skills/verify/SKILL.md` promises "an explicit list of what matches".

The task asks for checks that cost less, take less time and report fewer false positives. The closure should build the diff once, use the right model for each check, validate findings before they block, and get short answers back from both checks. Two outside measurements support this. Superpowers v6 measured −10% from preparing the diff once and −41% output from short reviewer answers. Anthropic's code-review plugin runs a validation agent over every finding.

One rule in `AGENTS.md` stays fixed: "an unbounded artefact is read by an agent, never by the flow". The diff never enters the main thread. Only the result blocks do.

## Requirements

- REQ-1: A new plugin script, `review-package.sh --base <ref> [--json]`, writes one file. The file holds a header with the merge base and HEAD, the commits `<base>..HEAD` (`git log --oneline`), the stat (`git diff --stat <base>`) and the diff with ten lines of context (`git diff -U10 <base>`). The diff runs against the working tree, so staged and unstaged changes to tracked files are both included, as they are today. The file lives under `state_dir review-package` (the git common directory, outside the working tree, so `git add -A` never stages it). It is named after the slugified branch, so two branches (two worktrees) get two files, and a second run on the same branch overwrites it with the current content. The script never stages. It follows the script contract and prints the keys `PACKAGE`, `MERGE_BASE`, `EMPTY`, `COMMITS`, `FILES`, `CHANGED_LINES` and `SIZE`.
- REQ-2: `EMPTY` is decided by the diff, never by the commits. `EMPTY=true` exactly when `git diff --quiet <base>` succeeds: no change between `--base` and the working tree, index included. The script then exits 0 with `EMPTY=true`, `PACKAGE=""`, `SIZE=""`, `FILES=0` and `CHANGED_LINES=0`, and leaves no package file behind for the branch. Staged or unstaged changes with no commit count as `EMPTY=false`: that is the closure's own state at step 3 (everything staged, nothing committed, HEAD at the merge base).
- REQ-3: The script fails without writing a package and with nothing on stdout when the range is not valid. That covers a `--base` that does not resolve to a commit, a missing `--base`, an unknown argument, and a run outside a git repository. It exits with a non-zero status and a stderr message that names the cause.
- REQ-4: `SIZE` is `large` when `CHANGED_LINES` (insertions + deletions from `--numstat`) is above 300 or `FILES` is above 10. Otherwise it is `small`. Both thresholds are named constants in the script.
- REQ-5: The `sdd` closure generates the diff once. Its packaging step stages with `git add -A`, then calls `check-prerequisites.sh`, then `review-package.sh --base <MERGE_BASE>` once, and passes `PACKAGE` to both checks. Neither agent can regenerate the diff: `spec-verifier` and `code-reviewer` take `PACKAGE` as input, their bodies contain no `git diff`, and their `tools:` no longer include `Bash`. A full file is read only where the ten lines of context are not enough.
- REQ-6: The closure runs verify and review in parallel. It invokes both skills in the same turn and launches `spec-verifier` and `code-reviewer` in one message. `EMPTY=true` stops the closure with "nothing to verify or review" and launches no agent. The two results are read together, in this order:
  1. verify fail → back to development; the review's findings are shown but not acted on;
  2. otherwise, review fail → fix the `CONFIRMED` violations and rerun from step 3, the packaging step;
  3. otherwise, verify pass-with-warnings → show the warnings and ask;
  4. otherwise → step 5.
- REQ-7: Invoked without a `PACKAGE` (standalone `/dev-setup:review`, or `verify` outside the closure), each skill builds the package itself with `review-package.sh --base <MERGE_BASE>`. It then proceeds the same way, and on `EMPTY=true` it launches no agent.
- REQ-8: The model follows the check and the size. `code-reviewer` defaults to `model: opus`, `effort: high`. The `review` skill passes the per-invocation `model: fable` when `SIZE` is `large`, and no override otherwise. `spec-verifier` stays `opus`/`high`. The new `finding-validator` runs on `model: sonnet`, `effort: medium`.
- REQ-9: The `code-reviewer` answer is short by contract:
  - `VIOLATIONS` holds only what would block the merge. Each entry is `[<rule file> → <heading>] <file>:<line> — <why it blocks> — proof: <how to show it>`.
  - `WARNINGS` holds at most 5 entries, most important first, each `<file>:<line> — <suggestion>`.
  - A remark that cannot be tied to a file and line is not reported.
  - The answer never lists what is fine.
- REQ-10: The review skill validates findings before they count. When `VIOLATIONS` is not empty, it launches `finding-validator` with `PACKAGE`, `RULES_DIR` and the violations as returned.
  - The validator reads each cited file and line and the cited rule heading. It returns a `---VALIDATION-RESULT---` block with `CONFIRMED` and `DISCARDED` (each discarded entry with its reason). An entry without `file:line` is discarded.
  - The review fails only on `CONFIRMED` entries.
  - When the validator returns no `---VALIDATION-RESULT---` block, every violation stands as confirmed: an error is not a pass.
  - The final report gains `Discarded: <count>`.
  - With no violations, the validator is not launched.
- REQ-11: `AGENTS.md` records a before/after measurement of closure steps 3–4, on one small branch (`SIZE=small`) and one large branch (`SIZE=large`) of the same project. Each of the four rows gives: cost in USD, duration, output tokens summed over `modelUsage` (subagents included), the `modelUsage` model keys, the `WARNINGS` count, whether every `VIOLATIONS` and `WARNINGS` entry carries `<file>:<line>`, and the commit measured.
- REQ-12: The new script and agent ship with the plugin:
  - `manifest.json` lists `review-package.sh` under `plugin_scripts` and `validate-findings.md` under `template_agents`.
  - `dist/dev-setup/` is rebuilt.
  - The script table in `AGENTS.md` names `review-package.sh` with its keys.
  - `docs/developer-guide.md` describes the closure as running verify and review in parallel.
- REQ-13: The `spec-verifier` answer is short by contract, like the `code-reviewer`'s (REQ-9). The `---VERIFY-RESULT---` block in `skills/verify/reference/checks.md` keeps `STATUS` and `SUMMARY`. It replaces the COMPLETENESS/CORRECTNESS/COHERENCE lists with one line, `COUNTS: requirements <covered>/<total> · tests <found>/<total> · decisions <followed>/<total> · Impact files <touched>/<total>`. Under `GAPS:` it lists only what fell short: partial and not-found REQs, not-found tests, Missing and Unexpected files, missing dependencies, and not-found or diverged decisions. Each entry gives its id and either the `<file>:<line>` that shows it or what is missing. A `pass` is `STATUS`, `COUNTS` and `SUMMARY`; the answer never lists what matches. How the status is classified does not change, and `skills/verify/SKILL.md`'s "Expected output" no longer promises an explicit list of what matches.

## Technical decisions

- **Where the script lives.** It sits in `templates/dev-setup/.claude/scripts/review-package.sh`, shipped as `${CLAUDE_PLUGIN_ROOT}/scripts/review-package.sh`. The task wrote `scripts/review-package.sh`, but in this repository `scripts/` holds the meta-repo tooling, and every script a flow calls lives under the template and reaches projects through `plugin_scripts` (pattern: `check-prerequisites.sh`, `task-clock.sh`). The project's layout wins. *Deviation.*
- **Reuse over new helpers.** The script sources `common.sh` and uses `die`, `require_jq`, `json_set`/`json_emit`, `state_dir` and `slugify`, the same pattern as `task-clock.sh` and `sdd-start.sh` for per-repository state outside the working tree.
  - `--base` is required. The caller already holds `MERGE_BASE` from `check-prerequisites.sh`, and resolving it a second time would duplicate `detect_base_branch`. The script verifies the ref with `git rev-parse --verify --quiet "<ref>^{commit}"`.
  - Counts come from `git diff --numstat`. A binary file counts toward `FILES` and adds 0 lines.
- **`EMPTY` comes from the diff, not the commits.** At closure step 3 nothing is committed and everything is staged (`stop-point.md`: closure 1–5 leaves "everything staged, nothing committed"; `sdd-dev` does not commit), so HEAD equals the merge base and `COMMITS=0`. An `EMPTY` built on the commit range would stop every closure. `git diff --quiet <base>` is the test, and `COMMITS` is reported, never used to decide.
- **The packaging step stages.** `git diff <commit>` never lists an untracked file. Closure step 1 stages for `simplify`, but two paths reach the package with new unstaged files: a helper `simplify` (step 2) extracts into a new file, and a review fix that reruns from step 3 (REQ-6) — e.g. the missing `.spec.ts`. Step 3 therefore opens with `git add -A`, which covers every path into it at once. The script itself never stages: a standalone `/dev-setup:review` must not modify the developer's index, so the standalone skill documents "stage first" instead. Step 1 stays, because `simplify` reads the staged change.
- **Two agents in parallel, not one merged pass.** The task allows either ("oppure almeno in parallelo"). Its Risk section says to keep the two checks independent if quality drops, and `agents/verify.md` ("What is not yours") already draws that line. Parallel launches take duration off the closure. The shared package takes the double diff off the cost. Two separate agents keep each check independent. → `toConfirm`.
- **One reading order over the two results.** Running in parallel means both results arrive together, so the closure reads them in one order (REQ-6): a verify fail wins, because fixing review findings on an implementation that does not yet meet the spec is wasted work; a review fail comes next, because it blocks the merge; a verify warning asks last.
- **Both checks answer short.** The task's outcome says both checks "restituiscono risposte brevi", and proposal 5 says "mai l'elenco di ciò che è andato bene". The verify block's only consumers are the verify skill's own fail and pass-with-warnings handling (which needs the gaps) and closure step 5's `Verify:` line (which needs the status), and no test fixes the block's shape. No ADR, rule or REGISTRY entry requires listing what matches. So REQ-13 shortens it to counts plus gaps (precedence 2).
- **One code-reviewer plus one validator, not separate narrow reviewers.** Proposal 4 asks for separate bug and rule-compliance reviewers in parallel. It is not followed. Each extra reviewer re-reads the whole package, which works against "costano meno". The `code-reviewer`'s brief is already rule compliance plus what a linter cannot see, and adding a bug-hunting reviewer widens the check beyond the task's outcome. The validation half of the proposal is kept, because it is the part the outcome promises ("convalidano le segnalazioni"). *Deviation.*
- **Model per invocation, effort per definition.** Claude Code resolves a subagent's model from the per-invocation `model` parameter first, then the frontmatter. Effort comes only from the definition: no per-call override exists. So the frontmatter default drops to the cheaper pair (`opus`, `high`), and only a `large` diff is promoted to `fable`, still at `high`. Before, every diff ran on `fable`/`max`. Large diffs now lose `max` effort. Effort tuning belongs to DE-17062. → `toConfirm`.
- **Size thresholds.** 300 changed lines and 10 files. `AGENTS.md` calls a 324-line branch the ordinary case. Ten files is several times the `quick` bar (3 files), so a branch under both thresholds is a small, local change. These are named constants, cheap to tune once the REQ-11 numbers exist.
- **The validator runs only on blocking findings.** False positives cost most in `VIOLATIONS`, because they stop the merge. Warnings are capped at five by contract and block nothing. When there are no violations, the validator costs nothing. A validator that returns no block leaves every violation standing, as `verify/SKILL.md` and `agents/review.md` already say: an error is not a pass.
- **Proof that no agent re-diffs.** The tests check for the absence of `Bash` in the agents' tools rather than trusting prose. An agent with Read, Glob and Grep cannot run `git`. The package carries the commits, so neither agent needs `git log`.
- **How the measurement is read.** The Claude Code docs say the result's `usage` covers only the main agent loop and `modelUsage` covers the whole tree. All three agents this task changes run as subagents, so output tokens are `[.modelUsage[].outputTokens] | add`. The run uses `--output-format stream-json --verbose` and a pinned `--model`, as `scripts/measure-session-zero.sh` does. The `modelUsage` keys are the only runtime evidence for REQ-8: a per-invocation model blocked by `availableModels` is replaced without notice.
- **Numbering.** The closure keeps its numbering. Step 3 becomes "Package the diff" (stage, then package) and step 4 becomes "Verify and review, in parallel". Steps 5–9, and the stop points in `stop-point.md` that cite "after step 5/6/7", stay valid.
- **`auto-sdd.js`** (the open question in the task). Its `Verify` phase runs only `LINT_CMD`/`TYPECHECK_CMD`/`TEST_CMD` and reads no diff. Neither of its launchers (`auto-sdd`, `multi-sdd`) runs `spec-verifier` or `code-reviewer`, so there is nothing for the package to replace there. The workflow is left untouched.
- **Precedence applied.**
  - Project choices (script location, agents reading unbounded artefacts, `state_dir`, the existing verify/review split, the closure's "stage, then read the diff") won over the task's build instructions (proposal 1 path, proposal 4).
  - The task's outcome (short answers from both checks) and acceptance criteria (diff once, measurement, `file:line` and at most 5 warnings, tests for empty and invalid ranges) are all delivered.

## Impact

- **Files to create**:
  - `templates/dev-setup/.claude/scripts/review-package.sh`
  - `templates/dev-setup/.claude/agents/validate-findings.md` (frontmatter `name: finding-validator`, `tools: Read, Glob, Grep`, `model: sonnet`, `effort: medium`)
  - `dist/dev-setup/scripts/review-package.sh` and `dist/dev-setup/agents/validate-findings.md` (generated)
- **Files to modify**:
  - `templates/dev-setup/.claude/agents/verify.md` (input `PACKAGE` replaces the diff step, `Bash` removed from tools)
  - `templates/dev-setup/.claude/agents/review.md` (input `PACKAGE`, `model: opus`, `effort: high`, `Bash` removed, short-answer contract)
  - `templates/dev-setup/.claude/skills/verify/reference/checks.md` (the REQ-13 result block: `COUNTS:` and `GAPS:`)
  - `templates/dev-setup/.claude/skills/verify/SKILL.md` (accepts `PACKAGE`, builds it otherwise; "Expected output" no longer promises an explicit list of what matches, which also keeps it within the 500-word budget)
  - `templates/dev-setup/.claude/skills/review/SKILL.md` (accepts `PACKAGE`/`SIZE`, builds them otherwise, `model: fable` on `large`, the validation step and its no-block rule)
  - `templates/dev-setup/.claude/skills/review/reference/registry-updates.md` (`Discarded:` line in the final report)
  - `templates/dev-setup/.claude/skills/sdd/reference/closure.md` (steps 3–4, the outcome order, and the index)
  - `templates/dev-setup/manifest.json`
  - `scripts/test-plugin-scripts.sh`
  - `AGENTS.md` (script table, the "main thread" section, the measurement, the version footer)
  - `docs/developer-guide.md` (the closure line in "A task, end to end")
  - `dist/dev-setup/**` (regenerated by `bash scripts/build-plugin.sh dev-setup`)
- **Dependencies**: none (bash + git + jq, already required)

## Implementation plan

Each step rebuilds `dist/` with `bash scripts/build-plugin.sh dev-setup` in the same commit, so the `verify` CI job stays green at every commit.

1. **`feat(scripts): add review-package.sh to build the review diff once [DE-17080]`**
   - Write the script: usage header with keys and exit statuses, `--base` required, ref validation, `state_dir review-package`, slugified branch file name, header + `## Commits` + `## Stat` + `## Diff` sections, `--numstat` counts, `SIZE` from two named constants, `EMPTY` from `git diff --quiet <base>`, and the empty path that removes any stale file for the branch. No staging.
   - Add it to `manifest.json` `plugin_scripts` and to the `AGENTS.md` script table.
   - Add the script tests (Tests 1–6, 2b, 2c) to `scripts/test-plugin-scripts.sh`.
2. **`perf(review): read the shared package in spec-verifier and code-reviewer [DE-17080]`**
   - `agents/verify.md` and `agents/review.md`: input `PACKAGE` replaces `MERGE_BASE`/`BASE_BRANCH` for the diff, the `git diff` steps go, `Bash` leaves `tools:`, and a full file is read only where the ten lines of context are not enough.
   - An unreadable `PACKAGE` returns `STATUS: error`.
   - `code-reviewer` moves to `model: opus`, `effort: high` and gets the REQ-9 contract: blocking-only violations with proof, at most 5 warnings, `file:line` on everything, nothing about what is fine.
   - `skills/verify/reference/checks.md`: the REQ-13 result block (`STATUS`, `COUNTS`, `GAPS`, `SUMMARY`). `skills/verify/SKILL.md`: "Expected output" drops "an explicit list of what matches".
   - Add Tests 7, 9 and 14.
3. **`feat(review): validate blocking findings before they fail the review [DE-17080]`**
   - Create `agents/validate-findings.md` (`finding-validator`) with its `---VALIDATION-RESULT---` contract.
   - Add it to `manifest.json` `template_agents`.
   - `skills/review/SKILL.md`: accept `PACKAGE`/`SIZE` or build them with `review-package.sh` (stage first, documented), launch `code-reviewer` with `model: fable` on `large`, then "Launch the `finding-validator` agent" when `VIOLATIONS` is not empty, decide the status on `CONFIRMED`, and keep every violation when no `---VALIDATION-RESULT---` block comes back.
   - `registry-updates.md`: add the `Discarded:` line.
   - Add Tests 10–11.
4. **`perf(sdd): package the diff once and run verify and review in parallel [DE-17080]`**
   - `closure.md`: step 3 "Package the diff" (`git add -A` → `check-prerequisites.sh` → `review-package.sh --base <MERGE_BASE>`, `EMPTY=true` stops), with one line on why: a file that `simplify` (step 2) or a review fix created is untracked until it is staged, and an untracked file has no diff. Step 4 "Verify and review, in parallel" (both skills in one turn with `PACKAGE`/`SIZE`, both agents in one message, the four-line outcome order of REQ-6). The index.
   - `skills/verify/SKILL.md`: accept `PACKAGE`, build it otherwise, stay under 500 words.
   - `docs/developer-guide.md`: the closure line.
   - `AGENTS.md`: the "What the main thread is not allowed to carry" paragraph now says both agents read one package.
   - Add Tests 8 and 12.
5. **`docs(agents): record the closure cost before and after the redesign [DE-17080]`**
   - Run the measurement in Test 13.
   - Add the four-row table (small/large × before/after: cost USD, duration, output tokens over `modelUsage`, model keys, `WARNINGS` count, `file:line` on every entry, the commit measured) to the `AGENTS.md` section on the main thread.
   - Bump the version footer from 2.26.1 to 2.27.0.
   - Add Test 15.

## Test strategy

All automated tests live in `scripts/test-plugin-scripts.sh`, in a new "review-package.sh" section. They build their fixture repository with `git_init` under `$WORK_DIR`, as the `check-prerequisites.sh` tests do. They fail on the current `next`, where the script, the new contracts and the validator do not exist.

- **Test 1 (REQ-1).** The fixture has `main` → `next` with 3 commits → `feat(x)/DE-999_work` with one commit that changes line 15 of a 30-line file, plus one staged but uncommitted new file, plus one line appended to a tracked base file and left unstaged (what `simplify` leaves after step 1's `git add -A`). Run `review-package.sh --base $(git merge-base HEAD next) --json`. The test asserts:
  - exit 0 and `EMPTY=false`;
  - `PACKAGE` exists under `$(git rev-parse --git-common-dir)/dev-setup/review-package/`, and `basename "$PACKAGE"` starts with `feat-x-de-999-work`;
  - `git status --porcelain` is unchanged by the run (the script does not stage);
  - the package contains the branch commit subject and none of `next`'s commits;
  - it contains the stat line, the staged file and the unstaged appended line;
  - line 5 of the 30-line file is present (ten lines of context) and line 4 is absent;
  - `COMMITS=1`, `FILES=3` and `CHANGED_LINES` match `--numstat`;
  - overwrite: change one tracked line between two runs; the second run returns the same `PACKAGE`, and the file holds the new line and not the old one;
  - name: a run on a second branch returns a different `PACKAGE`, and the first branch's file stays.
- **Test 2 (REQ-2).** On a clean tree, `--base HEAD` exits 0 with `EMPTY=true`, `PACKAGE=""`, `SIZE=""`, `FILES=0` and `CHANGED_LINES=0`. A package left by Test 1 for the same branch is gone.
- **Test 2b (REQ-2).** A branch cut at its base with no commit and one file staged. `--base HEAD` exits 0 with `EMPTY=false`, `COMMITS=0` and `FILES=1`, and `PACKAGE` exists and holds the staged change.
- **Test 2c (REQ-2).** One commit and its revert, on a clean tree. `--base <before the commit>` gives `EMPTY=true` and no package file.
- **Test 3 (REQ-3).** Each of these exits non-zero, prints nothing on stdout, puts a stderr message that names its cause, and leaves the review-package directory unchanged:
  - `--base does-not-exist` (stderr names the ref);
  - no `--base` (stderr names `--base`);
  - `--bogus` (stderr names `--bogus`);
  - a run in a directory that is not a repository (stderr names `git`).
- **Test 4 (REQ-4).** The size thresholds:
  - 300 changed lines in 1 file gives `SIZE=small`;
  - 301 changed lines gives `large`;
  - 10 files of one line each gives `small`;
  - 11 files gives `large`.
- **Test 5 (REQ-1, contract).** `--json` output is a flat object whose keys are exactly `PACKAGE, MERGE_BASE, EMPTY, COMMITS, FILES, CHANGED_LINES, SIZE`, all strings. `MERGE_BASE` equals `git rev-parse <base>`.
- **Test 6 (REQ-12).** `manifest.json` lists `review-package.sh` and `validate-findings.md`, and `dist/dev-setup/scripts/review-package.sh` exists. The `AGENTS.md` script table names `review-package.sh`. Check 14 resolves it.
- **Test 7 (REQ-5).** No file under `templates/dev-setup/.claude/agents/` contains `git diff`. The `tools:` frontmatter of `verify.md` and `review.md` does not contain `Bash`. Both name `PACKAGE` as an input.
- **Test 8 (REQ-5, REQ-6).** `closure.md` calls `review-package.sh` exactly once and passes `PACKAGE` to both `verify` and `review`. In step 3, `git add -A` comes before `review-package.sh`. It states that the two agents launch in one message, that `EMPTY` stops the closure, and the four outcome lines of REQ-6 in their order.
- **Test 9 (REQ-8, REQ-9).**
  - `review.md` frontmatter has `model: opus` and `effort: high`, and no `effort: max`.
  - `verify.md` keeps `model: opus` and `effort: high`.
  - The `review.md` output contract contains "at most 5", the `<file>:<line>` form in both `VIOLATIONS` and `WARNINGS`, and `proof:`.
  - `skills/review/SKILL.md` names `model: fable` together with `SIZE` `large`.
- **Test 10 (REQ-10).** `agents/validate-findings.md` exists with `name: finding-validator`, `model: sonnet`, `effort: medium` and a `---VALIDATION-RESULT---` block with `CONFIRMED` and `DISCARDED`. `skills/review/SKILL.md` contains "Launch the `finding-validator` agent", which the existing launch-name test resolves against the frontmatter. `registry-updates.md` contains `Discarded:`.
- **Test 11 (REQ-10).** The validator contract states that an entry without `file:line` is discarded. The review skill states that the status is decided on `CONFIRMED`, and that with no `---VALIDATION-RESULT---` block every violation stands.
- **Test 12 (REQ-7).** `skills/verify/SKILL.md` and `skills/review/SKILL.md` both call `review-package.sh` for the case with no `PACKAGE`. `/project:validate` (`validate-plugin.sh --strict`) passes, including the 500-word budget on `verify/SKILL.md`.
- **Test 13 (REQ-11, manual and recorded).**
  - **Setup.** Use one project set up with `dev-setup`, with a small branch (`SIZE=small`) and a large one (`SIZE=large`), each with an approved spec.
  - **Before.** Run closure steps 3–4 with the plugin built from `next` at the fork point.
  - **After.** Run them again with this branch's `dist/dev-setup`, using `claude -p --plugin-dir <dist> --output-format stream-json --verbose` and a pinned `--model`, as `scripts/measure-session-zero.sh` does.
  - **Readings.** From the last `result` line: `total_cost_usd`, `duration_ms`, output tokens as `[.modelUsage[].outputTokens] | add`, and the `modelUsage` model keys. From the code-reviewer's `---REVIEW-RESULT---` block: the `WARNINGS` count and whether every `VIOLATIONS` and `WARNINGS` entry has `<file>:<line>`.
  - **Pass condition.** The large "after" row lists the model `fable` resolves to and the small "after" row does not; the "after" rows have at most 5 warnings and `file:line` on every entry; the four rows and the commit ids are in `AGENTS.md` (Test 15).
- **Test 14 (REQ-13).** `skills/verify/reference/checks.md` contains `COUNTS:` and `GAPS:`, no longer contains `COMPLETENESS:`, and states that covered requirements, found tests and followed decisions are not listed. `skills/verify/SKILL.md` no longer contains "an explicit list of what matches".
- **Test 15 (REQ-11).** `test-plugin-scripts.sh` asserts that `AGENTS.md` holds the measurement table with the four small/large × before/after rows.

## Notes

- **Risk from the task.** If the parallel pair, the cheaper default model or the shorter verify block reports worse findings in the REQ-11 run, that is the signal to revisit the defaults. The thresholds are named constants for that reason.
- **Unchanged here.**
  - The `review` skill's own `effort: max` and the other skill-level effort settings are left for DE-17062.
  - The prompt wording beyond the result contracts is left for DE-17070.
- **Untracked files.** `git diff` never shows them, so the script does not either. The packaging step stages before it packages (step 3), so the files step 2 or a review fix created are in the package. The standalone review documents the same expectation: stage first.
- **Sandbox.** The package is written where `task-clock.sh` already writes (the git common directory), so any project where the work clock runs can write the package too.
