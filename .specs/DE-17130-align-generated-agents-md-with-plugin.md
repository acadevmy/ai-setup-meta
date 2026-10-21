# Spec: [dev-setup] Update the generated AGENTS.md and REGISTRY.md to the current plugin [DE-17130]

> Status: implemented
> Task: https://app.clickup.com/t/869fcez9p
> Branch: fix/DE-17130_align-generated-agents-md-with-plugin
> Created: 2026-10-12
> Approved: 2026-10-12

## Context

The setup writes an `AGENTS.md` into every project it configures — one for a
single project, one at the root and one per application in a workspace — and
that file is the one instruction every agent reads in every session. The prompt
audit of 2026-10-06 on `next` (03312d4) found it describing a plugin that does
not exist:

- the agents table names `review`, while the agent's frontmatter name is
  `code-reviewer` (`.claude/agents/review.md`), and omits `spec-verifier`
  (`verify.md`) and `finding-validator` (`validate-findings.md`);
- the commands table lists four of the six public commands — `quick` and
  `multi-sdd`, both `user-invocable: true`, are missing;
- the `sdd` row and the note under the table say "discusses it at each
  checkpoint" and "with supervision at each checkpoint", which contradicts the
  stops `sdd/SKILL.md` declares (launch, discovery, spec approval — DE-17076)
  and invites the model to stop between phases;
- "Where the rules live" sends git conventions to `.claude/rules/`, while
  `core.md` says they are in the `vcs-ops` skill;
- `REGISTRY.md` says "Claude Code reads this at the start of each session" and
  the sub-project template says "**Always** read it at the start of a new
  session", while nothing loads it — the generated `CLAUDE.md` imports only
  `@AGENTS.md` — and the single-project template already says the right thing:
  "Read it before adding something that may already exist";
- the sub-project template lists test and lint but not the type-check, which
  the commit gate runs and the workspace template points at; adding the
  placeholder without its rendering rule in `agents-generation.md` makes
  `render-template.sh` fail on it.

Half of the fix is the templates. The other half is UPDATE: today
`agents-generation.md` offers to replace only the `## Workflows` table and the
agents table of an existing file, so the note with the stops, the rules row and
the registry sentence would reach fresh setups only. Discovery settled the four
open points: the stops are **named**, never counted (the task's "two stops" was
written before DE-17076 added the discovery stop); UPDATE carries the **whole
plugin-owned tail** of the file; the agents table lists **all three** shipped
agents; `REGISTRY.md` is fixed for **fresh setups only**, since in UPDATE mode
it is the team's file and nothing loads it anyway.

Related: DE-17079 point 5 (a shorter generated `AGENTS.md`) — these fixes must
not lengthen it. DE-17128 removed the quality-command question from the flow.

## Requirements

- REQ-1: The agents table of `AGENTS.template.md` and `AGENTS.workspace-template.md`
  lists every agent the plugin ships, by frontmatter name — `clickup`,
  `code-reviewer`, `spec-verifier`, `finding-validator` — and no `review` row.
- REQ-2: The `## Workflows` table of both root templates lists exactly the
  `user-invocable: true` skills — `setup`, `quick`, `sdd`, `auto-sdd`,
  `multi-sdd`, `review` — one row each, with a "when to use" line; `quick`'s
  row carries the three-files bar and `sdd`'s says everything above it.
- REQ-3: The `sdd` row and the note under the table name the stops — launch
  (the fork point and how far the run goes), the discovery questions, the
  developer's approval of the spec — and say the flow stops nowhere else.
  Neither template contains "each checkpoint".
- REQ-4: In "Where the rules live", the rules-on-the-code row no longer lists
  `git`, and a row sends branch, commit and merge-request conventions to the
  `vcs-ops` skill.
- REQ-5: `AGENTS.project-template.md` and `REGISTRY.md` say "Read it before
  adding something that may already exist." No generated file says the registry
  is read at the start of a session.
- REQ-6: `AGENTS.project-template.md` carries `- **Type-check**:
  \`{{TYPECHECK_COMMAND}}\``, and `agents-generation.md` 5B names
  `{{TYPECHECK_COMMAND}}` among the per-sub-project placeholders, in the wrapped
  form. Every placeholder any of the three templates declares is one
  `agents-generation.md` tells the setup how to fill.
- REQ-7: In UPDATE mode, on an existing root `AGENTS.md`, the setup compares the
  plugin-owned tail — from the `## Available agents` heading to the version
  footer — with the template's and offers to replace that tail as one block,
  quoting the rows that go and the rows that arrive; every line above the
  heading is left untouched; the full regeneration stays the second option,
  with its cost stated; a file with no `## Available agents` heading gets the
  full-regeneration offer only. The outcome has a summary line: updated,
  declined (naming what the file still gets wrong), or already current. A
  sub-project `AGENTS.md` gets the same offer for its tail (from `## Project
  registry`) plus the type-check line when its commands section lacks one.
