# Spec: Quality commands declared by the project and verified at setup: no autonomous run starts without them [DE-17535]

> Status: implemented
> Task: https://app.clickup.com/t/869fj4v0z
> Branch: created by the dev step through `sdd-start.sh`
> Created: 2026-10-16
> Approved: 2026-10-16 (the review that runs next is the approval in this flow)

## Context

Today the quality commands (lint, typecheck, test) come from per-language
heuristics in `templates/dev-setup/.claude/scripts/detect-stack.sh`. They are
worked out again on every run, and every consumer reads an empty value as "the
project does not define it". On DE-17472 (invictus-program-backend: Laravel in
`api/`, with its gates in `make lint`, `make test` and the CI job `api`),
detection returned `LANG=unknown` and three empty commands. `auto-sdd` then ran
spec, challenge and dev (19 commits, about 145M input tokens) without running a
single test, and it stopped at `verify`. The outcome was already certain at
intake. The session was an ephemeral cloud session, so the unpushed branch and
worktree were lost.

The root defect: nothing separates "we do not know" from "the project has none",
and the plugin never asks the project which one it is. Adding PHP to
`detect-stack.sh` would only move the problem to the next stack. This task turns
the commands into a **project declaration**. The setup writes and verifies it
once, and every flow reads it from one place. An autonomous run that cannot
check its own work stops at intake, within seconds, before any agent starts.

## Requirements

- REQ-1 (one declaration, one reader): `detect-stack.sh` reads
  `.claude/quality-commands.json` before it runs its heuristics.
  - A valid file sets `TEST_CMD`, `LINT_CMD` and `TYPECHECK_CMD`.
  - The script emits two new keys:
    - `COMMANDS_SOURCE`: `declared`, `detected` or `none`;
    - `PREFLIGHT_CMD`: the declared `preflight`, or empty when there is none.
  - A malformed file makes the script exit non-zero, with the cause on stderr and
    nothing on stdout. A file is malformed when it has:
    - a missing command key;
    - an empty-string command;
    - a `null` command with no reason in `absent`;
    - a `hook_manager` that does not match `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`;
    - invalid JSON.
- REQ-2 (the declaration wins): a project with a declaration gets the declared
  commands, even when the heuristics would find others. This includes each
  `null`: a command declared absent stays empty and is never filled in from a
  heuristic.
- REQ-3 (declared absent is not unknown): a command declared `null` with a reason
  comes out empty, with `COMMANDS_SOURCE=declared`. The launcher check (REQ-8)
  and the autonomous workflow accept it and run the other commands, so a project
  with no typecheck proceeds on lint and test.
- REQ-4 (source semantics without a declaration): when there is no file,
  `COMMANDS_SOURCE` is `detected` if at least one heuristic command is non-empty,
  and `none` if all three are empty. Every existing fixture snapshot carries the
  two new keys.
- REQ-5 (declared hook manager): a non-null `hook_manager` in the declaration
  becomes `HOOK_MANAGER`, even when detection finds none. For example,
  `pre-commit` and `captainhook` are both accepted. `gate-commit.sh` then runs in
  anti-bypass mode and runs no check of its own.
- REQ-6 (stack-independent candidates): a new script,
  `quality-candidates.sh [--dir <path>] --json`, returns `LINT_CANDIDATES`,
  `TYPECHECK_CANDIDATES`, `TEST_CANDIDATES` and `CANDIDATE_COUNT`.
  - Each `*_CANDIDATES` value has one `<command>\t<source>` line per candidate,
    deduplicated by command, in source order.
  - `<source>` is `<kind>:<path from the repository root>`. The kinds are:
    - `ci:` for `.github/workflows/*.y*ml` and `.gitlab-ci.yml`;
    - `runner:` for `Makefile`, `justfile` and `Taskfile.yml`;
    - `scripts:` for `package.json`, `composer.json` and `pyproject.toml`;
    - `docs:` for `README.md` and `AGENTS.md`;
    - `heuristic:detect-stack.sh`.
  - The readers are:
    - GitHub `run:` steps, both single-line and `run: |` blocks;
    - GitLab `script:` items;
    - Makefile, justfile and Taskfile targets;
    - `package.json` and `composer.json` scripts;
    - `pyproject.toml` `[tool.poe.tasks]` and `[tool.pdm.scripts]`;
    - the fenced code blocks of `README.md` and `AGENTS.md`;
    - last, the `detect-stack.sh` heuristics.
  - Every candidate is a command that runs from the repository root:
    - A CI `run:` under a `working-directory: X` (on its step, or in the job's
      `defaults.run`) is emitted as `cd X && <command>`.
    - So is every candidate found with `--dir X`.
  - On a fixture in a language `detect-stack.sh` does not know, with its gates in
    a `Makefile` and in CI, the script proposes `make lint` and `make test`.
