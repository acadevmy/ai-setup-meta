# Spec: Tracker-agnostic task integration — ClickUp and Linear [MERC-222]

> Status: approved
> Task: MERC-222 (Multica)
> Branch: `feat/MERC-222-tracker-agnostic`, from `feat/parallel-adopt`
> Created: 2026-11-11
> Approved: 2026-11-12

## Context

The `dev-setup` plugin is wired to ClickUp from top to bottom. On
`feat/parallel-adopt` the word appears on about 300 lines in 48 shipped files
(outside `dist/`, `.specs/`, `docs/legacy/` and the meta repo's own
`.claude/`). Half of an abstraction already exists: every flow reaches the board
through the `clickup` subagent and an intent contract (`read`, `filter`,
`next-task`, `update`, `create`). Everything around that contract is ClickUp's
own:

| Coupling | Where |
|---|---|
| agent name, `tools:` frontmatter with `mcp__clickup__*` names, transition table | `shared/agents/clickup.md` |
| contract file name, `---CLICKUP-RESULT---` block, `custom_id`, `CLICKUP_SETUP_LIST_ID`, statuses spelled as ClickUp spells them | `templates/dev-setup/.claude/reference/clickup-contract.md` |
| board documentation, install-time list id substituted as `${user_config.CLICKUP_SETUP_LIST_ID}` | `shared/skills/clickup/SKILL.md`, `scripts/builders/build-claude.sh` (plugin `userConfig`) |
| `mcp__clickup__*` allow and ask rules, `CLICKUP_API_TOKEN` | `templates/dev-setup/.claude/settings.json` |
| MCP registration, `.env.example` line, `.claude/auto-dev.json` | `templates/dev-setup/setup/reference/mcp-env.md` (6.1, 7, 7d), `install.md`, `existing.md` |
| headless REST client with a personal token | `templates/dev-setup/.claude/scripts/auto-dev-clickup.sh`, called by `auto-dev-select.sh` (already takes `tracker: clickup \| none`) |
| prose and examples ("ClickUp task", `CODE REVIEW`, `DE-123`) | `kickoff` (+ `board.md`), `sdd` (`intake.md`, `closure.md`), `sdd-discovery`, `sdd-spec`, `quick`, `auto-dev`, `auto-sdd` (+ `workflows/auto-sdd-run.js`), `multi-sdd`, `devcontainer`, `vcs-ops`, PR templates, `AGENTS.template.md`, `AGENTS.workspace-template.md`, `docs/`, `README.md`, `AGENTS.md` |

A team on Linear gets nothing from the plugin's board half today, and the only
way in is to fork the prose. This task makes the tracker a project choice, with
ClickUp behaving exactly as now for a project that runs the setup again.

Two things already point the way: `.claude/auto-dev.json` maps canonical
statuses (`ready`, `in_progress`, `in_review`, `blocked`) to the board's names,
and `auto-dev-select.sh` already branches on a `tracker` value. The task
generalises both instead of inventing a parallel mechanism.

Scope settled in discovery (2026-11-11): base `feat/parallel-adopt`; ClickUp
and Linear only; no migration path for existing projects — they re-run the
setup.

## Requirements

- REQ-1: No skill, reference, workflow or template outside the adapter
  directories names an MCP tool, an MCP server or a status spelling of a
  specific tracker; every board operation goes through the `tracker` agent and
  the neutral contract (`tracker-contract.md`).