- REQ-8: The single and workspace templates are not longer than today (131 and
  136 lines); the sub-project template gains at most the type-check line (30).
- REQ-9: `dist/dev-setup` is rebuilt in the same change; `bash
  scripts/test-plugin-scripts.sh` pins REQ-1 to REQ-8; `bash
  scripts/validate-plugin.sh --strict` (checks 14–15 included) and the
  history-phrase assertion stay green.

## Technical decisions

- **The tables are pinned to the plugin's own surface, not to a list in the
  test.** The suite derives the public commands from every `user-invocable:
  true` frontmatter and the agents from the `name:` of every file under
  `.claude/agents/` and `shared/agents/`, and asserts each appears as a row —
  so the next skill or agent added without a row is red, and so is a row for
  one removed. The same rule the `/dev-setup` mod uses for its catalogue.
- **Stops are named, not counted.** "It stops at launch (the fork point and how
  far the run goes), at the discovery questions and for your approval of the
  spec — nowhere else." A number went stale once already (the task's "two").
  This deviates from the task's proposed wording, by decision at discovery.
- **UPDATE compares content, and the boundary is a heading.** Everything from
  `## Available agents` to the footer holds no project value — the sections
  above (Identity, Infrastructure, Stack, Quality, Before implementing,
  Language, MCPs, the VCS note) carry the team's answers and the detected
  commands and are never compared. One block, one offer: a per-table offer
  would leave the note between the tables behind, which is the defect this
  task is about. The version footer is inside the tail, so it is updated by
  the same offer and is never read as a signal. An older file without the
  heading predates the tail; there the existing full-regeneration offer stands.
- **The offer reports, in the shape `settings.json` already uses.** Three
  lines for the summary — `AGENTS.md: plugin sections updated (agents,
  commands, where the rules live)`, `AGENTS.md: plugin sections DECLINED — it
  still names …`, `AGENTS.md already current` — so a declined offer is
  visible, which is the UPDATE-path question the repository's AGENTS.md asks
  of every generated artefact. (Check 16 does not match "offer", but the rule
  it enforces applies.)
- **The recognition rule keeps its one history phrase.** The suite asserts
  that `agents-generation.md` is one of exactly three files allowed a "no
  longer": the rule describing the old shapes an UPDATE has to recognise. It
  stays, extended with the shapes this task adds (a `review` row, a four-row
  Workflows table). No history phrase enters the templates.
- **`REGISTRY.md`: fresh setups only.** `install.md` makes it the team's file
  in UPDATE mode and the review finds its sections by exact text; its header
  line is not one of those, but a one-line edit would need its own ask for a
  sentence nothing acts on once `AGENTS.md` is right.
- **The length budget is met by shortening what grew stale**, in this order:
  the note under the Workflows table (nine lines, mostly `auto-sdd`), the
  two-line preamble of the agents table, the three-line `Rationale:` paragraph
  of "Before implementing" — a justification the model does not act on. The
  `## Test and lint commands` heading of the sub-project template keeps its
  name: the workspace template cites it by name.
- **Version footers bump** (3.0.0 → 3.1.0, 2.0.0 → 2.1.0, 1.1.0 → 1.2.0) as
  the record of the change, nothing more.
- **Docs.** The developer guide's UPDATE table row for `AGENTS.md` says the
  narrow offer comes first; the migration page's row stays true as written.
  The setup summary's "Available commands" list is out of scope (Notes).

## Impact

- **Files to create**: `.specs/DE-17130-align-generated-agents-md-with-plugin.md`
- **Files to modify**:
  - `templates/dev-setup/AGENTS.template.md`
  - `templates/dev-setup/AGENTS.workspace-template.md`
  - `templates/dev-setup/AGENTS.project-template.md`
  - `templates/dev-setup/REGISTRY.md`
  - `templates/dev-setup/setup/reference/agents-generation.md`
  - `scripts/test-plugin-scripts.sh`
  - `docs/developer-guide.md`
  - `README.md` — its own agents table and two tree comments named `review` as
    the one agent, the defect this task removes from the generated file (added
    at review)
  - `dist/dev-setup/skills/setup/templates/{AGENTS.template.md,AGENTS.workspace-template.md,AGENTS.project-template.md,REGISTRY.md}` and `dist/dev-setup/skills/setup/reference/agents-generation.md` — through `bash scripts/build-plugin.sh dev-setup`, never by hand
- **Dependencies**: none

## Implementation plan

1. **Tests first** — add a `DE-17130` block to `scripts/test-plugin-scripts.sh`
   after the DE-17128 block (same `flat` helper): the derived-surface
   assertions for the agents and commands tables, the named-stops phrases, the
   rules rows, the registry sentences, the placeholder subset check against
   `agents-generation.md` (`render-template.sh --list` on each template), the
   UPDATE boundary and summary lines, the line budgets. Run it: red.