- REQ-7 (DE-17472 regression): the `laravel-api` fixture has Laravel in `api/`,
  its gates in a root `Makefile`, and a CI job `api` that runs `make lint` and
  `make test` at the root.
  - It yields `make lint` and `make test` with no `cd` prefix, while
    `detect-stack.sh` still reports `LANG=unknown`.
  - A declaration of those two commands passes `quality-preflight.sh --run`.
  - All of this goes through REQ-6 and through no PHP rule.
- REQ-8 (the fail-fast check): a new script,
  `quality-preflight.sh [--require-declared] [--run] --json`, returns `READY`,
  `REASON`, `COMMANDS_SOURCE`, `MISSING`, `PREFLIGHT`, `OUTPUT`, `LINT_STATUS`,
  `TYPECHECK_STATUS` and `TEST_STATUS`.
  - It exits 3 (refused) with `READY=false` when:
    - `detect-stack.sh` rejects the declaration (`REASON` carries its stderr);
    - `--require-declared` is set and `COMMANDS_SOURCE` is not `declared`
      (`REASON` names the setup);
    - no command is non-empty;
    - without `--allow-unavailable`, the first binary of a non-empty command is
      not found (none of the commands is run);
    - without `--allow-unavailable`, a declared `preflight` exits non-zero
      (`OUTPUT` holds the tail of its output).
  - With `--allow-unavailable` (REQ-17), those last two are not refusals: the
    affected kinds come back in `UNAVAILABLE`, with `UNAVAILABLE_REASON`, and
    the answer is ready.
  - It exits 0 when ready, and exits 1 for a bad flag or a missing `jq`.
  - Both checks skip a command that is declared absent.
  - With `--run`, it executes each non-empty command once from the repository
    root and reports `passed`, `failed` or `not-found` per command, or `absent`
    for a command declared absent. A red command is reported, not refused. Only
    exit 126 or 127 (the command did not start) refuses.
- REQ-9 (workflow intake): `auto-sdd.js` returns
  `{status: 'failed', stage: 'intake'}`, without launching any agent, when
  `stack.lint`, `stack.typecheck` and `stack.test` are all empty or missing. That
  includes the `{lint: '', typecheck: '', test: ''}` object the launchers pass.
- REQ-10 (auto-sdd launcher): the `auto-sdd` skill runs
  `quality-preflight.sh --require-declared --json` in step 1, right after it
  reads the task and before the backlog-gate question. So the check also comes
  before the fork-point question, the `IN PROGRESS` move, the clock and the
  `Workflow` call.
  - Any non-zero exit means no run, and none of those steps happens.
  - On exit 3, a task read in `SPRINT` gets one bail-out call
    (`SPRINT -> BLOCKED`) that carries `REASON` and `OUTPUT`.
  - A task read in `BACKLOG` is left exactly as found, and `REASON` and `OUTPUT`
    are shown in chat.
- REQ-11 (multi-sdd launcher): `multi-sdd` runs the same check once for the whole
  set, at the top of `reference/preflight.md`'s intake, before any task is read.
  So it also comes before the backlog gate, the triage, the overlap warning, the
  fork point and the fan-out. On a non-zero exit it prints `REASON` and `OUTPUT`
  and stops. No run starts, and no task is read or touched, which is how
  `multi-preflight.sh`'s exit 3 already works.
- REQ-12 (interactive flows): `sdd` (intake step 4) and `quick` (step 1) read
  `COMMANDS_SOURCE`. When it is `none`, they say so in one line inside that step.
  This is not a stop. `sdd-dev`'s per-step check keeps skipping a command
  declared absent, and keeps reporting it.
- REQ-13 (the setup writes and verifies the declaration): a new setup step, 3b,
  runs in every mode. GREENFIELD runs it after Step 8, on the scaffold. The step:
  - runs `quality-candidates.sh`;
  - asks the developer to confirm or correct lint, typecheck and test in one
    `AskUserQuestion` call;
  - still asks about a kind with no candidate, so no command is left empty
    without a decision;
  - writes `.claude/quality-commands.json`;
  - runs `quality-preflight.sh --run` and reports the result per command in one
    summary line;
  - regenerates `.claude/.stack.json`, so that Steps 4 and 5 read the declared
    commands.
- REQ-14 (UPDATE path): on a project that is already set up but has no
  declaration, step 3b proposes one from the same candidates.
  - If the developer declines, the summary carries a DECLINED line saying that
    `auto-sdd` and `multi-sdd` refuse to start until the file exists.
  - An existing valid declaration is kept as the team left it, and is verified.
  - A malformed declaration is reported, and a rewrite is offered.
- REQ-15 (ephemeral environment): `run-outcomes.md` states the policy for a
  `failed` outcome that carries a `branch` while `CLAUDE_CODE_REMOTE` is `true`:
  push the branch with `git push -u origin "<branch>"`, open no merge request,
  and name the pushed branch in the `BLOCKED` note.
