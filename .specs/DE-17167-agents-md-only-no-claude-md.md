# Spec: Setup generates only AGENTS.md, without CLAUDE.md, and Claude Code reads AGENTS.md [DE-17167]

> Status: approved
> Task: https://app.clickup.com/t/869fcv04b
> Branch: created by the dev step through `sdd-start.sh` (`feat(setup)/DE-17167_agents-md-only`)
> Created: 2026-10-16
> Approved: 2026-10-16 (in this flow the review that runs next is the approval)

## Context

Today the setup writes two instruction files: `AGENTS.md` and a one-line
`CLAUDE.md` holding `@AGENTS.md`. It writes them at the root and in every
application sub-project (`templates/dev-setup/setup/reference/agents-generation.md`,
Step 5b). The shim was there because Claude Code read only `CLAUDE.md`. That is
no longer true. Since v2.1.277 the built-in `cc-plugin-agents-md` mod reads
`AGENTS.md` as project instructions. With the default `claude-md-or-agents-md`,
it does so only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md`
sits in the working directory or above it. So the shim is now a second file to
maintain, and it also decides which file wins.

This was checked against `code.claude.com/docs/en/memory`, `docs/en/worktrees`,
`docs/en/env-vars` and the plugin manifest reference on 2026-10-16:

- `~/.claude/CLAUDE.md`, the managed `CLAUDE.md` and `.claude/rules/` do not
  count. They load alongside `AGENTS.md`.
- A sub-project's `AGENTS.md` loads when Claude reads a file in that directory,
  unless the directory has a `CLAUDE.md` of its own.
- `@path` imports inside `AGENTS.md` are expanded.
- **Project instructions** (`pluginConfigs["cc-plugin-agents-md@builtin"].options.instructionFiles`,
  or `agents-md@builtin` before 2.1.285) is read only from
  `~/.claude/settings.json`, a `--settings` file or managed settings. Project and
  local settings ignore it.
- `plugin.json` has no field for a minimum client version. Its `settings` object
  applies only `agent` and `subagentStatusLine`, so the plugin cannot carry
  `pluginConfigs` either.
- **AGENTS.md is not read** in these cases:
  - versions before 2.1.277;
  - when the built-in mod is disabled in `/plugin`;
  - in some first sessions after an upgrade from 2.1.276 or earlier;
  - before v2.1.281, in sessions on Amazon Bedrock or with telemetry disabled.
- A subagent in its own worktree takes the instruction files it starts with
  from the main conversation, not from its worktree.

This task removes the shim from every mode. It also checks the client version
before the setup writes anything, and reports every file that would make Claude
Code skip `AGENTS.md`. UPDATE moves projects that are already configured onto
the new shape, as the "UPDATE path is part of the contract" section of the
meta-repo `AGENTS.md` requires. As with `migrate-settings.sh`, both the
recognition and the move of team content are a script with tests in CI, not
prose.

## Requirements

- REQ-1 (no CLAUDE.md is generated): no setup mode writes a `CLAUDE.md`. This
  covers GREENFIELD, EXISTING and UPDATE; single project, workspace root and
  every application sub-project.
  - `agents-generation.md` has no step that generates one.
  - The `5, 5b` row of `setup/SKILL.md` no longer says "and CLAUDE.md".
  - The Step 9 summaries in `existing.md` and `greenfield.md`, and the
    full-stack bullet in `greenfield.md` 8.5, list no `CLAUDE.md`.
  - `profiles/nextjs.md` no longer presents a `CLAUDE.md` shim as a canonical
    file.
  - The same holds for the built copies under `dist/dev-setup/`.
- REQ-2 (shim recognition, by a script): a new
  `templates/dev-setup/.claude/scripts/instruction-files.sh [--dir <path>] [--json]`
  scans the tree under `--dir` (default: the repository root, else the current
  directory). It skips `.git/`, `node_modules/` and `.claude/worktrees/`, and
  emits these keys:
  - `SHIMS`: every `CLAUDE.md` whose content is exactly `@AGENTS.md`, once
    trailing whitespace and carriage returns are stripped. Anything else in the
    file, including a leading blank line or a second line, makes it not a shim.
  - `CUSTOM`: every other `CLAUDE.md` or `.claude/CLAUDE.md` whose owning
    directory (the parent of `.claude/` for the second form) has an
    `AGENTS.md`.
  - `UNIMPORTED`: the subset of `CUSTOM` with no line exactly equal to
    `@AGENTS.md`.
  - `LOCAL`: every `CLAUDE.local.md`.

  Paths are relative to `--dir`, one per line. An empty list is the empty string.
- REQ-3 (files above the project): the script emits `ABOVE`. It holds the
  absolute paths of every `CLAUDE.md`, `.claude/CLAUDE.md` and `CLAUDE.local.md`
  in the directories strictly above `--dir`, up to `/`. It always leaves out
  `$HOME/.claude/CLAUDE.md`, the user file the docs say does not count.
- REQ-4 (client version): the script emits `CLAUDE_VERSION`,
  `MIN_CLAUDE_VERSION` and `VERSION_OK`.
  - `CLAUDE_VERSION` is the first `N.N.N` token of `claude --version`.
  - `MIN_CLAUDE_VERSION` is `2.1.281`, the script's single constant.
  - `VERSION_OK` is `true` or `false` from a numeric comparison per component
    (so `2.1.29` and `2.1.99` are below the floor and `2.1.1000` is above it).
    It is empty when `claude` is not on `PATH` or its output has no version.
- REQ-5 (script contract): the script follows the plugin script contract.
  - `--json` prints one flat object with exactly the `UPPER_SNAKE` keys above.
  - `--merge <path>` (REQ-8) is the one other mode: it prints a file's content
    instead of the object, like `render-template.sh`.
  - Diagnostics go to stderr only.
  - A `--dir` that does not exist exits non-zero with nothing on stdout.
  - The script is read-only in every mode: a run leaves the scanned tree
    byte-identical.
- REQ-6 (version gate at Step 1): before it reports the mode, the setup's Step 1
  runs `instruction-files.sh --json`.
  - `VERSION_OK=false`: the setup stops before any write, with a message naming
    `CLAUDE_VERSION` and `MIN_CLAUDE_VERSION`. It explains that without a
    `CLAUDE.md` an older client reads no project instructions.
  - `VERSION_OK` empty: the setup continues and the summary carries
    `Claude Code version not verified — AGENTS.md needs <MIN_CLAUDE_VERSION> or later`.
- REQ-7 (shim removal, every mode): Step 5b removes every path in `SHIMS`
  without asking, at the root and in every sub-project. The summary carries
  `CLAUDE.md shim removed (AGENTS.md is read directly): <paths>`. A `CLAUDE.md`
  that is not in `SHIMS` is never removed without the developer's yes.
- REQ-8 (custom CLAUDE.md, moved by the script): for each path in `CUSTOM`,
  Step 5b asks the developer whether to move it.
  - The merged file comes from `instruction-files.sh --merge <path>` (path
    relative to `--dir`). It prints to stdout the owning directory's
    `AGENTS.md` (for `.claude/CLAUDE.md`, the parent of `.claude/`, as in
    REQ-2), byte for byte, followed by a `## Instructions moved from CLAUDE.md`
    section appended at the end of the file — after its `*Generated by:` footer
    line when it has one. Step 5's UPDATE offer leaves every line after the
    footer untouched in the root, workspace and sub-project files alike, and a
    team-written file with no footer has no tail to replace.
  - The section holds the `CLAUDE.md` content minus every line equal to
    `@AGENTS.md` (trailing whitespace stripped, as in REQ-2) and minus leading
    and trailing blank lines. If nothing is left, the output is the `AGENTS.md`
    unchanged.
  - A path not in `CUSTOM` exits non-zero with empty stdout. `--merge` writes
    nothing.
  - On a yes, Step 5b writes that output over the `AGENTS.md`, removes the
    `CLAUDE.md`, and the summary carries `<path> moved into <AGENTS.md path> and
    removed`.
  - On a no, the summary says the project stays on `CLAUDE.md`:
    - if the file imports `AGENTS.md`: `<path> kept: Claude Code reads it, and
      AGENTS.md only through its @AGENTS.md import`;
    - if the path is in `UNIMPORTED`: `<path> kept: Claude Code reads it and does
      NOT read <AGENTS.md path>`.