2. **`AGENTS.template.md`** — agents table (four rows, one-line preamble),
   Workflows table (six rows), the note rewritten around the named stops and
   the two unsupervised commands, the rules table (`git` out, `vcs-ops` row
   in), footer 3.1.0; trim the `Rationale:` paragraph only if still over 131.
3. **`AGENTS.workspace-template.md`** — the same edits, with the sub-project
   wording of the `review` row kept; footer 2.1.0; at most 136 lines.
4. **`AGENTS.project-template.md`** — the type-check line, the registry
   paragraph reduced to the one sentence plus the review line, footer 1.2.0.
5. **`REGISTRY.md`** — the header line.
6. **`agents-generation.md`** — 5A: the UPDATE block becomes the tail rule
   (boundary, one offer, what is quoted, full regeneration second, the
   heading-less case, the three summary lines); the "Take the same approach to
   the agents table" sentence goes, since the tail covers it. 5B: add
   `{{TYPECHECK_COMMAND}}` to the per-sub-project bullet, and the UPDATE
   paragraph for a sub-project file. Index unchanged.
7. **`docs/developer-guide.md`** — the `AGENTS.md` row of the UPDATE table.
8. **Build** — `bash scripts/build-plugin.sh dev-setup`; `git status` must
   show only the five dist files above changed. Stage by path.
9. **Gates** — `bash scripts/test-plugin-scripts.sh` (with `TEST_TMPDIR` if
   the sandbox refuses the repo-local work directory), `bash
   scripts/validate-plugin.sh --strict`, `shellcheck --severity=warning
   scripts/test-plugin-scripts.sh`.

## Test strategy

- Test 1 (REQ-1): for every `name:` under `templates/dev-setup/.claude/agents/*.md`
  and `shared/agents/*.md`, both root templates have a `| **<name>** |` row;
  neither has a `| **review** |` row.
- Test 2 (REQ-2): for every skill with `user-invocable: true`, both root
  templates have a `` `/dev-setup:<name>`` row; the number of
  `/dev-setup:` rows equals the number of public skills.
- Test 3 (REQ-3): both root templates, flattened, contain "for your approval of
  the spec" and "nowhere else", and do not contain "each checkpoint".
- Test 4 (REQ-4): the "Rules on the code" row of both root templates does not
  contain "git"; a row contains "`vcs-ops`".
- Test 5 (REQ-5): none of the four generated files contains "start of each
  session" or "start of a new session"; the sub-project template and
  `REGISTRY.md` contain "before adding something that may already exist".
- Test 6 (REQ-6): `render-template.sh --list` on the sub-project template
  names `TYPECHECK_COMMAND`; for each of the three templates, every placeholder
  `--list` reports appears as `{{NAME}}` in `agents-generation.md`.
- Test 7 (REQ-7): `agents-generation.md`, flattened, names `## Available
  agents` as the boundary, `## Project registry` for the sub-project, and the
  three summary lines; the existing history-phrase assertion still lists it.
- Test 8 (REQ-8): `wc -l` ≤ 131 / 136 / 30 for the three templates.
- Test 9 (REQ-9): `validate-plugin.sh --strict` green locally; `dist/` in sync
  is CI's `verify` job.

## Notes

- **Open question, adjacent and not in the task**: both root templates and
  the sub-project template say "If any command shows "not detected", ask the
  developer which command to use before proceeding". DE-17128 settled that an
  empty command is skipped and reported, never asked — `gate-commit.sh`,
  `sdd-dev` and the dev agent all read `detect-stack.sh`. That sentence is a
  session-level ask the flow removed. Left as is unless pulled in at approval.
- **Open question, adjacent**: the setup summary's "Available commands" list
  in `existing.md` and `greenfield.md` names three of the six commands — same
  defect, in the summary rather than in a generated file. Not in the task.
- **Risk**: the history-phrase assertion expects `agents-generation.md` among
  the files that carry one; rewriting the UPDATE block must keep "no longer
  commands" in the recognition rule.
- **Risk**: this session runs in a sandboxed worktree; the build writes under
  `dist/`, and `git status` after it is the check that it wrote only there.
  Stage by path, never `git add -A`.
- **Risk**: a team that edited the tail by hand sees a diff it did not expect;
  the offer quotes it and asks, and a no is reported, never assumed.
- References: `templates/dev-setup/.claude/skills/sdd/SKILL.md` (the stops),
  `templates/dev-setup/rules/core.md` lines 52–53 (`vcs-ops`),
  `templates/dev-setup/setup/reference/install.md` 3.2 (`REGISTRY.md` in
  UPDATE), `scripts/validate-plugin.sh` check 16.
