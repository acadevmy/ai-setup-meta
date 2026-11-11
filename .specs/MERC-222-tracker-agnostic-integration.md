# Spec: Tracker-agnostic task integration — ClickUp as the first adapter, Linear as the second [MERC-222]

> Status: draft
> Task: MERC-222 (Multica). No ClickUp task yet — to create on approval, if wanted
> Branch: not created yet — proposed `feat/MERC-222-tracker-agnostic` (see Notes, "Base branch")
> Created: 2026-11-11
> Approved: pending

## Context

The `dev-setup` plugin is wired to ClickUp from top to bottom. On `origin/next`
the word appears on 453 lines in 80 files outside `dist/` (358 lines in 65 files
on `feat/parallel-adopt`, which does not have the `story` command yet). Half of
an abstraction already exists: every flow reaches the board through the
`clickup` subagent and an intent contract (`read`, `filter`, `next-task`,
`update`, `create`, `relate`, `search`, `create-doc`, `create-page`,
`update-page`). Everything around that contract is ClickUp's own:

| Coupling | Where |
|---|---|
| agent name, `tools:` frontmatter with `mcp__clickup__*` names, transition table | `shared/agents/clickup.md` |
| contract file name, `---CLICKUP-RESULT---` block, `custom_id`, `CLICKUP_SETUP_LIST_ID`, the canonical statuses spelled as ClickUp spells them | `templates/dev-setup/.claude/reference/clickup-contract.md` |
| board documentation, install-time list id substituted as `${user_config.CLICKUP_SETUP_LIST_ID}` | `shared/skills/clickup/SKILL.md`, `scripts/builders/build-claude.sh` (plugin `userConfig`) |
| `mcp__clickup__*` allow and `mcp__clickup__clickup_delete_*` / `move_*` / `merge_*` / `remove_*` ask rules, `CLICKUP_API_TOKEN` | `templates/dev-setup/.claude/settings.json`, `migrate-settings.sh` |
| MCP registration and `.env.example` line | `templates/dev-setup/setup/reference/mcp-env.md` (6.1, 7, 7d), `install.md`, `existing.md` |
| headless REST client with a personal token | `templates/dev-setup/.claude/scripts/auto-dev-clickup.sh`, called by `auto-dev-select.sh` (already takes `tracker: clickup \| none`) |
| `.claude/auto-dev.json` with `clickup_list_ids` and a `status` map of the board's names | `mcp-env.md` 7d, `auto-dev-args.sh`, `auto-dev-select.sh` |
| direct `mcp__clickup__clickup_*_document_pages` calls, outside the agent | `setup/reference/product-context.md`, its `allowed-tools` |
| prose and examples ("ClickUp task", `CODE REVIEW`, `DE-123`) | `kickoff`, `sdd` (`intake.md`, `closure.md`), `sdd-discovery`, `sdd-spec`, `quick`, `auto-dev`, `auto-sdd` (+ `workflows/auto-sdd-run.js`), `multi-sdd`, `story`, `devcontainer`, `vcs-ops`, PR templates, `AGENTS.template.md`, `AGENTS.workspace-template.md`, `docs/`, `README.md`, `AGENTS.md` |

A team on Linear, Jira, Asana or Notion gets nothing from the plugin's board
half today, and the only way in is to fork the prose. This task makes the
tracker a project choice, with ClickUp behaving exactly as now.

Two things already point the way: `.claude/auto-dev.json` maps canonical
statuses (`backlog`, `ready`, `in_progress`, `in_review`, `blocked`) to the
board's names, and `auto-dev-select.sh` already branches on a `tracker` value.
The task generalises both instead of inventing a parallel mechanism.

## Requirements

- REQ-1: No skill, reference, workflow or template outside `adapters/` names an
  MCP tool, an MCP server or a status spelling of a specific tracker; every
  board operation goes through the `tracker` agent and the neutral contract
  (`tracker-contract.md`).