- REQ-9 (files the setup does not own): every `LOCAL` and `ABOVE` path is listed
  in the summary and never modified.
  - The `CLAUDE.local.md` line explains both ways out: move its content, or set
    **Project instructions** to `claude-md-and-agents-md` in
    `~/.claude/settings.json` under `pluginConfigs."cc-plugin-agents-md@builtin"`.
  - The setup never writes the user's `~/.claude/settings.json` and never writes
    `pluginConfigs` anywhere.
- REQ-10 (the floor is declared where the plugin states its requirements):
  `README.md` "**Prerequisites**" and `docs/onboarding.md` "You need" both name
  Claude Code `2.1.281` or later, on every machine and runner that works on the
  project. Both version strings equal the script's `MIN_CLAUDE_VERSION`.
- REQ-11 (subagents keep the instructions): no agent the plugin ships sets
  `omitClaudeMd`. These are `templates/dev-setup/.claude/agents/*.md` and
  `shared/agents/*.md`, including `review.md` (`code-reviewer`) and `verify.md`
  (`spec-verifier`). The docs say a subagent inherits the `AGENTS.md` read as
  project instructions unless that flag is set.
- REQ-12 (shipped and documented):
  - `instruction-files.sh` is listed in `manifest.json` `plugin_scripts` and
    built to `dist/dev-setup/scripts/`. The built tree matches the sources.
  - `README.md`, `docs/onboarding.md` and `docs/developer-guide.md` no longer
    list `CLAUDE.md` as a file the setup writes or regenerates.
  - `docs/migration-v2-to-v3.md` gains a breaking-change section and updated
    "How to migrate" rows.
  - The meta-repo `AGENTS.md` script table lists `instruction-files.sh`.
  - `bash scripts/test-plugin-scripts.sh` passes, `/project:validate` passes
    (checks 14–16 included), and `shellcheck --severity=warning` passes.