- REQ-2: The contract defines intents, parameters and result format with no
  tool names, and the flow's statuses as canonical values — `BACKLOG`,
  `READY` (today's `SPRINT`), `IN_PROGRESS`, `IN_REVIEW`, `DONE`, `BLOCKED` —
  with the transition table and the backlog gate stated on those values.
- REQ-3: One adapter file per tracker declares its MCP server and tools, the
  default map from canonical statuses to the board's names, the shape of the
  human task key and its capabilities.
- REQ-4: The project chooses its tracker through `.claude/tracker.json`
  (`clickup`, `linear` or `none`), overridable by `TRACKER_PROVIDER` /
  `TRACKER_LIST_ID`, resolved in one documented order.
- REQ-5: The setup asks which tracker the project uses (ClickUp, Linear, none),
  registers that tracker's MCP server, writes `tracker.json` and
  `.env.example`, and generates the `settings.json` permissions for that
  provider instead of the hardcoded `mcp__clickup__*` rules.
- REQ-6: The headless run (`auto-dev`) reaches the board through
  `auto-dev-tracker.sh`, which dispatches to a per-provider backend; today's
  `auto-dev-clickup.sh` body becomes the ClickUp backend with unchanged
  behaviour.
- REQ-7: ClickUp works as today through its adapter, once the setup has been
  re-run: every existing test in `scripts/test-plugin-scripts.sh` passes
  (rewritten only where it asserts a renamed file or string, never where it
  asserts behaviour).
- REQ-8: The Linear adapter is implemented and exercised on `read`, `update`
  and `create` against a real workspace.
- REQ-9: `docs/workflow.md`, `docs/developer-guide.md`, `docs/onboarding.md`,
  `docs/training.md`, `README.md`, `AGENTS.md` and the generated AGENTS
  templates speak of "the task tracker", with tracker-specific examples kept in
  the adapters; the CHANGELOG states that an existing project must re-run the
  setup.

## Technical decisions

**D1 — Canonical statuses, mapped per project.** The contract and the
transition table speak canonical values only. The real names live in
`.claude/tracker.json` (D3), written by the setup from the adapter's default
map. ClickUp default: `backlog · sprint · in progress · code review · done ·
blocked`, with `in review` as the second name for `IN_REVIEW`. Linear default:
the team's workflow states by type (`backlog`, `unstarted`, `started`,
`completed`) plus named `In Review` and `Blocked` states. `IN_REVIEW` keeps
today's "try the first name, fall back to the second" behaviour, expressed as a
list of names.

**D2 — One `tracker` agent, adapters as files it reads.**
`shared/agents/clickup.md` becomes `shared/agents/tracker.md`: fidelity rule,
contract, transition validation on canonical values, `---TRACKER-RESULT---`
format. Its first step resolves the provider (D3) and reads
`${CLAUDE_PLUGIN_ROOT}/reference/tracker-adapters/<provider>.md`, which maps
each intent to that tracker's tools. A subagent's `tools:` frontmatter is
static, so it lists the tools of both adapters; a tool whose server is not
configured is simply absent (to confirm in step 1). Discarded: one agent
generated per provider at setup time — it doubles what the builder and the
tests keep in step, and a plugin update would need a setup re-run to reach it.

**D3 — Configuration.** `.claude/tracker.json` (committed, no credentials)
holds `provider`, `lists` (ClickUp list ids, Linear team key / project id) and
`status` (D1). Resolution: `TRACKER_PROVIDER` / `TRACKER_LIST_ID` from the
environment, then `tracker.json`, then the plugin `userConfig`
(`TRACKER_PROVIDER`, `TRACKER_LIST_ID`) as the `tracker` skill states it, then
`none`. `.claude/auto-dev.json` keeps only what is specific to the unattended
run (`tag`, Figma, `dry_run`) and reads lists and statuses from `tracker.json`.
`CLICKUP_SETUP_LIST_ID`, `clickup_list_ids` and the old `status` block are
**not** read any more: a project configured by an older version re-runs the
setup (decision of 2026-11-11, see the decision log).

**D4 — Neutral result format.** The block is `---TRACKER-RESULT---`; the human
key field is `key` (ClickUp `custom_id`, Linear identifier `ENG-42`). Every
caller changes in the same PR, so no alias is kept.