- REQ-16 (documentation):
  - `docs/developer-guide.md` documents the declaration: the file, its keys,
    `COMMANDS_SOURCE`, the launcher refusal and how to fix it.
  - `docs/migration-v2-to-v3.md` records the contract change, since the
    autonomous launchers refuse to start without a declaration.
  - `AGENTS.md` lists the two new scripts and the new `detect-stack.sh` keys.
  - Checks 14 and 15 of `validate-plugin.sh` stay green.
- REQ-17 (an environment that cannot run the commands does not stop the run —
  the developer's decision of 2026-10-16, superseding the task's "Binario
  mancante blocca il launcher"):
  - The autonomous launchers call `quality-preflight.sh --require-declared
    --allow-unavailable`. A missing program makes its kind unavailable; a red
    declared preflight makes every declared kind unavailable. The launchers say
    so in one line and pass `unavailable` and `unavailableReason` to the
    workflow.
  - The workflow never runs an unavailable command: the dev agent is told not
    to run it, install anything or substitute a check, and to write the tests
    anyway; Verify skips it, and lists a command that exits 126/127 in
    `notStarted`, which is not a red result.
  - With no runnable command left, the run skips Verify and still returns
    `ready-for-mr`.
  - The outcome carries `unverified: [{kind, command, reason}]`, and the merge
    request opens with a **Not verified** section naming each one.
  - A project that declares nothing is still refused (REQ-8, REQ-9): "we do not
    know how to check it" is not "this machine cannot".

## Technical decisions

**The file.** `.claude/quality-commands.json` is tracked and owned by the team,
on the model of `.claude/merge-request.json` (setup 3.9). It holds no credential.
Its shape:

```json
{
  "lint": "make lint",
  "typecheck": null,
  "test": "make test",
  "absent": { "typecheck": "the project has no type checker" },
  "preflight": null,
  "hook_manager": null
}
```

- `lint`, `typecheck` and `test` are required keys. Each one is either a
  non-empty string or `null`, and a `null` needs a non-empty `absent.<key>`.
  With that rule, a command cannot be written "empty by accident".
- `preflight` and `hook_manager` are optional and `null` by default. A
  `hook_manager` is a short tool name, which the regex in REQ-1 checks.
  `pre-commit`, `captainhook` and `grumphp` all pass it.

**Commands run from the repository root, so there is no `dir` key.** Point 1 of
the task asks the file to hold "la directory da cui eseguirli". The spec departs
from that, and the plugin's existing contract is what overrules it (precedence
1):

- `agents-generation.md`, "Command wrapping": "A command written into a
  sub-project's file still has to run from the workspace root".
- `detect-stack.sh`: "In a monorepo the commands must run from the workspace
  root".
- `gate-commit.sh` `cd`s to the repo root and `eval`s each command in a
  subshell, and the workflow's Verify prompt runs each command "exactly as
  written" from the worktree.

A command that needs a sub-directory carries it, for example
`make -C api lint` or `cd api && composer test`. That already works in every
consumer with no change. A single `dir` shared by three commands would also
attach every command to the wrong directory whenever the candidates come from
different places. On the `laravel-api` fixture it would run the root-Makefile
`make lint` inside `api/`. No acceptance criterion names a directory, and the
DE-17472 regression passes on the root commands. As a result, `gate-commit.sh`
needs no change, and the workflow prompts and launch blocks gain no field.

**One reader.** `detect-stack.sh` is the only reader of the file. Every consumer
already calls it: `gate-commit.sh`, `sdd-dev`'s `methodologies.md`, the
`auto-sdd` and `multi-sdd` launchers, `on-compact.sh`, and the setup through
`.stack.json`. So "every flow reads the commands from the same place" holds, and
no consumer grows a second parser.

The new keys follow the script contract: flat, `UPPER_SNAKE`, and the empty
string when there is no value. A malformed declaration exits non-zero, which is
the precedent `mr-meta.sh` set for a malformed metadata file. On that exit:

- `gate-commit.sh` stays fail-open, as its header already specifies for a failed
  detection;
- `quality-preflight.sh` turns it into a refusal (exit 3, `REASON` carrying the
  cause), so the launchers refuse with a reason instead of failing with a bare
  error.

**The declaration wins wholesale.** When the file is valid, none of the three
heuristic commands is used, not even to fill a `null`: a `null` is a decision,
not a gap. `HOOK_MANAGER` follows the same rule when `hook_manager` is non-null.
That covers captainhook, pre-commit and grumphp without one detection rule per
tool.

**Candidates are a script, not prose.** `quality-candidates.sh` (bash + jq, read
only) holds the deterministic part that the setup would otherwise work out again
on every run. That follows the AGENTS.md rule that deterministic work lives in
scripts, with fixtures in CI.

- **Classification** uses the gate's generic name, never a tool or language
  name:
  - a candidate whose text matches `lint` is a lint candidate;
  - one that matches `typecheck|type-check|types|analy[sz]e|static` is a
    typecheck candidate;
  - one that matches `test` is a test candidate.
- **Sources** are read in order of authority: CI first, because it is what gates
  the merge, then task runners, package-manager scripts, docs, and last the
  `detect-stack.sh` heuristics. The script dedupes by command and keeps the first
  source that yielded it.