## Technical decisions

- **No `CLAUDE.md`, relying on Claude Code's default.** This follows the task's
  route 1 and the docs (rank 1). The plugin cannot set Project instructions:
  `plugin.json` `settings` applies only `agent` and `subagentStatusLine`, and
  `pluginConfigs` is ignored in project and local settings. The setup therefore
  writes no configuration for it, and it never writes the user's
  `~/.claude/settings.json`, which the sandbox denies anyway.
- **The floor is 2.1.281, not 2.1.277 (deviation).** The task says 2.1.277.
  The docs, which rank first, say that before v2.1.281, sessions on Amazon
  Bedrock or with telemetry disabled still read `CLAUDE.md` only. On
  2.1.277–2.1.280 such a project would run with no project instructions and
  show no error. That is exactly the Risk the task names, and the
  acceptance criteria promise (rank 2) that Claude Code reads `AGENTS.md`. The
  higher floor delivers that promise. The cost is one upgrade for clients on
  2.1.277–2.1.280.
- **Stop, not warn, below the floor.** The acceptance criteria allow either.
  Stopping before the first write means a project is never left without a
  `CLAUDE.md` on a client that cannot read `AGENTS.md`. When the version is
  unknown (no `claude` on `PATH`, for example the desktop app), the setup
  continues and the summary says the version was not verified. The setup does
  not refuse something it cannot measure.