**D5 — Capabilities.** The five intents on this base are covered by both
trackers. Adapters still declare `comments` and `time_tracking`, the only
differences that matter here: the clock's measurement goes to ClickUp's time
tracking, and on Linear (no time tracking) it travels only in the closing
comment, as it already does when ClickUp's call fails. An intent an adapter
cannot serve returns `STATUS: unsupported` with `CAPABILITY: <name>`, distinct
from `error`, so the intents `next` adds (doc pages, relations, task types) have
a place to land at the realignment.

**D6 — The task key stays `[A-Z][A-Z0-9]*-[0-9]+`.** The regex in
`common.sh`, `session-title.sh` and `mod/lib/clock.ts` already matches ClickUp
custom ids and Linear identifiers, so branch names, session titles and the
clock do not change.

**D7 — Headless backends.** `auto-dev-tracker.sh --provider <p>` keeps today's
CLI (`--read`, `--start`, `--finish`, `--json`) and keys, and sources
`scripts/tracker-backends/<p>.sh`. ClickUp backend: today's script body,
`CLICKUP_API_TOKEN`, header still passed on stdin. Linear backend: the GraphQL
API with `LINEAR_API_KEY`, same stdin rule. `auto-dev-select.sh` accepts any
provider with a backend. `auto-dev-clickup.sh` is removed.

**D8 — Permissions generated per provider.** The template's `settings.json`
drops the `mcp__clickup__*` lines; the setup merges a per-adapter fragment
(allow reads and the writes the flows make, ask on delete / move / merge /
remove or their Linear equivalents). The ClickUp fragment is exactly today's
lines.

**D9 — MCP server names are fixed by the setup.** Tool names depend on the name
the server is registered under (`mcp__<name>__…`), so the adapter states it and
the setup registers it with that name (`clickup`, `linear`). A developer who
reaches the tracker through a claude.ai connector gets other names
(`mcp__claude_ai_ClickUp__…`): the adapter lists both prefixes and the agent's
`tools:` carries both.

## Impact

