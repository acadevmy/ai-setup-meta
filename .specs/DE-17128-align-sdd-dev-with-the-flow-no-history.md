# Spec: [dev-setup] Align sdd-dev with the flow's stops and the autonomous run, and take the history out of the instructions [DE-17128]

> Status: approved
> Task: https://app.clickup.com/t/869fcez3y
> Branch: fix/DE-17128_align-sdd-dev-with-the-flow-no-history
> Created: 2026-10-12
> Approved: 2026-10-12 — approval is the review that runs next in this flow

## Context

The prompt audit of 2026-10-06 on `next` (03312d4) found that the prose the
`sdd-dev` skill and the dev agent of `auto-sdd.js` both read —
`templates/dev-setup/.claude/skills/sdd-dev/reference/methodologies.md` — still
asks for confirmations the flow removed with DE-16480 and DE-17076, and
restates `detect-stack.sh` with a table that no longer matches the script it
calls authoritative. The same audit found six places where an instruction tells
the model what the flow *used to* do before stating what it does now, and one
rule shouted in bold without its reason.

Four facts of the repository frame the fix:

- **The stops are fixed and counted.** `sdd/SKILL.md` declares three stops
  (launch, discovery, spec approval — DE-17076), enumerates the conditional
  ones (picking a task, the backlog gate) and says "`sdd-dev`'s summary is not
  a stop". `sdd-dev/SKILL.md` already says "Do not ask the developer to confirm
  the breakdown". A reference that says "present the scenarios to the
  developer before implementing them" adds a stop the skill does not declare
  in the interactive flow and a wait nobody answers in the autonomous one.
- **The quality commands come from the script, and an empty one is reported,
  never asked.** `detect-stack.sh` (lines 309–377) resolves `TEST_CMD`,
  `LINT_CMD` and `TYPECHECK_CMD`: `run_prefix` for pnpm/yarn/npm, `npx vitest
  run`, `npx jest`, `npx eslint .`, `flake8`, `tool.pytest.ini_options`,
  Nx/Turbo `run-many`. Everything downstream already treats an empty value the
  same way: `gate-commit.sh` (lines 216–227) skips it and says so on stderr,
  the dev agent prompt in `auto-sdd.js` says "skip it, do not substitute your
  own", the verify agent lists it in `absent`, the setup summary prints
  `Test runner: <TEST_CMD>` as it is (`existing.md`), and the `sdd-dev` summary
  has `Tests:` / `Linter:` lines. The table in `methodologies.md` names none of
  the script's commands, and its closing "ask the developer which commands to
  use" is the fallback of the prose detection `sdd-dev` performed itself
  before e2fbe98 — it outlived the script that replaced it.