- **Where the floor is declared.** `plugin.json` has no requirements field, so
  the floor is the constant in `instruction-files.sh`, which the setup enforces.
  The person-facing declarations are the two places the plugin already states
  its requirements: the "**Prerequisites**" line of `README.md` and the "You
  need" line of `docs/onboarding.md` (the task's "where the plugin declares its
  requirements"). A test keeps all three equal, so they cannot drift.
- **One read-only script, with the setup doing the writes.** This follows the
  `migrate-settings.sh` pattern from the meta-repo `AGENTS.md`: the recognition
  that can destroy team content, and the move of team content into another
  file, are code with tests, not prose. The script never writes anything.
  Step 5b runs `rm` on exactly the `SHIMS` paths, and writes the `--merge`
  output over an `AGENTS.md` only on the developer's yes — the same split as
  `render-template.sh`, which prints and lets the setup write.
  - The shim definition is strict: only `@AGENTS.md`, with trailing whitespace
    stripped. This follows the task's Risk.
  - The same script also answers the version question, because both answer the
    same question: will Claude Code read `AGENTS.md` here? It runs at Step 1 for
    the version and again at Step 5b, after Step 5 has written the `AGENTS.md`
    files, for the files.
- **`CUSTOM` only counts files that shadow an `AGENTS.md`.** A `CLAUDE.md` in a
  directory with no `AGENTS.md` (a library, for example) hides nothing, so the
  setup offers no move for it. A shim is removed wherever it sits, because
  removing `@AGENTS.md` loses nothing.
- **The step runs in every mode.** EXISTING finds shims too: `create-next-app`
  16.2 writes the same `@AGENTS.md` `CLAUDE.md` that `profiles/nextjs.md`
  documents. Removing it there changes no instruction Claude reads, so the rule
  is the same in every mode, and `setup/SKILL.md` names the shim beside the
  `dev-setup-*.md` exception to "Ask before overwriting".
- **The moved content is appended after the footer.** The plugin-owned tail
  starts at a different heading in each file: `## Available agents` in a root
  or workspace `AGENTS.md`, `## Project registry` in a sub-project one
  (`AGENTS.project-template.md`; `agents-generation.md` 5B UPDATE), none in a
  team-written one. In every one of them, Step 5's UPDATE offer leaves every
  line after the `*Generated by:` footer untouched (`agents-generation.md`,
  UPDATE offer point 2), and the tail comparison stops at the footer. One
  placement rule — the end of the file — needs no heading lookup, and the
  section survives the next tail replacement. Only the full regeneration loses
  it, as it loses every hand-written section today, and that option already
  says so.
- **Sessions that cannot read `AGENTS.md` (the task's Assumption, settled from
  the docs).**
  - `claude -p` and the Agent SDK load project instructions the same way, and
    the built-in mods keep running under `--bare`, `--safe-mode` and
    `disableAllHooks`.
  - Subagents inherit the `AGENTS.md` read as project instructions unless they
    set `omitClaudeMd`, which REQ-11 pins.
  - The `auto-sdd` dev agent runs in a worktree under `.claude/worktrees/<id>/`,
    but a subagent in its own worktree takes its instruction files from the
    main conversation, not from the worktree. So it gets the `AGENTS.md` the
    launching session read at the project root.
  - The cloud Routine and a CI job (the runners `.claude/auto-dev.json` exists
    for, `mcp-env.md` Step 7d; the `CLAUDE_CODE_REMOTE` session of
    `run-outcomes.md`) start on the runner's own client and never pass through
    Step 1's gate. A fresh container is always a first session, but the docs
    name only the first session after an upgrade from 2.1.276 or earlier among
    the skip cases, and since 2.1.281 a session that fetches no flags reads
    `AGENTS.md`. So a runner at or above the floor is covered; one pinned on
    2.1.277–2.1.280 with telemetry disabled is not, silently. No new gate: the
    two floor lines (REQ-10) say the floor applies on every machine and runner,
    and the merge request's by-hand checks include `/memory` in a cloud
    session.
  - The remaining cases are a client below the floor (REQ-6), a mod the user
    disabled in `/plugin`, and the first session after an upgrade from 2.1.276
    or earlier. The last two cannot be seen from the repository. One summary
    sentence names them.