- **Formats.**
  - Task runners give `make <target>`, `just <recipe>` and `task <name>`.
  - Package scripts use the runner prefix `detect-stack.sh` already uses for npm
    (`npm run`, `pnpm run`, `yarn`, `bun run`). The other managers give
    `composer <script>`, `poe <task>` and `pdm run <script>`.
- **Directories** are folded into the command as `cd X && `, following the
  root-relative contract above. The script does not emit them as a separate
  value.
- **Scope.** `--dir` points the scan at a sub-project. YAML is read line by line:
  a single-line `run:`, the indented body of a `run: |` block,
  `working-directory:` on a step or under `defaults.run`, and `script:` list
  items. No YAML parser is added, and the dependency contract stays bash + jq.

**The fail-fast check is a separate script.** `quality-preflight.sh` serves both
the setup verification (`--run`) and the two launchers (`--require-declared`).
It calls `detect-stack.sh`, so it reads the same source as every other consumer.

- **First-binary check.** For each non-empty command, the script skips any
  leading `VAR=value` words and any leading `cd <dir> &&`. It checks a word that
  contains `/` with `-x`, relative to that `<dir>` (or to the root when there is
  no `cd`). It checks any other word with `command -v`. A declared-absent
  command is skipped, because `command -v ""` exits 1.
- **Refusal.** The script exits 3, as `multi-preflight.sh` does, so a refusal is
  an exit status and not a sentence. Exit 1 is kept for a real error: a bad flag
  or a missing `jq`.
- **Without `--run`**, it executes nothing except the declared `preflight`. That
  is what keeps a launcher refusal down to a few seconds.

**What the workflow checks.** The workflow VM has no shell, and running a command
there means launching an agent, which the task forbids at intake. So
`auto-sdd.js` checks what code can check: that at least one command is
non-empty. Whether the commands can actually run is checked by the launchers,
through `quality-preflight.sh`. The existing workflow simulation in
`test-plugin-scripts.sh` passes no stack and expects `ready-for-mr`. It is
updated to pass one, and new cases pin the intake refusal.

**The autonomous launchers require `declared`.** This follows point 5 of the task
literally: "until it exists, the autonomous launchers refuse, pointing at the
setup". A 3.4.x project whose commands are detected correctly therefore has to
run the setup's UPDATE once before `auto-sdd` starts again. That is a breaking
change for existing projects, so it goes into `docs/migration-v2-to-v3.md`, and
the squash commit carries a `BREAKING CHANGE:` footer.

**Refusal on the board.** Point 4 of the task asks for BLOCKED with the output.
Acceptance criterion 2 asks the launchers to stop before the board. The
project's contract decides which one applies where (precedence 1):