- **The autonomous flow never waits.** `turn-discipline.md` ("Where this does
  not apply") says an autonomous flow finishes or bails out.
- **The suite matches raw text.** `assert_contains` in
  `scripts/test-plugin-scripts.sh` is a `case *"$needle"*` on `$(cat file)`,
  and two of the sentences this task has to keep are wrapped across a line in
  `closure.md` today, so a prose assertion has to read the file with its
  newlines folded or it is red whatever the edit does.

The rationale behind each rule is kept where the maintainers read it —
`AGENTS.md` ("What the interactive flow stopped doing (DE-16480)") and the
commits — and is removed from the files the model reads on every run: a
sentence that narrates steps the model has never seen is a sentence it can
re-perform.

Related: DE-17070 (the broader prompt audit). This spec covers only the defects
the audit listed under DE-17128.

## Requirements

- REQ-1: Neither `sdd-dev` nor the dev agent of `auto-sdd` stops to have the
  BDD scenarios confirmed. `methodologies.md` tells whoever writes the code to
  write the scenarios into the test names before implementing them, and no
  file under `skills/sdd-dev/` asks to present them to the developer.
- REQ-2: `methodologies.md` lists no per-stack commands. It points at
  `detect-stack.sh --json` as the one source of `TEST_CMD`, `LINT_CMD` and
  `TYPECHECK_CMD` and carries no table of stack markers.
- REQ-3: `methodologies.md` states one rule for an empty quality command, the
  same in both flows and the one `gate-commit.sh` and the dev agent of
  `auto-sdd.js` already apply: an empty `TEST_CMD`, `LINT_CMD` or
  `TYPECHECK_CMD` is a command the project does not define — run nothing for
  it, never substitute one of your own, and report it as not defined where the
  step reports (the `Tests:` / `Linter:` lines of the `sdd-dev` summary;
  `notes` in the autonomous run). Nothing under `skills/sdd-dev/` asks the
  developer which commands to use, and nothing is conditioned on both commands
  being empty.
- REQ-4: The dev agent prompt in `auto-sdd.js` tells the agent to report, in
  `notes`, every quality command it skipped because the project does not
  define it: the prompt the dev agent receives when every command is empty
  carries `say so in \`notes\`` next to `test: (none)`, and the workflow still
  compiles the way the harness compiles it.
- REQ-5: The six history narratives the audit listed are gone and the rule each
  one carried stays:
  - `sdd-dev/SKILL.md` §2 — keep "Do not ask the developer to confirm the
    breakdown or its order"; drop "re-litigating it here was a second approval
    wearing a different hat";
  - `sdd-dev/SKILL.md` §4 — keep "Do not commit, simplify or touch the spec's
    status"; drop "doing any of it here once cost a task four commits";
  - `sdd/reference/closure.md` intro — keep "the gates run before the commit,
    and there is one commit" and its two reasons; drop "the three bookkeeping
    commits this flow used to mandate (…)";
  - `sdd/reference/closure.md` §2 — keep "This is the only place `simplify`
    runs in the flow"; drop "`sdd-dev` no longer calls it";
  - `sdd-spec/reference/spec-template.md` — keep "Nothing in here records how
    the run went"; drop "The `## Simplify phase` and `## Review phase` sections
    this template used to carry…";
  - `review/reference/registry-updates.md` — keep "Leave the change in the
    working tree — do not commit it" and the two cases (inside the flow, on
    its own); drop "the `docs(registry): update REGISTRY.md` commit this
    reference used to mandate was the second of three bookkeeping commits";
  - `setup/reference/mcp-env.md` Step 7b — keep "they are settings on the host,
    so this step sets them there"; drop "used to be two bullets in a governance
    document nobody could enforce".
- REQ-6: `grep -rln "used to\|no longer\|once cost"` over the prose the model
  reads — `templates/dev-setup/.claude/skills`,
  `templates/dev-setup/.claude/reference`, `templates/dev-setup/.claude/agents`
  and `templates/dev-setup/setup` — matches exactly three files, none of them
  an instruction about a past behaviour:
  `.claude/reference/fork-point.md` ("a choice that no longer has an effect" —
  a present-tense fact about an existing branch),
  `setup/reference/rules-generation.md` ("a stack this project no longer has",
  "no longer read by anything" — present-tense facts reported to the
  developer) and `setup/reference/agents-generation.md` (kept by the task's
  own assumption: UPDATE uses it to recognise the old `## Workflows` table).
  The prose this task writes — `methodologies.md`, `install.md` §3.2 — carries
  none of the three phrases.
- REQ-7: `setup/reference/install.md` §3.2 states the verbatim-write rule with
  its reason and without the `**IMPORTANT**` marker: the files are written
  exactly as received because the later steps read them back by their content
  (`migrate-settings.sh` recognises an old `settings.json` by its shape — 3.2b;
  the review finds `REGISTRY.md`'s sections and `_No ... registered._`
  placeholders by their text). The paragraph carries the phrases `exactly as
  received` and `read them back`, and none of `used to`, `no longer`, `once
  cost`.
- REQ-8: The static checks stay green: `bash scripts/validate-plugin.sh
  --strict` exits 0 — every `SKILL.md` touched within 500 lines / 500 words,
  check 16 (every setup step that asks says what it reports) unaffected by the
  edits to `mcp-env.md` and `install.md` — and
  `scripts/validate-baseline.txt` stays empty.
- REQ-9: `dist/dev-setup/` is regenerated by `scripts/build-plugin.sh
  dev-setup`, never edited by hand, and `git diff --quiet -- dist/
  .claude-plugin/` is clean after the build (the `verify` CI job).

## Technical decisions