- **`check-prerequisites.sh` keeps `CLAUDE.md` in `AVAILABLE_DOCS`.** A project
  that declined the move still has a team-written `CLAUDE.md`, and `verify`
  reads `AVAILABLE_DOCS`. Only the header comment changes: it describes
  `CLAUDE.md` as a team file, not one the plugin generates.
- **`templates/dev-setup/CHANGELOG.md` is not edited (deviation).** The task
  lists it, but release-please generates it from the commits
  (`release-please-config.json` `changelog-path`), and `AGENTS.md` forbids
  hand edits. The `feat(setup)!:` commit with its `BREAKING CHANGE:` footer is
  the changelog entry.
- **No change to `.specs/DE-17130-*.md`.** DE-17130 is implemented. Its spec
  records what was true then, and no generated `AGENTS.*template.md` mentions
  `CLAUDE.md`.
- **The mod's test fixture is not a generated file.** `/p/CLAUDE.md` in
  `mod/tests/lib.test.ts` is a sample memory-file entry for the context view.
  It stays.

## Impact

- **Files to create**:
  - `templates/dev-setup/.claude/scripts/instruction-files.sh`
  - `dist/dev-setup/scripts/instruction-files.sh` (generated by the build)
- **Files to modify**:
  - `templates/dev-setup/manifest.json`
  - `templates/dev-setup/setup/SKILL.md`
  - `templates/dev-setup/setup/reference/agents-generation.md`
  - `templates/dev-setup/setup/reference/existing.md`
  - `templates/dev-setup/setup/reference/greenfield.md`
  - `templates/dev-setup/profiles/nextjs.md`
  - `templates/dev-setup/.claude/scripts/check-prerequisites.sh` (comment only)
  - `scripts/test-plugin-scripts.sh`
  - `README.md` (line 38 prerequisites, line 118 diagram)
  - `docs/onboarding.md`
  - `docs/developer-guide.md`
  - `docs/migration-v2-to-v3.md`
  - `AGENTS.md` (script table row, version 2.31.0 → 2.32.0)
  - `dist/dev-setup/**` (regenerated by `bash scripts/build-plugin.sh dev-setup`,
    never edited by hand)
- **Dependencies**: none (bash + `jq`, per the script contract)

## Implementation plan

1. `feat(setup): add instruction-files.sh to tell which instruction file Claude
   Code reads`
   - Write the script on `common.sh`, which provides JSON emission and repo-root
     resolution. It covers `--dir`, the pruned `find`, the `SHIMS` / `CUSTOM` /
     `UNIMPORTED` / `LOCAL` / `ABOVE` lists, `claude --version` parsing, a
     per-component numeric version comparison against the `2.1.281` constant,
     and the `--merge <path>` mode (append after the end of the owning
     `AGENTS.md`, `@AGENTS.md` lines and edge blank lines dropped, non-zero
     exit for a path not in `CUSTOM`).
   - Add it to `manifest.json` `plugin_scripts`.
   - Add a `── instruction-files.sh ──` block to `test-plugin-scripts.sh`
     (Tests 1–5 and 8b).
   - Rebuild `dist/`.