- **Files to create**:
  - `templates/dev-setup/.claude/reference/tracker-contract.md`
  - `templates/dev-setup/.claude/reference/tracker-adapters/clickup.md`, `linear.md`
  - `shared/agents/tracker.md`, `shared/skills/tracker/SKILL.md`
  - `templates/dev-setup/.claude/scripts/auto-dev-tracker.sh`
  - `templates/dev-setup/.claude/scripts/tracker-backends/clickup.sh`, `linear.sh`
  - `templates/dev-setup/.claude/scripts/tracker-config.sh` (the D3 resolution, one place for every script)
  - `templates/dev-setup/setup/reference/tracker-permissions/clickup.json`, `linear.json`
  - test fixtures for the Linear backend (a fake GraphQL endpoint, like today's `CLICKUP_API_BASE` one)
- **Files to remove**: `shared/agents/clickup.md`,
  `shared/skills/clickup/SKILL.md`,
  `templates/dev-setup/.claude/reference/clickup-contract.md`,
  `templates/dev-setup/.claude/scripts/auto-dev-clickup.sh`
- **Files to modify**:
  - build and manifest: `scripts/builders/build-claude.sh` (`userConfig`),
    `templates/dev-setup/manifest.json`
  - settings and setup: `templates/dev-setup/.claude/settings.json`,
    `templates/dev-setup/setup/reference/mcp-env.md`, `install.md`,
    `existing.md`, `templates/dev-setup/.env.example`
  - scripts and hooks: `auto-dev-args.sh`, `auto-dev-select.sh`,
    `hooks/post-merge-request.sh`, `mod/lib/merge-request.ts`,
    `mod/tests/lib.test.ts`, `mod/tests/register.test.ts`,
    `workflows/auto-sdd-run.js`
  - skills: `kickoff` (+ `reference/board.md`), `sdd` (+ `intake.md`,
    `closure.md`), `sdd-discovery`, `sdd-spec` (+ `spec-template.md`),
    `quick`, `auto-dev`, `auto-sdd`, `multi-sdd` (+ `preflight.md`),
    `devcontainer/reference/contract.md`, `reference/run-outcomes.md`,
    `shared/skills/vcs-ops/SKILL.md`, `agents/review.md`
  - templates and docs: `boilerplate/PULL_REQUEST_TEMPLATE.{en,it}.md`,
    `AGENTS.template.md`, `AGENTS.workspace-template.md`, `CHANGELOG.md`,
    `docs/workflow.md`, `docs/developer-guide.md`, `docs/onboarding.md`,
    `docs/training.md`, `docs/migration-v2-to-v3.md`, `README.md`, `AGENTS.md`
  - tests: `scripts/test-plugin-scripts.sh`
  - not touched: `.specs/*` (history), `docs/legacy/*`, the meta repo's own
    `.claude/skills/auto-maintain` (it tracks the meta repo's ClickUp board,
    not a project's), `migrate-settings.sh`
- **Dependencies**: none in the plugin. Developers on Linear need the Linear
  MCP server (remote, OAuth) and, for headless runs, a `LINEAR_API_KEY`.

## Implementation plan

1. **Spike on the agent tool list** — check on the current Claude Code that a
   subagent's `tools:` may list tools of an unconfigured server without failing
   to load, and whether a server-level entry (`mcp__linear`) is accepted there.
   The answer fixes how D2 writes the frontmatter; record it in the decision
   log.
2. **Neutral contract and config resolution** — `tracker-contract.md`
   (canonical statuses, transitions, backlog gate, clock, bail-out, result
   format, `unsupported`) and `tracker-config.sh` with the D3 order, tested.
3. **ClickUp adapter and `tracker` agent** — move every ClickUp-specific line
   of `clickup.md` / `clickup-contract.md` into `tracker-adapters/clickup.md`;
   write `tracker.md` and the `tracker` skill. Builder, manifest and
   `userConfig` updated; `dist/` rebuilt; the suite green with only renames in
   the assertions.
4. **Callers on the contract** — every skill, reference, workflow and hook in
   the Impact list calls `tracker` and speaks canonical statuses. A test greps
   the shipped tree and fails on any `mcp__clickup`, `CLICKUP_` or ClickUp
   status spelling outside the adapter directories (REQ-1).
5. **Headless dispatch** — `auto-dev-tracker.sh` and the ClickUp backend;
   `auto-dev-select.sh` generalised; the existing headless tests pointed at the
   new entry point and still green.
6. **Setup and permissions** — `mcp-env.md` asks the tracker (ClickUp,
   Linear, none), registers its server, writes `tracker.json`, `.env.example`
   and the permission fragment; `auto-dev.json` reduced as in D3.
7. **Linear adapter and backend** — `tracker-adapters/linear.md`,
   `tracker-backends/linear.sh`, permission fragment, fixtures; then the real
   check on a Linear workspace: `read`, `update` through the whole transition
   table, `create`, and one headless `--read/--start/--finish` (REQ-8).
8. **Docs and generated AGENTS.md** — the files in the Impact list's last
   group; CHANGELOG entry saying a configured project must re-run the setup.

## Test strategy

- Test 1 (REQ-1): the grep test of step 4 over `templates/`, `shared/` and
  `dist/`, adapter directories excluded.
- Test 2 (REQ-2): the contract states each canonical status and each
  transition; the ClickUp adapter maps every canonical status.
- Test 3 (REQ-3): every file in `tracker-adapters/` has the required sections
  (server, tools, status map, key format, capabilities).
- Test 4 (REQ-4): `tracker-config.sh` on four fixtures — env only,
  `tracker.json` only, `userConfig` only, nothing → `none`; env wins over the
  file; a legacy `CLICKUP_SETUP_LIST_ID` alone resolves to `none`.
- Test 5 (REQ-5): the template `settings.json` has no `mcp__clickup`; merging
  the ClickUp fragment reproduces today's allow/ask set exactly; merging the
  Linear one gives the Linear set.
- Test 6 (REQ-6): today's `auto-dev-clickup.sh` tests run against
  `auto-dev-tracker.sh --provider clickup` with the same output; the Linear
  backend against a fake GraphQL endpoint for `--read`, `--start`, `--finish`
  (ready-for-mr and failed).
- Test 7 (REQ-7): the whole existing suite green.
- Test 8 (REQ-8): manual, recorded in the merge request — the real Linear run
  of step 7.
- Test 9 (REQ-9): the grep test also covers `docs/`, `README.md`, `AGENTS.md`
  and the AGENTS templates, outside the sections that list the supported
  trackers.

## Decision log

- 2026-11-11 · **Base `feat/parallel-adopt`, not `next`**: the developer's choice. `next` carries the `story` command, the `relate` / `search` / doc intents and `product-context.md` (20 commits ahead), which this task therefore does not cover. Discarded: branching from `next`, or from `feat/parallel-adopt` with `next` merged in — both would widen the PR beyond what the base the chain lands on holds.
- 2026-11-11 · **ClickUp and Linear only**: the developer's choice. Jira, Asana and Notion stay out; Asana would also need a decision on branch keys, having no `ABC-123` identifier.
- 2026-11-11 · **No migration path**: the developer's choice — an existing project re-runs the setup. This replaces the acceptance criterion "projects with `CLICKUP_SETUP_LIST_ID` keep working without manual intervention". Consequences: no legacy fallback in the config resolution, no `custom_id` alias, no `auto-dev-clickup.sh` wrapper, no `migrate-settings.sh` step. Discarded: an automatic fallback on `CLICKUP_SETUP_LIST_ID` — cheap, but it keeps the old name alive in the shipped tree and in the tests.
- 2026-11-11 · **Linear test team has no `Blocked` state**: the workspace provided for the real check (one team, `HOFJ`) has `Backlog`, `Todo`, `In Progress`, `In Review` (type `started`), `Done`, `Canceled`, `Duplicate`. The risk below is real on the first board tried: the setup must let `BLOCKED` map to a state the team picks (or to a label), not assume a state named `Blocked`. Discarded: creating the state on the team from the setup — the plugin does not reshape a team's workflow.
- 2026-11-12 · **Real Linear check on `HOFJ`, on a throwaway issue**: the developer's choice — no separate test team; the issue created for step 7 is disposable and is cancelled at the end. The team's PM will add a `Blocked` state, so the adapter keeps `Blocked` as its default name; the `-> BLOCKED` transitions of the real check run once that state exists, and are reported as not verified if it does not yet. The setup still lets a team map `BLOCKED` to a state of its choice.
- 2026-11-11 · **Statuses: generalise the `auto-dev.json` map instead of a new mechanism**: the project already declares its board's status names there for the unattended run. Discarded: a fixed map per adapter with no project override — boards rename their columns.

## Notes

**Realignment on `next`.** When #154 and #163 land, this branch meets the
`story` command and the extended ClickUp contract on `next`. The realignment
has to port those intents (`relate`, `search`, `create-doc`, `create-page`,
`update-page`, `task_type`, `parent`, `tags`) and `product-context.md`'s direct
ClickUp calls onto the contract: ClickUp adapter entries, `unsupported` on
Linear where it has no equivalent (doc pages), and the callers' degradation.
That work is not in this PR; it is the expected cost of the base choice.

**Risks.**

- A claude.ai connector exposes the tracker under different tool names
  (`mcp__claude_ai_ClickUp__…`). D9 covers both prefixes; step 1 confirms it is
  enough.
- `custom_id` is read outside the agent's result (hooks, the mod, the clock):
  without an alias, every reader must move to `key` in the same PR, and the
  grep test must catch the ones left.
- Linear's state types do not name `IN_REVIEW` or `BLOCKED`: the map needs
  named states, which a team may not have. The setup asks; a missing state is a
  setup error, not a runtime one.
- A project updated to this version without re-running the setup resolves to
  `none`: the flows run without a board instead of failing. The CHANGELOG and
  the setup's update check must say so plainly.
- Size: about 50 files. One PR, one commit per plan step, a guide in the
  description.