- **Prose edits plus one prompt line; no new script, no new check.** Every
  defect is a sentence in a file the model reads, and the repository already
  pins prose with grep assertions in `scripts/test-plugin-scripts.sh`
  (section 9, "the slimmed interactive flow"). The same mechanism pins this
  task; no new validation check is added to `validate-plugin.sh`, because a
  generic "no history" check would need a judgement a grep cannot make (see
  REQ-6's allowlist).
- **REQ-3 is one rule, not two.** The task's "in un flusso interattivo si
  chiede" is overruled under precedence 1 by `sdd/SKILL.md` (three stops, the
  conditional ones enumerated — picking a task, the backlog gate — and
  "`sdd-dev`'s summary is not a stop"), by `gate-commit.sh` (an empty command
  is skipped and reported, never asked), by `detect-stack.sh` as the single
  source (`AGENTS.md` §"The plugin's scripts and hooks": deterministic work
  lives in scripts, not in prose re-interpreted on every run) and by the
  setup, which already reports an empty `TEST_CMD` in its summary. The ask was
  the fallback of the prose detection `sdd-dev` did before e2fbe98 and
  outlived the script that replaced it; a command named in chat would be
  checked by `sdd-dev` and by nothing downstream — the gate, the closure and
  the autonomous run all read the script. The task's acceptance criteria
  promise the skip-and-report behaviour for the workflow and nothing about an
  interactive ask, and no page under `docs/` or `README.md` describes the ask,
  so the change owes no doc edit (checks 14–15 unaffected). Listed in
  `deviations`. Because the task's own risk names `AGENTS.md` as the home of
  the "why", one bullet goes under §"What the interactive flow stopped doing
  (DE-16480)": the quality-command question — an empty command is reported,
  not asked (DE-17128). One bullet is not a substantial change, so the version
  line of `AGENTS.md` is left alone.