2. `feat(setup)!: stop generating CLAUDE.md and let Claude Code read AGENTS.md`
   - `SKILL.md`:
     - Step 1 first runs the script and stops on `VERSION_OK=false`.
     - The `5, 5b` row becomes "Generate AGENTS.md; check the instruction files".
     - "Ask before overwriting" names the shim exception.
     - Trim words elsewhere so the file stays ≤ 500 words.
   - `agents-generation.md`:
     - Rewrite the title, intro and index.
     - Replace Step 5b with "Check the instruction files": the
       shim/custom/local/above handling, the `--merge` call and the rule that
       the setup writes its output only on a yes, the after-the-footer
       placement, and the summary lines of REQ-6 to REQ-9.
     - Remove `CLAUDE.md` from the sub-project sentence.
   - `existing.md`, `greenfield.md`: drop `CLAUDE.md` from the summaries and from
     8.5, and name the 5b report lines.
   - `nextjs.md`: drop the shim block and say that Claude Code reads the
     `AGENTS.md` directly.
   - `check-prerequisites.sh` header comment; the comment above line 1842 of
     `test-plugin-scripts.sh`.
   - Add the prose tests 6–9 and 11.
   - Rebuild `dist/`.
   - Body footer: `BREAKING CHANGE: the setup no longer writes CLAUDE.md, and
     removes the @AGENTS.md shim on UPDATE; Claude Code 2.1.281 or later is
     required to read the project instructions.`
3. `docs: document AGENTS.md as the only instruction file and the Claude Code
   floor [DE-17167]`
   - `docs/onboarding.md`: "You need" gets Claude Code 2.1.281+ on every machine
     and runner, and the table row becomes `AGENTS.md`.
   - `README.md`: the line 38 "**Prerequisites**" gets the same floor, and the
     line 118 diagram drops `CLAUDE.md`.
   - `docs/developer-guide.md`: the UPDATE "Regenerated" row, plus a
     troubleshooting line for "AGENTS.md is not loading" that names a
     `CLAUDE.md`/`CLAUDE.local.md` above, and `/memory`.
   - `docs/migration-v2-to-v3.md`: a new `## 12. CLAUDE.md is gone: Claude Code
     reads AGENTS.md`, plus its index entry and the "How to migrate" rows.
   - `AGENTS.md`: script table row and version bump.
   - Add Tests 10 and 12.
   - Run `/project:validate` and the full suite.

## Test strategy

All tests are in `scripts/test-plugin-scripts.sh` unless noted. Fixtures are
built under the suite's work directory.

- Test 1 (REQ-2): a fixture tree with these files:
  - root `CLAUDE.md` = `@AGENTS.md\n`;
  - `apps/web/CLAUDE.md` = `@AGENTS.md  \r\n\n`;
  - `apps/api/CLAUDE.md` = `@AGENTS.md\nUse pnpm.`;
  - `apps/admin/.claude/CLAUDE.md` = `Be terse.`, with `apps/admin/AGENTS.md` present;
  - `libs/ui/CLAUDE.md` = `Notes`, with no `AGENTS.md` there;
  - `apps/x/CLAUDE.md` = `\n@AGENTS.md`;
  - `CLAUDE.local.md`;
  - `node_modules/pkg/CLAUDE.md` and `.claude/worktrees/DE-1/CLAUDE.md`, both shims.

  Every directory except `libs/ui` has an `AGENTS.md`. Assert:
  - `SHIMS` is exactly the root file and `apps/web/CLAUDE.md`;
  - `CUSTOM` is exactly `apps/api/CLAUDE.md`, `apps/admin/.claude/CLAUDE.md`
    and `apps/x/CLAUDE.md`;
  - `UNIMPORTED` is exactly `apps/admin/.claude/CLAUDE.md`;
  - `LOCAL` is `CLAUDE.local.md`;
  - nothing under `node_modules/` or `.claude/worktrees/` appears;
  - `libs/ui/CLAUDE.md` appears in no list.