- The clickup agent allows `SPRINT -> BLOCKED` ("Bail-out before work could
  start") and has no `BACKLOG -> BLOCKED` transition.
- The backlog gate never moves a task on the flow's initiative, and it comes
  "before any branch, spec or board write".
- multi-sdd's phase A "writes nothing" to the board.

So the rules are:

- `auto-sdd` bails out a SPRINT task, in place of the `IN PROGRESS` move, with no
  clock, no fork-point question and no `Workflow`.
- `auto-sdd` leaves a BACKLOG task as it found it, and shows the reason in chat.
  It runs the check before the backlog question, so it never asks that question
  for a run that could not start.
- `multi-sdd` touches no task, and it runs the check before the first task read.

These rules are written once, in `run-outcomes.md` ("When the run does not
start"), which both launchers already cite. No new plugin-level reference is
created.

`auto-sdd/SKILL.md` and `multi-sdd/SKILL.md` are both at 499 words. So the
multi-sdd change lives in `reference/preflight.md`. In auto-sdd, the call and
"exit 3 → run-outcomes.md" replace the existing sentence "a command left empty
stays empty", rather than being added next to it.

**The setup step.** Step 3b is a new setup reference,
`setup/reference/quality-commands.md`.

- **Placement.** 3b runs after 3.1–3.9 and before Step 4, because Step 4 selects
  `tests.md` on `TEST_CMD` and Step 5 writes `{{TEST_COMMAND}}` into AGENTS.md.
  3b ends by rewriting `.claude/.stack.json`.
- **GREENFIELD** runs 3b after Step 8, once the scaffold has written its scripts.
  The SKILL.md table row says so.
- **Asking.** Lint, typecheck and test go in one `AskUserQuestion` call, under
  `turn-discipline.md`. Each question offers the top candidates of its kind plus
  "None — this project has no <kind>", and its free-text answer accepts a
  command. "None" writes `null` with the reason `declared absent at setup`.
- **Fields nobody is asked about.** `preflight` and `hook_manager` are written as
  `null`. Each is a one-line edit for the team, the way 7d.3 treats
  `base_branch` and `dry_run`.
- **Verification.** The step runs `quality-preflight.sh --run`, which delivers "a
  declared command is an executed command". Its per-command statuses make up the
  summary line.
- **Summary.** The reference declares its summary lines, so check 16 passes.
- **Budget.** `setup/SKILL.md` stays within 500 words: the new table row is paid
  for by trimming existing prose.

**Ephemeral sessions.** Claude Code sets `CLAUDE_CODE_REMOTE` to `true` in a
cloud session; the Claude Code environment-variable docs, checked through
Context7, document this. `run-outcomes.md` keys the push-on-failure policy on
it. Locally nothing changes: the worktree survives and stays the material for
debugging.

**Interactive flows.** These are prose changes, held to their budgets:

- `sdd/reference/intake.md` step 4 adds the `detect-stack.sh` read and the
  one-line notice.
- `quick/SKILL.md` (497 words) gets the notice in step 1, paid for by trimmed
  words.
- `sdd-dev/reference/methodologies.md` adds the declared-absent wording: an
  empty command has either a reason in the file, or `COMMANDS_SOURCE=none`.

**What does not change.**

- The `verify` skill runs no quality command: it checks the spec against the
  review package. The task's "`verify`" consumer is the workflow's Verify phase
  (REQ-9).
- No language rule is added to `detect-stack.sh`; REQ-7 pins this.
- `gate-commit.sh`, `merge-request.json`, `auto-dev.json` and
  `migrate-settings.sh` are untouched. `gate-commit.sh` already reads
  `HOOK_MANAGER` and the commands from `detect-stack.sh`, and hooks reach
  projects through the plugin.

**Precedence applied.**

1. The architecture won:
   - on where the commands run (the repository root, with no `dir`);
   - on the refusal on the board (SPRINT only, no write in multi-sdd);
   - on how the workflow checks whether commands can run (code checks that they
     are non-empty, the launchers check the binaries);
   - on where the refusal text lives (`run-outcomes.md`);
   - on where the commands are read (`detect-stack.sh` only).
2. The acceptance criteria were delivered as written.
3. The task's "e.g. `.claude/quality-commands.json`" was followed as given. Its
   "la directory da cui eseguirli" and "il task va in BLOCKED" were departed from,
   as set out above.

## Impact

- **Files to create**:
  - `templates/dev-setup/.claude/scripts/quality-candidates.sh`
  - `templates/dev-setup/.claude/scripts/quality-preflight.sh`
  - `templates/dev-setup/setup/reference/quality-commands.md`
  - the `declared` fixture: `scripts/fixtures/declared/package.json`,
    `scripts/fixtures/declared/tsconfig.json`,
    `scripts/fixtures/declared/.claude/quality-commands.json`,
    `scripts/fixtures/declared.expected.json`
  - the `unknown-make` fixture: `scripts/fixtures/unknown-make/mix.exs`,
    `scripts/fixtures/unknown-make/Makefile`,
    `scripts/fixtures/unknown-make/.github/workflows/ci.yml`,
    `scripts/fixtures/unknown-make/README.md`,
    `scripts/fixtures/unknown-make.expected.json`
  - the `laravel-api` fixture: `scripts/fixtures/laravel-api/Makefile`,
    `scripts/fixtures/laravel-api/.github/workflows/ci.yml`,
    `scripts/fixtures/laravel-api/api/composer.json`,
    `scripts/fixtures/laravel-api/api/artisan`,
    `scripts/fixtures/laravel-api.expected.json`
- **Files to modify**:
  - `templates/dev-setup/.claude/scripts/detect-stack.sh`
  - `templates/dev-setup/.claude/workflows/auto-sdd.js`
  - `templates/dev-setup/.claude/skills/auto-sdd/SKILL.md`
  - `templates/dev-setup/.claude/skills/multi-sdd/reference/preflight.md`
  - `templates/dev-setup/.claude/skills/sdd/reference/intake.md`
  - `templates/dev-setup/.claude/skills/quick/SKILL.md`
  - `templates/dev-setup/.claude/skills/sdd-dev/reference/methodologies.md`
  - `templates/dev-setup/.claude/reference/run-outcomes.md`
  - `templates/dev-setup/setup/SKILL.md`
  - `templates/dev-setup/setup/reference/existing.md` (the Step 2 key list and
    the Step 9 list of collected reports)
  - `templates/dev-setup/setup/reference/greenfield.md` (the Step 9 list of
    collected reports)
  - `templates/dev-setup/manifest.json` (two more `plugin_scripts`, one more
    `setup_reference`)
  - `scripts/test-plugin-scripts.sh`
  - `scripts/fixtures/{flutter,monorepo,nestjs,nextjs,plain-node}.expected.json`
    (the two new keys)
  - `docs/developer-guide.md`, `docs/migration-v2-to-v3.md`, and `AGENTS.md`
    (the script table, the `detect-stack.sh` keys, version 2.31.0)
  - `dist/dev-setup/**` (regenerated by `scripts/build-plugin.sh`, never edited
    by hand)
- **Dependencies**: none. The scripts use bash + jq only, as the script contract
  requires.

## Implementation plan

1. **detect-stack reads the declaration.**
   - In `detect-stack.sh`, read and validate `.claude/quality-commands.json`
     before the quality-command heuristics, following the rules in REQ-1.
   - On a valid file, set the three commands, `PREFLIGHT_CMD` and, when it is
     non-null, `HOOK_MANAGER`.
   - Compute `COMMANDS_SOURCE`, emit the two new keys, and document them in the
     header.
   - Add the three fixtures:
     - `declared`: package.json scripts `lint`/`test`, a `tsconfig.json`, and a
       declaration with different commands, a `null` typecheck with a reason,
       and `preflight: "bin/check-toolchain.sh"`;
     - `unknown-make`: `mix.exs`, a Makefile with `lint:` and `test:`, and CI
       steps `run: make lint` and `run: make test`;
     - `laravel-api`: a root Makefile whose `lint:` and `test:` run `@true`, a
       CI job `api` that runs `make lint` and `make test` at the root,
       `api/composer.json` and `api/artisan`.
   - Regenerate the snapshots with `--update`. The load-bearing values are pinned
     with `assert_eq` (see Tests 1–5).
2. **quality-candidates.sh.**
   - Write the script: the readers, the classification, the order, the dedupe,
     the `<command>\t<source>` lines with `<kind>:<path>`, the `cd X && `
     folding for `working-directory` and `--dir`, `--json`, and the `--help`
     header.
   - Add it to `manifest.json` `plugin_scripts`.
   - Add the suite cases of Tests 6 and 7. Each reader gets an ad-hoc directory
     under the work directory, not under `scripts/fixtures/`.
3. **quality-preflight.sh.**
   - Write the script: `--require-declared`, `--run`, the malformed-declaration
     refusal, the first-binary check (skipping `VAR=value`, `cd <dir> &&` and
     declared-absent commands), the `preflight` run, exits 0/3/1, and the output
     keys.
   - Add it to `manifest.json`.
   - Add the suite cases of Test 8, one per REQ-8 branch.
4. **Workflow intake.**
   - In `auto-sdd.js`, before `phase('Spec')`, return `failed`/`intake` when all
     three commands are empty or missing.
   - Update the header contract comment.
   - In the suite's `workflow-sim.cjs`, accept an args override:
     - existing scenarios pass
       `{lint: 'make lint', typecheck: '', test: 'make test'}`;
     - the `devAbsent` assertion moves to `typecheck: (none)` (REQ-3);
     - add the intake cases of Test 9.
5. **Launchers and outcomes.**
   - In `run-outcomes.md`:
     - "When the run does not start" gains the quality-preflight refusal: a
       SPRINT task gets one `BLOCKED` bail-out with `REASON` and `OUTPUT`, a
       BACKLOG task is left as found, multi-sdd touches no task, and in every
       case there is no `IN PROGRESS`, no clock and no `Workflow`;
     - the `failed` section gains the `CLAUDE_CODE_REMOTE` push-without-MR
       policy;
     - the `stage: intake` text covers the empty-commands case.
   - In `auto-sdd/SKILL.md` step 1, put `quality-preflight.sh --require-declared
     --json` between the task read and the `BACKLOG` line, with "any non-zero
     exit → run-outcomes.md". It replaces the step 3 sentence "a command
     `detect-stack.sh` left empty stays empty", so the file stays within 500
     words.
   - In `multi-sdd/reference/preflight.md`, put the once-per-set check at the
     top of `## The intake`, before the first `INTENT: read`.
   - Add the order and text assertions of Tests 10, 11 and 15.
6. **Interactive flows.**
   - In `sdd/reference/intake.md` step 4, read `detect-stack.sh` and give the
     one-line notice on `COMMANDS_SOURCE=none`.
   - In `quick/SKILL.md` step 1, add the same notice, trimming words to stay at
     or under 500.
   - In `sdd-dev/reference/methodologies.md`, add the declared-absent wording.
   - Add the positional assertions of Test 12.
7. **Setup step 3b.**
   - Write `setup/reference/quality-commands.md`. It opens with an index and
     covers:
     - the file and its keys;
     - the candidates from `quality-candidates.sh`, then the one
       `AskUserQuestion` call on lint, typecheck and test;
     - the jq write;
     - `quality-preflight.sh --run`;
     - rewriting `.claude/.stack.json`;
     - the UPDATE cases: absent (propose), present and valid (keep and verify),
       malformed (report and offer a rewrite), declined (the DECLINED line);
     - the summary lines.
   - Add the table row to `setup/SKILL.md` (GREENFIELD after Step 8), trimming
     prose to stay within 500 words.
   - Add the reference to `manifest.json` `setup_reference`, add 3b to the
     collected-reports lists, and add the new `detect-stack.sh` keys to
     `existing.md` Step 2.
   - Add the assertions of Tests 13 and 14.
8. **Documentation.**
   - `docs/developer-guide.md`:
     - a section on the declaration: the file, its keys, the sources,
       `COMMANDS_SOURCE`, root-relative commands (`make -C api lint`), the
       launcher refusal and how to fix it;
     - the Upgrading table row;
     - the commit-gate paragraph on `hook_manager`;
     - the troubleshooting entry "The setup did not detect my stack",
       rewritten around the declaration.
   - `docs/migration-v2-to-v3.md`: a new numbered section, with its index
     entry, on autonomous runs requiring the declaration.
   - `AGENTS.md`: the script table (the `detect-stack.sh` keys and the two new
     scripts), and the version bumped to 2.31.0.
9. **Build and gates.**
   - Run `bash scripts/build-plugin.sh dev-setup` to regenerate
     `dist/dev-setup/`.
   - Then run `bash scripts/test-plugin-scripts.sh`,
     `bash scripts/validate-plugin.sh --strict`, and
     `shellcheck --severity=warning` on the two new scripts and the touched
     ones.

## Test strategy

All the tests are in `scripts/test-plugin-scripts.sh` unless stated otherwise.
The scripts are logic, so each case is written red first. A load-bearing value
is pinned with `assert_eq`, never left to a snapshot that `--update` regenerates.

- Test 1 (REQ-1):
  - Each malformed declaration exits non-zero, with empty stdout and non-empty
    stderr. The cases are:
    - a missing `test` key;
    - `"lint": ""`;
    - `"typecheck": null` with no `absent.typecheck`;
    - `"hook_manager": "a b"`;
    - invalid JSON.
  - `"hook_manager": "pre-commit"` is accepted.
  - On `declared`, `PREFLIGHT_CMD` equals `bin/check-toolchain.sh`.
- Test 2 (REQ-2): on `declared`, `LINT_CMD` and `TEST_CMD` equal the declared
  strings, not `npm run lint`/`npm run test`. `TYPECHECK_CMD` is empty, although
  `tsconfig.json` would make the heuristic give `npx tsc --noEmit`.
- Test 3 (REQ-3):
  - `declared` gives `COMMANDS_SOURCE=declared` with an empty `TYPECHECK_CMD`.
  - A workflow simulation with `typecheck: ''`, and lint and test set, reaches
    `ready-for-mr`, and its dev prompt shows `typecheck: (none)`.
  - The REQ-8 side is covered by Test 8's ready case.
- Test 4 (REQ-4): `assert_eq` on `.COMMANDS_SOURCE`:
  - `none` on `plain-node`, `unknown-make` and `laravel-api`;
  - `detected` on `nestjs`, `nextjs`, `flutter` and `monorepo`;
  - `detected` on an ad-hoc directory whose `package.json` is
    `{"scripts":{"lint":"eslint ."}}`. Only lint is set there, which separates
    "at least one" from "all three".
  - Every snapshot also carries the two keys.
- Test 5 (REQ-5): a project with `hook_manager: "captainhook"` and no detectable
  manager reports `HOOK_MANAGER=captainhook`, and `pre-commit` gives
  `HOOK_MANAGER=pre-commit`. `gate-commit.sh` lets a staged commit through on a
  red declared lint.
- Test 6 (REQ-6), one ad-hoc directory per reader. Each yields a command no other
  reader yields, and the test asserts its exact line:
  - a `run: |` body holding `npm run check:types` (typecheck,
    `ci:.github/workflows/ci.yml`);
  - a step with `working-directory: web` running `npm test`, giving
    `cd web && npm test`;
  - a job with `defaults.run.working-directory: svc` running `make lint`, giving
    `cd svc && make lint`;
  - a GitLab `- ./gradlew test` (`ci:.gitlab-ci.yml`);
  - `just lint` (`runner:justfile`);
  - `task test` (`runner:Taskfile.yml`);
  - `composer analyse` (typecheck, `scripts:composer.json`);
  - `poe lint` and `pdm run test` (`scripts:pyproject.toml`);
  - a fenced `make test` in `README.md` and a fenced `make lint` in `AGENTS.md`
    (`docs:`);
  - `go.mod` alone, giving `go test ./...` from `heuristic:detect-stack.sh`.
  - On `unknown-make`:
    - `make lint` comes out once, with its `ci:` source, although the Makefile
      also yields it;
    - `make test` is in `TEST_CANDIDATES`.
  - On `nestjs`, the output lists `npm run lint` with `scripts:package.json`.
  - `--dir api` on `laravel-api` lists the `api/composer.json` scripts as
    `cd api && composer <script>`.
  - An empty directory returns `CANDIDATE_COUNT=0` and exit 0.
- Test 7 (REQ-7): on `laravel-api`:
  - the candidates hold `make lint` and `make test` with no `cd` prefix and a
    `ci:` source;
  - `detect-stack.sh` gives `LANG=unknown` (`assert_eq`);
  - in a copy of the fixture with the declaration
    `{"lint":"make lint","typecheck":null,"absent":{"typecheck":"none"},"test":"make test"}`,
    `quality-preflight.sh --run` gives `LINT_STATUS=passed` and
    `TEST_STATUS=passed`.
- Test 8 (REQ-8), the `quality-preflight.sh` cases:
  - no declaration with `--require-declared` gives exit 3, with a `REASON` that
    names the setup;
  - `"lint": ""` gives exit 3, a JSON object on stdout and a `REASON` containing
    `lint`;
  - an all-`null` declaration gives exit 3;
  - a missing binary gives exit 3 with `MISSING` set;
  - `test: "cd sub && ./run-tests"` with no `sub/run-tests` gives exit 3, and
    with an executable `sub/run-tests` it passes the check;
  - `preflight: "echo boom; exit 7"` gives exit 3, with `OUTPUT` holding `boom`;
  - the ready declaration `{"lint":"true","typecheck":null,"absent":{"typecheck":"none"},"test":"touch ran"}`:
    - without `--run`: exit 0, `READY=true`, `MISSING` empty, and no `ran` file;
    - with `--run`: `LINT_STATUS=passed`, `TYPECHECK_STATUS=absent`,
      `TEST_STATUS=passed`, and `ran` present at the root;
  - `--run` with a red test gives `TEST_STATUS=failed` and exit 0;
  - a command exiting 127 gives `not-found` and exit 3;
  - an unknown flag gives exit 1.
- Test 9 (REQ-9), the workflow simulation:
  - no stack gives `failed`/`intake` with zero agent calls;
  - `stack: {lint: '', typecheck: '', test: ''}` gives `failed`/`intake` with
    zero agent calls.
  - The existing Challenge assertions stay green with a stack passed.
- Test 10 (REQ-10):
  - In the step-1-to-step-3 range of `auto-sdd/SKILL.md` (extracted with
    `sed -n '/^## 1\. /,/^## 3\. /p'`), the
    `quality-preflight.sh --require-declared` line precedes the `BACKLOG` gate
    line, `fork-point.md`, `status: IN PROGRESS` and `task-clock.sh`.
  - `run-outcomes.md`'s refusal names `BLOCKED` for a SPRINT task and "left as
    found" for a BACKLOG one.
- Test 11 (REQ-11): in `multi-sdd/reference/preflight.md`, the check precedes the
  first `INTENT: read` and the `^## Triage` heading, and its refusal text
  contains no `BLOCKED`.
- Test 12 (REQ-12):
  - `quick/SKILL.md` contains `COMMANDS_SOURCE` between `1. **The change.**` and
    `2. **The branch.**`;
  - `sdd/reference/intake.md` contains it inside its `## 4.` section;
  - `sdd-dev/reference/methodologies.md` contains `declared absent`.
- Test 13 (REQ-13):
  - `setup/reference/quality-commands.md` names `quality-candidates.sh`,
    `AskUserQuestion`, `quality-preflight.sh` with `--run`, and `.stack.json`;
  - `validate-plugin.sh --strict` check 16 reports nothing for it;
  - check 2 keeps `setup/SKILL.md` within 500 words.
- Test 14 (REQ-14): the same reference carries the UPDATE branch for an absent
  declaration, and the DECLINED summary line naming `auto-sdd` and `multi-sdd`.
- Test 15 (REQ-15): the `failed` section of `run-outcomes.md` contains
  `CLAUDE_CODE_REMOTE`, `git push -u origin` and "no merge request".
- Test 16 (REQ-16):
  - `validate-plugin.sh --strict` checks 14–15 pass, so every script and path the
    docs name resolves;
  - `docs/developer-guide.md` contains `.claude/quality-commands.json` and
    `quality-preflight.sh`;
  - `docs/migration-v2-to-v3.md` contains `quality-commands.json`.
- Gates that cover the whole change:
  - the CI job `verify` (dist in sync after `build-plugin.sh`);
  - `shellcheck` on the new scripts;
  - check 2 (every touched `SKILL.md` at or under 500 words);
  - check 13 (the workflow phases are still declared and opened).

## Notes

- **Breaking change.** On a project set up before this release, the autonomous
  launchers refuse to start until `/dev-setup:setup` (UPDATE) writes the
  declaration. The squash commit carries a `BREAKING CHANGE:` footer, and the
  migration page says so.
- The temporary patch in invictus-program-backend#7 (`stack` and `preflight` in
  `.claude/auto-dev.json`, plus `bin/check-agent-toolchain.sh`) is removed by
  that project once this ships. Its preflight script maps onto the declaration's
  `preflight` field. Its commands are declared in root-relative form, for
  example `make lint`.
- A local, untracked `scripts/fixtures/laravel/` directory (holding only
  `.claude/.cc-writes`) exists on the author's checkout. The snapshot loop
  iterates over it and reports "no snapshot". The new fixture is named
  `laravel-api` to stay clear of it, and the stray directory is not part of this
  change.
- Out of scope, possibly worth doing later: suggesting a `hook_manager`
  candidate from `captainhook.json`, `.pre-commit-config.yaml` or `grumphp.yml`
  at setup.