- REQ-2: The contract defines intents, parameters and result format with no
  tool names, and the flow's statuses as canonical values — `BACKLOG`,
  `READY` (today's `SPRINT`), `IN_PROGRESS`, `IN_REVIEW`, `DONE`, `BLOCKED` —
  with the transition table and the backlog gate stated on those values.
- REQ-3: One adapter file per tracker declares its MCP server and tools, the
  map from canonical statuses to the board's names, the shape of the human task
  key, the capabilities it supports and the degradation for each one it does
  not.
- REQ-4: The project chooses its tracker through a `tracker` setting
  (`clickup`, `linear`, … or `none`) plus generic variables
  (`TRACKER_PROVIDER`, `TRACKER_LIST_ID`), resolved in a documented order; a
  project that only has `CLICKUP_SETUP_LIST_ID` resolves to `clickup` with that
  list, with no manual step.
- REQ-5: The setup asks which tracker the project uses (or none), registers
  that tracker's MCP server, writes `.env.example` and generates the
  `settings.json` permissions for that provider instead of the hardcoded
  `mcp__clickup__*` rules.
- REQ-6: The headless run (`auto-dev`) reaches the board through
  `auto-dev-tracker.sh`, which dispatches to a per-provider backend;
  `auto-dev-clickup.sh` becomes the ClickUp backend with unchanged behaviour.
- REQ-7: ClickUp works as today through its adapter: every existing test in
  `scripts/test-plugin-scripts.sh` passes (rewritten only where it asserts a
  renamed file or string, never where it asserts behaviour).
- REQ-8: A second adapter (Linear) is implemented and exercised on `read`,
  `update` and `create` against a real workspace.
- REQ-9: `docs/workflow.md`, `docs/developer-guide.md`, `docs/onboarding.md`,
  `README.md`, `AGENTS.md` and the generated `AGENTS.template.md` speak of "the
  task tracker", with tracker-specific examples kept in the adapters.

## Technical decisions

**D1 — Canonical statuses, mapped per project.** The contract and the
transition table speak canonical values only. The real names live in one place
per project: today's `.claude/auto-dev.json` `status` map, promoted to
`.claude/tracker.json` (D3). The adapter carries the default map for its
tracker (ClickUp: `backlog · sprint · in progress · code review · blocked`,
fallback `in review`; Linear: the team's workflow states by *type* —
`backlog`, `unstarted`, `started`, `completed`, plus named `In Review` and
`Blocked` states). `IN_REVIEW` keeps today's "try the preferred name, fall back
to the second" behaviour, expressed as a list of names in the map.

**D2 — One `tracker` agent, adapters as files it reads.** `shared/agents/clickup.md`
becomes `shared/agents/tracker.md`: fidelity rule, contract, transition
validation on canonical values, the `---TRACKER-RESULT---` format. Its first
step resolves the provider (D3) and reads
`${CLAUDE_PLUGIN_ROOT}/reference/tracker-adapters/<provider>.md`, which maps
each intent to that tracker's tools. An agent's `tools:` frontmatter is static,
so it lists the union of the shipped adapters' tools; a tool whose server is
not configured is simply absent. The ClickUp-specific procedures (the
asynchronous task-type template, tag reporting) move into `clickup.md`
unchanged. Discarded: one generated agent per provider at setup time — it
multiplies what the builder and the tests must keep in step, and a plugin
update would need a re-run of the setup to reach the agent.

**D3 — Configuration and its resolution order.** `.claude/tracker.json`
(committed, no credentials) holds `provider`, `lists` (list / team / project /
board / database ids), `status` (D1), and adapter options (Jira project key,
Notion key property). `.claude/auto-dev.json` keeps only what is specific to
the unattended run (`tag`, Figma, `dry_run`) and reads the rest from
`tracker.json`; `clickup_list_ids` and `status` there remain read as a fallback.
Resolution of the provider and the default list:

1. `TRACKER_PROVIDER` / `TRACKER_LIST_ID` from the environment;
2. `.claude/tracker.json`;
3. the plugin `userConfig` (`TRACKER_PROVIDER`, `TRACKER_LIST_ID`) as the
   `tracker` skill states it;
4. legacy: `CLICKUP_SETUP_LIST_ID` (environment, then `userConfig`) → provider
   `clickup`, that list;
5. nothing → `none`.

Discarded: a `migrate-settings.sh` step as the only path — a project that never
reruns the setup would break on the plugin update (see Notes, Q3).

**D4 — Neutral result format, with an alias for one release.** The block is
`---TRACKER-RESULT---`; the human key field is `key` (ClickUp `custom_id`,
Linear/Jira identifier). For one minor release the ClickUp adapter also emits
`custom_id` so a caller not yet migrated keeps working; the alias is removed in
the next minor, noted in the CHANGELOG.

**D5 — Capabilities declared, absences explicit.** Each adapter declares
`docs`, `task_types`, `parent`, `relations`, `tags`, `time_tracking`,
`comments`. An intent whose capability is absent returns
`STATUS: unsupported` with `CAPABILITY: <name>` — distinct from `error` — and
each caller states its degradation in its own skill: `story --map` writes the
map to a local file, `create` with `task_type` falls back to a label or a title
prefix when the adapter says so, the clock's measurement goes into the closing
comment when there is no time tracking. Never a silent no-op (see Notes, Q2).

**D6 — The task key stays `[A-Z][A-Z0-9]*-[0-9]+`.** The regex in
`common.sh`, `session-title.sh` and `mod/lib/clock.ts` already matches ClickUp
custom ids, Linear and Jira identifiers. An adapter whose tracker has no such
key must declare how it produces one (Notion: a `Unique ID` property with a
prefix, required by the adapter) or it is out of scope until it does (Asana:
see Notes, Q1). The branch-name contract in `vcs-ops` does not change.

**D7 — Headless backends.** `auto-dev-tracker.sh --provider <p>` keeps the
current CLI (`--read`, `--start`, `--finish`, `--json`) and the current keys,
and sources `scripts/tracker-backends/<p>.sh`. The ClickUp backend is today's
script body, token via `CLICKUP_API_TOKEN`, header still passed on stdin. The
Linear backend uses the GraphQL API with `LINEAR_API_KEY`, same stdin rule.
`auto-dev-select.sh` stops special-casing `clickup` and accepts any provider
with a backend. `auto-dev-clickup.sh` stays one release as a thin wrapper that
calls `auto-dev-tracker.sh --provider clickup`.

**D8 — Permissions generated per provider.** The template's `settings.json`
drops the `mcp__clickup__*` lines; the setup merges a per-adapter fragment
(allow reads and the writes the flows make, ask on delete / move / merge /
remove or their equivalents). `migrate-settings.sh` leaves an existing ClickUp
project's rules where they are — they are already that fragment.

**D9 — MCP server names are fixed by the setup.** Tool names depend on the name
the server is registered under (`mcp__<name>__…`), so the adapter states the
name and the setup registers it with that name (`clickup`, `linear`, …). A
developer who reaches the tracker through a claude.ai connector gets different
names (`mcp__claude_ai_ClickUp__…`); the adapter lists both prefixes and the
agent's `tools:` carries both (see Notes, risks).

## Impact

Paths as on `origin/next`; the base is discussed in Notes.

- **Files to create**:
  - `templates/dev-setup/.claude/reference/tracker-contract.md`
  - `templates/dev-setup/.claude/reference/tracker-adapters/clickup.md`
  - `templates/dev-setup/.claude/reference/tracker-adapters/linear.md`
  - `shared/agents/tracker.md`, `shared/skills/tracker/SKILL.md`
  - `templates/dev-setup/.claude/scripts/auto-dev-tracker.sh`
  - `templates/dev-setup/.claude/scripts/tracker-backends/clickup.sh`, `linear.sh`
  - `templates/dev-setup/.claude/scripts/tracker-config.sh` (the D3 resolution, one place for every script)
  - `templates/dev-setup/setup/reference/tracker-permissions/clickup.json`, `linear.json`
  - test fixtures for the Linear backend (a fake GraphQL endpoint, like today's `CLICKUP_API_BASE` one)
- **Files to remove** (replaced by the above, wrappers kept where D4/D7 say so):
  `shared/agents/clickup.md`, `shared/skills/clickup/SKILL.md`,
  `templates/dev-setup/.claude/reference/clickup-contract.md`
- **Files to modify**:
  - build and manifest: `scripts/builders/build-claude.sh` (`userConfig`),
    `templates/dev-setup/manifest.json`
  - settings and setup: `templates/dev-setup/.claude/settings.json`,
    `templates/dev-setup/.claude/scripts/migrate-settings.sh`,
    `templates/dev-setup/setup/reference/mcp-env.md`, `install.md`,
    `existing.md`, `product-context.md`, `templates/dev-setup/.env.example`
  - scripts and hooks: `auto-dev-args.sh`, `auto-dev-select.sh`,
    `auto-dev-clickup.sh` (wrapper), `hooks/post-merge-request.sh`,
    `mod/lib/merge-request.ts` and its tests, `workflows/auto-sdd-run.js`
  - skills: `kickoff` (+ `reference/board.md`), `sdd` (+ `intake.md`,
    `closure.md`), `sdd-discovery`, `sdd-spec` (+ `spec-template.md`),
    `quick`, `auto-dev`, `auto-sdd`, `multi-sdd` (+ `preflight.md`), `story`
    (+ `publish.md`, `model.md`, `templates.md`, `intake.md`,
    `frontmatter.schema.json`), `devcontainer/reference/contract.md`,
    `reference/run-outcomes.md`, `shared/skills/vcs-ops/SKILL.md`,
    `agents/review.md`
  - templates and docs: `boilerplate/PULL_REQUEST_TEMPLATE.{en,it}.md`,
    `AGENTS.template.md`, `AGENTS.workspace-template.md`,
    `product.template.md`, `CHANGELOG.md`, `docs/workflow.md`,
    `docs/developer-guide.md`, `docs/onboarding.md`,
    `docs/migration-v2-to-v3.md`, `README.md`, `AGENTS.md`
  - tests: `scripts/test-plugin-scripts.sh`
  - not touched: `.specs/*` (history), `docs/legacy/*`, the meta repo's own
    `.claude/skills/auto-maintain` (it tracks the meta repo's ClickUp board,
    not a project's)
- **Dependencies**: none in the plugin. Developers on Linear need the Linear
  MCP server (remote, OAuth) and, for headless runs, a `LINEAR_API_KEY`.

## Implementation plan

1. **Spike on the agent tool list** — check on the current Claude Code that a
   subagent's `tools:` may list tools of an unconfigured server without
   failing to load, and whether a server-level entry (`mcp__linear`) is
   accepted there. The answer fixes how D2 writes the frontmatter. Record it in
   the decision log.
2. **Neutral contract and config resolution** — write `tracker-contract.md`
   (canonical statuses, transitions, backlog gate, clock, bail-out, result
   format, `unsupported`) and `tracker-config.sh` with the D3 order, with tests
   for each step of the order and the legacy fallback.
3. **ClickUp adapter and `tracker` agent** — move every ClickUp-specific line
   of `clickup.md` / `clickup-contract.md` into `tracker-adapters/clickup.md`;
   write `tracker.md` and the `tracker` skill; emit `key` plus the `custom_id`
   alias. Builder, manifest and `userConfig` updated; `dist/` rebuilt; the
   suite green with only renames in the assertions.
4. **Callers on the contract** — every skill, reference, workflow and hook in
   the Impact list calls `tracker` and speaks canonical statuses;
   `product-context.md` reads docs through a new `read-doc` intent instead of
   direct ClickUp tools. A test greps the shipped tree and fails on any
   `mcp__clickup`, `CLICKUP_` or ClickUp status spelling outside
   `tracker-adapters/`, `tracker-backends/`, `tracker-permissions/` and the
   compatibility wrappers (REQ-1).
5. **Headless dispatch** — `auto-dev-tracker.sh` and the ClickUp backend;
   `auto-dev-clickup.sh` as wrapper; `auto-dev-select.sh` generalised; existing
   headless tests pointed at the new entry point and still green.
6. **Setup and permissions** — `mcp-env.md` asks the tracker (ClickUp, Linear,
   none; later adapters appear as they ship), registers its server, writes
   `tracker.json`, `.env.example` and the permission fragment;
   `auto-dev.json` reduced as in D3; `migrate-settings.sh` writes a
   `tracker.json` for a ClickUp project that lacks one.
7. **Linear adapter and backend** — `tracker-adapters/linear.md`,
   `tracker-backends/linear.sh`, permission fragment, fixtures; then the real
   check on a Linear workspace: `read`, `update` through the whole transition
   table, `create`, and one headless `--read/--start/--finish` (REQ-8).
8. **Docs and generated AGENTS.md** — the files in the Impact list's last
   group; CHANGELOG entry naming the deprecations (D4, D7).

## Test strategy

- Test 1 (REQ-1): the grep test of step 4 over `templates/`, `shared/` and
  `dist/`, with the adapter directories excluded.
- Test 2 (REQ-2): the contract states each canonical status and each
  transition; the ClickUp adapter maps every canonical status (assert on the
  file, as the suite does today for the clickup contract).
- Test 3 (REQ-3): every file in `tracker-adapters/` has the required sections
  (server, tools, status map, key format, capabilities) — a structural check.
- Test 4 (REQ-4): `tracker-config.sh` on six fixtures — env only, `tracker.json`
  only, `userConfig` only, legacy `CLICKUP_SETUP_LIST_ID` in env, legacy in
  `userConfig`, nothing → `none`; env wins over the file.
- Test 5 (REQ-5): setup fragments — the template `settings.json` has no
  `mcp__clickup`; merging the ClickUp fragment reproduces today's allow/ask
  set exactly; merging the Linear one gives the Linear set; migrating an old
  ClickUp `settings.json` leaves it unchanged and writes `tracker.json`.
- Test 6 (REQ-6): today's `auto-dev-clickup.sh` tests run against
  `auto-dev-tracker.sh --provider clickup` and against the wrapper, same
  output; the Linear backend against a fake GraphQL endpoint for `--read`,
  `--start`, `--finish` (ready-for-mr and failed).
- Test 7 (REQ-7): the whole existing suite green.
- Test 8 (REQ-8): manual, recorded in the merge request — the real Linear run
  of step 7.
- Test 9 (REQ-9): the grep test of step 1 also covers `docs/`, `README.md`,
  `AGENTS.md` and the AGENTS templates, outside the sections that list the
  supported trackers.

## Decision log

- 2026-11-11 · **The inventory is taken on `origin/next`, not on `feat/parallel-adopt`**: `next` carries the `story` command (#118), the `relate`/`search`/doc intents and `product-context.md`, none of which are on `feat/parallel-adopt`; specifying from the older base would leave the largest consumer of the contract out. Discarded: inventory on `feat/parallel-adopt` as the issue's base suggests.
- 2026-11-11 · **Statuses: generalise the `auto-dev.json` map instead of a new mechanism**: the project already declares its board's status names there for the unattended run. Discarded: hardcoding a default map per adapter with no project override — boards rename their columns.

## Notes

**Open questions for discovery — each with the recommendation the plan
assumes:**

- **Q1 — Which trackers now.** Recommended: ClickUp + Linear in this task
  (REQ-8); Jira next, as its own task, once Atlassian's remote MCP covers
  transitions reliably; Notion and Asana after. Asana has no human key of the
  `ABC-123` shape (only numeric gids), so it needs a decision on branch naming
  before an adapter makes sense; Notion needs a `Unique ID` property, which the
  adapter would require.
- **Q2 — Missing capabilities.** Recommended: explicit degradation stated by
  each caller, on an `unsupported` result (D5). An intent rejected outright
  would stop `story --map` on every tracker without docs, which is most of
  them.
- **Q3 — Migration of existing projects.** Recommended: both — the automatic
  fallback (D3 step 4) so nothing breaks on update, and `migrate-settings.sh`
  writing `tracker.json` on the next setup so the fallback can be removed one
  day.
- **Q4 — Epic / User Story and task types.** Recommended: in scope only as far
  as the contract needs it (`task_type` and `parent` become capabilities, D5);
  porting `story`'s hierarchy model to Linear (projects / sub-issues) or Jira
  (issue types) goes to a separate task.

**Base branch.** The issue asks for a branch from `feat/parallel-adopt` (PR
#163, stacked on #154). That branch is 20 commits behind `origin/next` on
exactly the files this task rewrites (the `story` command and the extended
ClickUp contract). Recommended: wait for #154 and #163 to merge into `next` and
branch from `next`; if that is not imminent, branch from `feat/parallel-adopt`
with `origin/next` merged in, and say so in the MR. Starting from
`feat/parallel-adopt` alone means a large conflict on the contract later.

**Risks.**

- A claude.ai connector exposes the tracker under different tool names
  (`mcp__claude_ai_ClickUp__…`, observed in a session today). If the agent only
  lists `mcp__clickup__…`, it finds no tool for those developers. D9 covers
  both prefixes; step 1 confirms it is enough.
- `custom_id` is read in places outside the agent's result (hooks, the mod,
  the clock): the alias in D4 must cover every reader, and the grep test must
  catch the ones left.
- The Linear status types do not name `IN_REVIEW` or `BLOCKED`: the map needs
  named states, which a team may not have. The setup asks; the adapter's
  default is `In Review` and `Blocked`, and a missing state is a setup error,
  not a runtime one.
- The size of the diff (about 80 files): one PR, organised as one commit per
  plan step, with a guide in the description — not split by layer.