- Test 2 (REQ-3): put the fixture at `<base>/parent/proj` with
  `<base>/parent/CLAUDE.local.md` and `<base>/CLAUDE.md`. Set `HOME=<base>` and
  create `<base>/.claude/CLAUDE.md`. Assert only on the lines of `ABOVE` under
  the fixture base (`case "$line" in "$BASE"/*)`), since in CI the meta-repo's
  tracked `CLAUDE.md` sits above the repo-local work dir: that subset is
  exactly `<base>/CLAUDE.md` and `<base>/parent/CLAUDE.local.md`, and
  `<base>/.claude/CLAUDE.md` appears on no line of `ABOVE`. For `<base2>/proj`,
  with no instruction file in `<base2>`, no line of `ABOVE` starts with
  `<base2>/`.
- Test 3 (REQ-4): a stub `claude` placed first on `PATH`.
  - It prints `2.1.281 (Claude Code)`, `2.1.300 (Claude Code)`,
    `2.2.0 (Claude Code)` and `2.1.1000 (Claude Code)` → `VERSION_OK=true`.
  - It prints `2.1.280`, `2.1.28`, `2.1.29 (Claude Code)` and
    `2.1.99 (Claude Code)` → `false`. The last three tell a numeric comparison
    from a string one.
  - With no `claude` on `PATH`, and with a stub printing `garbage` →
    `VERSION_OK=""` and `CLAUDE_VERSION=""`.
  - `MIN_CLAUDE_VERSION` is `2.1.281` in every case.
- Test 4 (REQ-5):
  - `--json` output passes `jq -e` and its key set equals the expected eight
    keys.
  - stdout has nothing but the object.
  - `--dir /nonexistent` exits non-zero with empty stdout and a message on stderr.
  - A checksum (`find … -type f -exec shasum`) of the Test 1 tree is identical
    before and after a run, and after every `--merge` call of Test 8b.
- Test 5 (REQ-12): `jq` finds `instruction-files.sh` in `manifest.json`
  `plugin_scripts`, and `dist/dev-setup/scripts/instruction-files.sh` exists
  after the build. The CI jobs `shellcheck` and `verify` cover lint and drift.
- Test 6 (REQ-1): search `templates/dev-setup/setup/SKILL.md`,
  `templates/dev-setup/setup/reference/*.md` and
  `templates/dev-setup/profiles/nextjs.md`, plus their copies
  `dist/dev-setup/skills/setup/SKILL.md`,
  `dist/dev-setup/skills/setup/reference/*.md` and
  `dist/dev-setup/skills/setup/templates/profiles/nextjs.md`. `grep -F` finds
  none of these strings:
  - `Generate AGENTS.md and CLAUDE.md`
  - `Generate CLAUDE.md`
  - `` `CLAUDE.md` is the one-line entry ``
  - `AGENTS.md / CLAUDE.md / REGISTRY.md`
  - `` generate a `CLAUDE.md` ``
  - `` generate `AGENTS.md`, `CLAUDE.md` ``
  - `` **`CLAUDE.md`** — the import shim ``

  `grep -E '^ *- `?CLAUDE\.md`? '` finds no summary row. Each of these is a line
  the tree holds today (checked), so the test is red before the change.
- Test 7 (REQ-6): `setup/SKILL.md` Step 1 names `instruction-files.sh` and
  `VERSION_OK=false`, and says the setup stops. `agents-generation.md` or the
  mode summaries carry the "version not verified" line. Check 1 of
  `/project:validate` keeps `SKILL.md` ≤ 500 words.
- Test 8 (REQ-7, REQ-8): `agents-generation.md` Step 5b:
  - names `SHIMS`, `CUSTOM` and `UNIMPORTED`;
  - holds the `CLAUDE.md shim removed` line, the `moved into` line and both
    `kept:` lines;
  - names `instruction-files.sh --merge` and the `*Generated by:` footer line
    the section is appended after, and does not anchor it on
    `## Available agents`.

  Check 16 of `validate-plugin.sh --strict` raises no `SETUP_ASK_UNREPORTED`
  for the new section. Test 1 is the guard that a custom file is never in
  `SHIMS`.