- **REQ-4 adds four words to the existing prompt line, not a new field.** The
  dev agent prompt already says "skip it, do not substitute your own"; it now
  also says "say so in `notes`". `notes` already exists in `DEV_SCHEMA` ("what a
  reviewer has to know") and is carried to the outcome as `notes`, and the
  verify agent's `absent` already reaches the outcome — so the acceptance
  criterion is met with no schema change and no change to `run-outcomes.md`.
  The `meta` literal and the phases are untouched (rule 1 and 3 of "Three
  rules for changing a workflow" in `AGENTS.md`). The proof is behavioural:
  the stubbed-agent simulation the suite already runs for the Challenge phase
  (`workflow-sim.cjs`) passes no `stack`, so the dev prompt it captures prints
  `(none)` for every command — the acceptance criterion's exact precondition.
- **The table is removed, not corrected.** The task prescribes it and the
  architecture agrees: `detect-stack.sh` is the single home for the resolution
  (its header says it "replaces the prose detection the setup skill used to
  re-interpret on every run"). A corrected table would drift again on the next
  change to the script.
- **The rule stays, the story goes, the "why" lives in `AGENTS.md`.** The task's
  risk — losing the rationale — is covered because `AGENTS.md` §"What the
  interactive flow stopped doing (DE-16480)" already records the three
  bookkeeping commits, the second `simplify` run and the spec sections, and
  `docs/migration-v2-to-v3.md` records them for the projects. The one addition
  is the bullet REQ-3 earns (above).
- **The reason given in `install.md` names what actually reads the files.**
  §3.2's own conflict detection is existence-based ("if it does [exist], tell
  the developer and keep the existing one"), so a reason that says the setup
  compares content with the template would describe a comparison it does not
  make. What does read the files back by content is `migrate-settings.sh`
  (an old `settings.json` is told from the team's by its shape, 3.2b) and the
  review (`registry-updates.md` step 2 finds the `_No ... registered._`
  placeholder by its text). The sentence also has to stay out of the task's
  acceptance grep: this task writes new prose into a file that grep covers,
  and "can no longer be told apart" would make it fail its own criterion.
- **Prose assertions read a whitespace-folded file.** A kept sentence is found
  wherever markdown wraps it, and a removed phrase cannot pass vacuously
  because a later edit wrapped it. One helper in section 9 of the suite, used
  by every needle this task adds.
- **`agents-generation.md` is not touched.** Its "no longer commands" sentence
  is the recognition rule UPDATE applies to an old `AGENTS.md` (the task's own
  assumption), so it is an instruction about the present, not a narrative.
- **`turn-discipline.md:18-20` is kept as it is.** The task asks for a
  verification, not a change. Verified: the sentence dates from the first
  version of the sdd skills (a6a5df2, PR #10), where it read "respond with
  `{"ok": true}`" — a defence against a Stop-hook protocol the plugin never
  shipped — and was rewritten to "ignore it" in 42ee328 and e2fbe98. No hook in
  `templates/dev-setup/.claude/hooks/` emits an "incomplete work" message, and
  no incident is recorded for it. It is listed under `## Notes` and in
  `toConfirm` for the reviewer; the spec leaves the line because the task
  proposes no change and a project's own Stop hook can still produce the
  signal it guards against.
- **Commit type.** `fix(<scope>)`: these are prompt defects found by an audit,
  user-visible as behaviour (an undeclared stop, a wait in the autonomous run).
  Every subject carries `[DE-17128]`.

## Impact

- **Files to create**: none
- **Files to modify**:
  - `templates/dev-setup/.claude/skills/sdd-dev/reference/methodologies.md`
  - `templates/dev-setup/.claude/workflows/auto-sdd.js` (the dev agent prompt only, inside `phase('Dev')`)
  - `templates/dev-setup/.claude/skills/sdd-dev/SKILL.md`
  - `templates/dev-setup/.claude/skills/sdd/reference/closure.md`
  - `templates/dev-setup/.claude/skills/sdd-spec/reference/spec-template.md`
  - `templates/dev-setup/.claude/skills/review/reference/registry-updates.md`
  - `templates/dev-setup/setup/reference/mcp-env.md`
  - `templates/dev-setup/setup/reference/install.md`
  - `AGENTS.md` (one bullet under §"What the interactive flow stopped doing (DE-16480)")
  - `scripts/test-plugin-scripts.sh` (the `flat` helper and the new assertions in section 9; the `devAbsent` field in the stubbed-agent simulation and its assertion)
  - `dist/dev-setup/**` — regenerated by `bash scripts/build-plugin.sh dev-setup` only (`.claude/rules/dist-readonly.md`)
- **Dependencies**: none

## Implementation plan

1. **Pin the task in the bash suite (red)** — in
   `scripts/test-plugin-scripts.sh`, section 9 ("the slimmed interactive
   flow"), add once the whitespace-folding helper
   `flat() { tr '\n' ' ' < "$1" | tr -s ' '; }` and, under a `DE-17128`
   heading, the assertions of the Test strategy below on the `templates/`
   sources; in the stubbed-agent simulation (`workflow-sim.cjs`, the Challenge
   block) add the `devAbsent` field to the printed JSON and its `assert_eq`
   after `SIM=$(sim '{}')`. Run `bash scripts/test-plugin-scripts.sh` and
   confirm the new assertions fail and only they fail. Commit:
   `test(scripts): pin the audit fixes of DE-17128 [DE-17128]`.
2. **Align `methodologies.md`, and record the why** — in the BDD section
   replace "Present the scenarios to the developer before implementing them."
   with "Write the scenarios into the test names before implementing them.";
   in "The per-step check" delete the "What the script resolves, per stack"
   sentence and the whole table, and replace the closing "If both come back
   empty, ask the developer…" paragraph with exactly: "An empty value is a
   command the project does not define: run nothing for it and never
   substitute one of your own. Say so where the step reports — the `Tests:` /
   `Linter:` lines of the summary, or `notes` in the autonomous run." Keep the
   index and the `detect-stack.sh --json` block. In `AGENTS.md`, under §"What
   the interactive flow stopped doing (DE-16480)", add one bullet: the
   quality-command question — an empty `TEST_CMD` or `LINT_CMD` is a command
   the project does not define, reported where the step reports and never
   asked (DE-17128); the version line stays. Commit: `fix(sdd-dev): align
   methodologies.md with the flow stops and detect-stack.sh [DE-17128]`.
3. **Have the dev agent report what it skipped** — in `auto-sdd.js`, in the
   dev agent prompt (`phase('Dev')`), change "(an empty one means the project
   does not define it — skip it, do not substitute your own)" to "(an empty one
   means the project does not define it — skip it, say so in `notes`, do not
   substitute your own)". Nothing else in the file moves. Commit:
   `fix(workflow): have the dev agent report absent quality commands in notes
   [DE-17128]`.
4. **Take the history out of the six instructions** — apply REQ-5 edit by edit:
   `sdd-dev/SKILL.md` §2 and §4, `closure.md` intro and §2,
   `spec-template.md` last bullet, `registry-updates.md` "Leave the change"
   paragraph, `mcp-env.md` Step 7b opening. Each edit keeps the rule sentence
   named in REQ-5 verbatim and removes only the narrative clause; the
   surrounding step structure, headings, index entries and the summary/report
   lines check 16 reads stay as they are. Commit: `fix(skills): state the
   current rule without the history behind it [DE-17128]`.
5. **Give the verbatim-write rule its reason** — in `install.md` §3.2 replace
   the `**IMPORTANT**` paragraph with: "Write the files you read exactly as
   received — no reformatting, no adjusting, no improving. The later steps
   read them back by their content: `migrate-settings.sh` tells an old
   generated `settings.json` from the team's by its shape (3.2b), and the
   review finds the sections and `_No ... registered._` placeholders of
   `REGISTRY.md` by their exact text. A copy that differs from the template is
   one the setup reads as the team's file." The paragraph carries none of
   `used to`, `no longer`, `once cost`. Commit: `fix(setup): give the
   verbatim-write rule its reason [DE-17128]`.
6. **Rebuild the plugin and run every gate (green)** — `bash
   scripts/build-plugin.sh dev-setup`; `git diff --quiet -- dist/
   .claude-plugin/` must be non-empty before the commit and the rebuild must
   be the only change; `bash scripts/validate-plugin.sh --strict` exits 0;
   `bash scripts/test-plugin-scripts.sh` is green, the step-1 assertions
   included (`TEST_TMPDIR` outside the project when sandboxed);
   `scripts/validate-baseline.txt` is still empty. Commit: `build(dist):
   rebuild dev-setup for DE-17128 [DE-17128]`.

## Test strategy

All tests are grep assertions in `scripts/test-plugin-scripts.sh` on the
`templates/` sources (the pattern section 9 already uses), one behavioural
assertion on the stubbed-agent simulation, plus the two existing gates. Each
one fails on `next` today and passes after the plan. Needles are matched on a
whitespace-folded read of the file (`flat`), so a sentence the markdown wraps
still counts and a removed phrase cannot pass because a later edit wrapped it.
`METH` is `methodologies.md`, `INSTALL` is `install.md`.

- Test 1 (REQ-1): `assert_eq "" "$(grep -rln 'Present the scenarios' templates/dev-setup/.claude/skills/sdd-dev || true)"` and `assert_contains "$(flat "$METH")" "into the test names before implementing them"`.
- Test 2 (REQ-2): `assert_eq "" "$(grep -n '^|' "$METH" || true)"` (no table), `assert_eq "" "$(grep -nE 'npm test|ruff check|go test|cargo test|flutter test' "$METH" || true)"`, and `assert_contains "$(flat "$METH")" "detect-stack.sh --json"`.
- Test 3 (REQ-3): `assert_eq "" "$(grep -rn 'ask the developer which commands\|If both come back empty' templates/dev-setup/.claude/skills/sdd-dev || true)"`, `assert_contains "$(flat "$METH")" "never substitute one of your own"` and `assert_contains "$(flat "$METH")" "\`notes\`"`.
- Test 4 (REQ-4): in `workflow-sim.cjs` the printed JSON gains `devAbsent: /test:\s+\(none\)/.test(prompts['dev:DE-1'] || '') && (prompts['dev:DE-1'] || '').includes('say so in \`notes\`')`, and after `SIM=$(sim '{}')`: `assert_eq "with no quality command defined, the dev agent is told to skip it and say so in notes" "true" "$(field "$SIM" devAbsent)"`. The existing compile test ("the auto-sdd workflow script compiles the way the harness compiles it") still passes.
- Test 5 (REQ-5): for each file `F`, every "gone" check is `assert_eq "<label>" "" "$(flat "$F" | grep -o '<phrase>' || true)"` with the phrases `second approval wearing`, `once cost a task four commits`, `this flow used to mandate`, `no longer calls it`, `this template used to carry`, `this reference used to mandate`, `used to be two bullets`; every "kept" check is `assert_contains "<label>" "$(flat "$F")" "<sentence>"` with the sentences REQ-5 names (`Do not ask the developer to confirm the breakdown`, `Do not commit, simplify or touch the spec's status`, `the gates run before the commit, and there is one commit`, `This is the only place \`simplify\` runs in the flow`, `Nothing in here records how the run went`, `Leave the change in the working tree — do not commit it`, `settings on the host`).
- Test 6 (REQ-6): `assert_eq` of the sorted output of `grep -rln "used to\|no longer\|once cost"` over the four prose directories against the three-file allowlist (`templates/dev-setup/.claude/reference/fork-point.md`, `templates/dev-setup/setup/reference/agents-generation.md`, `templates/dev-setup/setup/reference/rules-generation.md`).
- Test 7 (REQ-7): `BLOCK="$(sed -n '/^### 3.2 /,/^### 3.2b/p' "$INSTALL" | tr '\n' ' ' | tr -s ' ')"`; `assert_eq "no shouted IMPORTANT in the verbatim-write rule" "" "$(printf '%s' "$BLOCK" | grep -o '\*\*IMPORTANT\*\*' || true)"`; `assert_contains "the verbatim-write rule is kept" "$BLOCK" "exactly as received"`; `assert_contains "and states its reason" "$BLOCK" "read them back"`; and `assert_eq "install.md carries no history phrase" "" "$(grep -n 'used to\|no longer\|once cost' "$INSTALL" || true)"`, so the one file this task writes new prose into is pinned directly and a regression there names the file instead of only breaking Test 6's count. (`conflict detection` is not a needle: it already occurs twice in §3.2 today, so it would be green before the change.)
- Test 8 (REQ-8): `bash scripts/validate-plugin.sh --strict` exits 0 (CI job `static-checks`); `wc -w` on `sdd-dev/SKILL.md` is under 500 (it is 497 today and the edits only remove words).
- Test 9 (REQ-9): `bash scripts/build-plugin.sh dev-setup && git diff --quiet -- dist/ .claude-plugin/` exits 0 (CI job `verify`); the existing assertions that read `dist/dev-setup/skills/setup/reference/mcp-env.md` (`Figma MCP registered`) still pass.

## Notes

- **`turn-discipline.md:18-20`, verified and left in place.** Origin: a6a5df2
  (the first sdd skills, PR #10), where the model was told to "respond with
  `{"ok": true}`" to an incomplete-work message — a Stop-hook protocol this
  plugin never shipped; rewritten to "ignore it" in 42ee328 and moved into the
  shared reference in e2fbe98. No hook under `templates/dev-setup/.claude/hooks/`
  emits such a message, no incident is on record, and a project's own Stop
  hook is the only source that could. The task proposes no change, so none is
  made; the reviewer decides whether the generic "ignore the harness" rule
  earns its place (see `toConfirm`).
- The task cites `sdd/SKILL.md:54-56` as "the two stops"; since DE-17076 the
  skill declares three (launch, discovery, spec approval). The spec aligns to
  the current count; the point — `sdd-dev`'s summary is not a stop and no
  further one is added — is unchanged.
- **Outside this task, worth a follow-up:** the outcome object of `auto-sdd.js`
  carries `notes` and `absent`, but `run-outcomes.md` names neither in the
  `ready-for-mr` shape nor under "The merge request", so a skipped quality
  check reaches the outcome and no reviewer unless the launcher happens to
  copy it. The acceptance criterion asks that the workflow signal it in
  `notes`, which REQ-4 delivers; carrying it to the merge request is a change
  to the launcher contract and is not made here.
- `README.md:363` ("which is why the flow no longer asks") and the bash and
  JS comments that say "used to" (`auto-sdd.js:332`, the hooks and scripts
  headers) are outside the acceptance criterion's grep and are read by
  maintainers, not by the model at run time. Not touched.
- Not in scope, worth one line: DE-17070 covers the remaining audit patterns
  (Gotchas, ritual instructions, narration) and may share this PR.