- Test 8b (REQ-8, the move itself), on a second fixture:
  - `apps/api/CLAUDE.md` = `@AGENTS.md\nUse pnpm.` and `apps/api/AGENTS.md` = a
    copy of `templates/dev-setup/AGENTS.project-template.md`. The output starts
    with the original `AGENTS.md` byte for byte (a `cmp` of its first `wc -c`
    bytes), the `## Instructions moved from CLAUDE.md` line comes after the
    `*Generated by:` footer, `Use pnpm.` follows it, and no line is
    `@AGENTS.md`. The lines from `## Project registry` to the footer are
    identical in input and output, so the UPDATE tail comparison still answers
    "already current".
  - Root `CLAUDE.md` = `Be terse.` beside a copy of `AGENTS.template.md`: same
    prefix check, and the `## Available agents`…footer lines are unchanged.
  - `apps/admin/.claude/CLAUDE.md`: the output is built from
    `apps/admin/AGENTS.md`.
  - A team-written `AGENTS.md` with no footer and no tail heading: the section
    comes after the original last line.
  - `apps/x/CLAUDE.md` = `\n@AGENTS.md`: the output equals `apps/x/AGENTS.md`
    byte for byte.
  - `--merge libs/ui/CLAUDE.md` exits non-zero with empty stdout.
- Test 9 (REQ-9):
  - (a) The Step 5b section of `agents-generation.md` (from `## Step 5b` to the
    next `## ` heading) names `LOCAL`, `ABOVE`, `claude-md-and-agents-md` and
    `cc-plugin-agents-md@builtin`, and no line in it matches
    `(>|mv |cp |tee ).*~/\.claude/settings\.json`.
  - (b) `jq -e 'has("pluginConfigs") | not'` holds for
    `templates/dev-setup/.claude/settings.json`,
    `templates/dev-setup/.claude/settings.user.json` and their copies in
    `dist/dev-setup/skills/setup/templates/`.
- Test 10 (REQ-10): the version on the "**Prerequisites**" line of `README.md`
  and on the "You need" line of `docs/onboarding.md` both equal the
  `MIN_CLAUDE_VERSION` that `instruction-files.sh --json` prints.
- Test 11 (REQ-11): `grep -l omitClaudeMd` over
  `templates/dev-setup/.claude/agents/*.md` and `shared/agents/*.md` returns
  nothing.
- Test 12 (REQ-12):
  - `README.md`, `docs/onboarding.md` and `docs/developer-guide.md` contain no
    `` `AGENTS.md`, `CLAUDE.md` `` pair and no `AGENTS.md, CLAUDE.md`.
  - `docs/migration-v2-to-v3.md` has the `## 12.` section and its index entry.
  - `bash scripts/validate-plugin.sh --strict` (checks 14–16) and the CI jobs
    are green.

## Notes

- The acceptance check "a new session shows `no CLAUDE.md found; AGENTS.md
  loaded: …`" and "a sub-project's `AGENTS.md` arrives when working on its
  file" are client behaviour. Nothing in CI can run them. Verify them by hand
  in the merge request on a client ≥ 2.1.281 (`/memory` lists the path), plus
  `/memory` in a cloud session, and list each there as verified or not
  verified.
- `InstructionsLoaded` hooks do not fire for an `AGENTS.md` read directly. The
  plugin registers none (`gate-commit`, `post-edit`, `post-merge-request`,
  `on-compact`), so nothing depends on it.
- A worktree under `.claude/worktrees/<id>/` also sees a `CLAUDE.local.md` at
  the main checkout's root, because that file is "above" it. The `LOCAL` report
  covers this case.
- Out of scope, worth a line: a `CLAUDE.md` symlinked to `AGENTS.md` is treated
  as custom, not as a shim (the setup never wrote one). The meta-repo's own
  `CLAUDE.md` (`@AGENTS.md`) is meta-repo tooling and stays.
