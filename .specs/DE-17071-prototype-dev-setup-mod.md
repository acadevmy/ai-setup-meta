# Spec: Prototype the dev-setup mod — work status, turnless commands, per-phase usage [DE-17071]

> Status: implemented
> Task: https://app.clickup.com/t/869faxn54
> Branch: feat(mods)/DE-17071_prototype-the-dev-setup-mod-work-status
> Created: 2026-10-07
> Approved: 2026-10-07

## Context

Every question about the state of the work costs a model turn today, or has no
answer at all: is a task clock open, which branch / spec / base is this, which
worktrees hold which ports, which of the six commands fits this change, how full
is the context, what did each `sdd` phase cost. The silent failure of DE-16879 —
a merge request opened by hand, the clock left running, nothing anywhere saying
so — is the expensive version of the same blindness. `post-merge-request.sh`
now tells the *model*; nothing tells the *developer* without a turn.

Claude Code mods (a TypeScript hooks module inside a plugin, `"modules"` in
`hooks/hooks.json`) can draw above the prompt, register commands that answer
without a model turn, and observe every model request's usage. This task builds
a prototype of a `dev-setup` mod, ships it inside the plugin, and writes down,
feature by feature, whether it earns a place in the plugin.

Discovery settled the shape (2026-10-07):

- **all four pieces are built** — the clock band and merge-request button, the
  turnless command, the per-phase usage bar, the multi-sdd pane — and the
  proposals not built (the commit-gate box) still get a written verdict;
- **on for everyone**, inside `dist/dev-setup`: no opt-in flag;
- **one command, `/dev-setup <view>`** — a mod command is `/<name>` with
  letters, digits, `_` and `-` only, so `/dev-setup:clock` cannot exist, and
  `/status` and `/context` are built-ins;
- **per-phase usage is built now**; the cross-check against DE-17081's script
  (not on `next` yet) is recorded as pending.

Facts verified while preparing this spec, on the local client 2.1.285 and the
mods documentation of v2.1.290:

- 2.1.285 reads `modules` (`claude plugin validate` lists the module's hooks and
  passes) but keeps mods behind early access: `claude plugin test` answers
  `hooks modules are not turned on in this build yet`, and runs with
  `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`. A client without mods ignores the
  module and keeps the bash hooks.
- Static analysis only accepts `$` passed to a top-level function **of the same
  file**; the one bare import allowed is `claude-code`; relative `.ts` imports
  work (probed).
- A command's `{ text }` is printed in the transcript **and read by Claude**; a
  command that returns `{}` adds nothing to the context.
- `$.session.usage({ breakdown })` returns the `/context` split (memory files
  with their paths, skills, agents, MCP tools); `turn.step` and `turn.complete`
  carry per-request / per-turn token usage, cache included, for subagents too;
  cost exists only as the session total.
- No event concerns workflows; a workflow's agents carry ids no
  `$.agent.list()` names; a background task's completion reaches a mod as a
  `prompt.submit` whose `origin.kind` is `task-notification`.

## Requirements

- REQ-1: `scripts/build-plugin.sh dev-setup` ships the module and its helpers
  under `dist/dev-setup/hooks/` and writes `"modules": ["./register.ts"]` into
  the generated `hooks.json`, with the `hooks` block exactly as today, driven by
  a `mod` list in `templates/dev-setup/manifest.json`.
  `claude plugin validate dist/dev-setup` lists the module's hooks and calls and
  reports no error.
- REQ-2: The mod enforces nothing. No hook returns `deny`, `decision`, `refuse`,
  `drop`, `consumed`, `skip` or a rewritten event; every `tool.call`,
  `prompt.submit` and `turn.step` hook passes its event on unchanged; the module
  never calls `$.prompt.submit`, `$.turn.abort`, `$.tool.call`, `$.config.set`,
  `$.env.set` or `$.fs.write`. Its only writes are `$.store` and `$.prompt.fill`.
- REQ-3: While a task clock is open in the session's repository, the band above
  the prompt shows one line per open task — `<TASK> · in progress · <elapsed>` —
  without anything being invoked. With no open clock it draws nothing. The band
  is refreshed on `session.start`, on `turn.complete`, after a Bash call whose
  command changes a clock (`task-clock.sh … --start` / `--stop`; a `--status`
  only reads one), and every 60 seconds. Other mods' band content
  is kept.
- REQ-4: After a Bash `gh pr create` / `glab mr create` whose output carries a
  merge-request URL, while a clock is open, the band shows a button that
  **fills** the prompt — never sends it — with the closure request: stop the
  named task's clock and move it to `CODE REVIEW` with the URL. Detection
  matches `post-merge-request.sh`: quoted strings are ignored, a URL is
  required. The button goes away once that clock is no longer open.
- REQ-5: `/dev-setup [clock|status|worktrees|context|usage|runs]` is
  registered with `immediate: true`, so it answers while Claude is working and
  never starts a model turn. No argument shows the catalogue; an unknown
  argument shows one line listing the views.
- REQ-6: In an interactive terminal or Desktop session the command opens the
  `dev-setup` pane on the requested view and returns `{}` — nothing enters the
  transcript. Anywhere else (`claude -p`, VS Code, a Routine) it returns the
  same view as plain `{ text }`.
- REQ-7: `clock` reads `task-clock.sh --status --json` (and `--task <id>` for
  each open task), `status` reads `check-prerequisites.sh --json`, `worktrees`
  reads `worktree-info.sh --json`. An empty value is written as `none` /
  `not set`. A script that is missing, exits non-zero or times out yields one
  line naming the script and the tail of its stderr — never a thrown error and
  never a blank view.
- REQ-8: The catalogue lists exactly the skills under
  `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` whose frontmatter says
  `user-invocable: true`, read at run time: the command (`/dev-setup:<name>`),
  what it does (the description before "Use when"), when to use it (the
  "Use when…" sentence), what it takes (`argument-hint`, else `nothing`), and an
  "outward-facing — started only by you" mark when `disable-model-invocation:
  true`. Adding or renaming a public skill changes the list with no change to
  the mod. Each row has a "use" button that fills `/dev-setup:<name> ` without
  sending. The view ends with a pointer to `docs/developer-guide.md`.
- REQ-9: `/dev-setup context` shows the context used — `tokens`, `window`,
  `percent` from `$.session.usage()` — the split by category from
  `breakdown`, labelled as Claude Code's estimate, and the `dev-setup` share:
  the `.claude/rules/dev-setup-*.md` memory files (`core.md` included), the
  `dev-setup:` skills and agents, and the MCP tools of the servers in the
  project's `.mcp.json`. When the client returns no breakdown, the view shows
  the total and says the split is unavailable on this client. The band shows a
  warning line while the context is at 70% or more.
- REQ-10: Every model request — main loop and subagents — is attributed to the
  `sdd` phase in progress, derived from the skill last expanded
  (`skill.prompt`). Per phase, the mod keeps input, output, cache-read and
  cache-write tokens, the number of requests and the cost (the growth of the
  session's `cost.usd` across the request), in `$.store`, per session. While a
  phase is being measured the band shows a compact per-phase line;
  `/dev-setup usage` reports the full table.
- REQ-11: A `Workflow` call named `dev-setup:auto-sdd` adds a run — task id,
  title, run id, start time — and its task notification sets the outcome:
  `ready-for-mr` or `failed` from the run's result, else the notification's own
  status. The `runs` view lists up to five runs with task, state, elapsed time
  and outcome; a `ready-for-mr` run whose merge request the mod saw (REQ-4
  detection) shows its URL; a `failed` or killed run has a button that fills the
  resume request with its `resumeFromRunId`. On the first launch of a session
  the pane opens on `runs` by itself (it waits for a wide enough terminal) and a
  toast names `/dev-setup runs`. The phase a run is in is not shown: no event
  exposes it.
- REQ-12: With mods off — a client without them, `--safe-mode`,
  `disableAllHooks`, `allowManagedModsOnly`, `sec-default` refusing an event —
  the plugin behaves exactly as today: the four bash hooks are unchanged in
  `hooks.json`, and no skill, script or hook depends on the mod.
- REQ-13: A `claude plugin test` suite covers the helpers and the hooks — the
  band, the merge-request button, every view in both modes, the catalogue, the
  usage attribution, the runs — and runs in a new CI job, `mod-tests`, against
  `dist/dev-setup`.
- REQ-14: `AGENTS.md` gains a section that states the boundary — the mod is an
  interface layer; the bash hooks, the `deny` rules and the sandbox enforce —
  and records the written decision: a verdict per proposal of the task (adopt,
  keep experimental, or drop), with what was verified and what is pending
  (DE-17081 cross-check, a run's phase, the `/context` total, the
  task-notification shape on a real run, the minimum client). The CI tables in
  `AGENTS.md` and `docs/workflow.md` list the sixth job;
  `docs/developer-guide.md` documents the band and `/dev-setup`; the
  `AGENTS.md` version is bumped.

## Technical decisions

- **Source under `templates/dev-setup/.claude/mod/`, shipped to
  `dist/dev-setup/hooks/`.** `register.ts` sits next to the generated
  `hooks.json` (the module path is relative to it), `lib/*.ts` beside it, and
  `tests/*.test.ts` ship too: tests inside the plugin directory are the mods
  convention, and CI then runs `claude plugin test dist/dev-setup` on exactly
  what is released. A new manifest key, `mod`, lists the files; the builder
  copies them and adds `modules` only when the list is non-empty, so a domain
  without a mod gets the same `hooks.json` as today. `validate-template`
  learns the key, like every other manifest list.
- **Every `$` call lives in `register.ts`; `lib/` is pure.** Static analysis
  rejects `$` passed to an imported function, so the split is forced, and it is
  the useful one: parsing (script JSON, frontmatter, notifications), detection
  (merge request, phase) and formatting (views, band lines) are plain functions
  unit-tested without the kit; `register.ts` only wires events to them.
- **No `any`, no `$.state`.** `register.ts` types its hooks with
  `import type` from `claude-code`; `lib/` declares its own input types.
  State is module-level (a shipped plugin does not hot-reload) plus `$.store`
  for what must outlive the session — `$.state` would need a `types` entry in
  `plugin.json` for no gain here.
- **One command, one pane, one tab per view.** `/dev-setup` is one row in
  `/help`, listed next to the `dev-setup:*` skills; the pane `dev-setup` holds
  the views as tabs (`plain` buttons with digit hotkeys). The interactive path
  returns `{}`, so a status check costs no context; the plain-text path exists
  because nothing is drawn off the terminal. The mode is decided from
  `session.start`'s `isInteractive` and `surface`.
- **Scripts run as `['bash', <root>/scripts/<name>.sh, …, '--json']`**, cwd the
  session's, timeout 15 s, inside `try`/`catch`: `$.process.run` rejects on a
  timeout or a program that cannot start. The script contract (flat JSON, empty
  means missing) is what the views render; no script changes.
- **The clock's elapsed time is computed in the mod** from `STARTED_AT` (local
  time, the format the script writes) plus `TOTAL_MINUTES` of the closed
  intervals. The script measures on `--stop` only, and `--status` must stay a
  read.
- **Merge-request detection is a port of `post-merge-request.sh`'s two
  patterns** (quoted strings stripped; `/pull/<n>` or `/merge_requests/<n>`
  URL required), observed on `tool.call` for `Bash` after `await next(e)`. The
  hook stays the authority — it is what puts the obligation in front of the
  model; the button is the developer's copy of it.
- **Usage is attributed per request on `turn.step`, not per turn.** One `sdd`
  turn crosses several phases (the sub-skills run inside one turn), so
  `turn.complete` would charge a whole turn to the phase it ended in. The phase
  map: `sdd` → intake, `sdd-discovery` → discovery, `sdd-spec` → spec,
  `sdd-plan` → plan, `sdd-dev` → dev, `verify` / `review` / `simplify` /
  `vcs-ops` → closure, with the `dev-setup:` prefix stripped; any other skill
  leaves the phase as it was. Cost per phase is the growth of the session total
  read after each request — exact in sum, approximate per phase when parallel
  subagents interleave; the view says so.
- **Runs are observed, never driven.** Start: `tool.call` on `Workflow` with
  `name: 'dev-setup:auto-sdd'`, reading `args.taskId` / `args.title` and the
  run id from the result. End: `prompt.submit` with `origin.kind:
  'task-notification'`, matched to a run by its task id, outcome parsed from the
  result's `status`. Both hooks return `next(e)` untouched. A launcher-written
  state file was the alternative; it would put new obligations in the
  `multi-sdd` flow for a prototype's benefit, and is kept as the fallback the
  decision names if notifications turn out not to reach `prompt.submit`.
- **The `dev-setup` share is read, not estimated**, from the breakdown's named
  items (memory-file paths, skill and agent names, MCP server names from the
  project's `.mcp.json`). The command asks for `breakdown: 'summary'` — local,
  no network, fast enough for `immediate`; the band only reads the free
  `tokens` / `percent`. The 70% threshold is a constant.
- **`argument-hint` on the public skills that take arguments** (`quick`, `sdd`,
  `auto-sdd`, `multi-sdd`), mirroring their `**Usage**` line: it is the one
  frontmatter field that says what a skill takes, it feeds the catalogue, and
  Claude Code's typeahead shows it too. The "use" button fills the command and a
  space only — the typeahead then shows the hint; a placeholder filled into the
  prompt and sent by mistake would become a bogus task id.
- **`$.store` layout**: one key per `sdd` run, `usage:<sessionId>:<startedAt>`,
  carrying the project directory so `/dev-setup usage` never shows another
  project's run; an index key pruned to the 20 most recent (the store is 4 MiB
  shared by every session), written once per run; one key per item so concurrent
  sessions never overwrite each other.
- **The decision lives in `AGENTS.md`**, not in a new page: it is the ground
  truth for whoever changes the plugin next, and a sixth docs page is the shape
  the docs table warns against.

## Impact

- **Files to create**:
  - `templates/dev-setup/.claude/mod/register.ts`
  - `templates/dev-setup/.claude/mod/lib/clock.ts`
  - `templates/dev-setup/.claude/mod/lib/merge-request.ts`
  - `templates/dev-setup/.claude/mod/lib/catalogue.ts`
  - `templates/dev-setup/.claude/mod/lib/usage.ts`
  - `templates/dev-setup/.claude/mod/lib/runs.ts`
  - `templates/dev-setup/.claude/mod/lib/context.ts`
  - `templates/dev-setup/.claude/mod/lib/views.ts`
  - `templates/dev-setup/.claude/mod/tests/*.test.ts`
  - their copies under `dist/dev-setup/hooks/` (generated)
- **Files to modify**:
  - `templates/dev-setup/manifest.json` — the `mod` list
  - `scripts/builders/build-claude.sh` — copy the mod, emit `modules`
  - `dist/dev-setup/hooks/hooks.json` (generated)
  - `templates/dev-setup/.claude/skills/{quick,sdd,auto-sdd,multi-sdd}/SKILL.md`
    and their `dist/` copies — `argument-hint`
  - `.github/workflows/ci.yml` — the `mod-tests` job
  - `.claude/agents/validate-template.md` — the `mod` manifest list
  - `AGENTS.md`, `docs/developer-guide.md`, `docs/workflow.md`, `README.md` (the trees)
  - `scripts/build-plugin.sh` (the summary names the module), `scripts/validate-setup-urls.sh`
    (the `mod` list, like every other manifest list)
  - `templates/dev-setup/.claude/hooks/post-merge-request.sh` — a comment naming
    its mirror in the mod; no behaviour change
  - `templates/dev-setup/.claude/skills/{quick,auto-sdd,multi-sdd}/SKILL.md` — a
    few words tightened to keep the 500-word budget the frontmatter line spends
- **Dependencies**: none to install. Claude Code with mods enabled to run
  them (2.1.287+, or 2.1.285 with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`).

## Implementation plan

1. **Packaging** — add the `mod` manifest list and the builder step (copy,
   `modules` in `hooks.json` only when the list is non-empty); a skeleton
   `register.ts`; build; `claude plugin validate dist/dev-setup` lists it, and
   the `hooks` block diff is empty.
2. **Pure helpers with their unit tests** — `clock` (parse, elapsed, lines),
   `merge-request` (the two patterns), `catalogue` (frontmatter, public skills,
   what/when split), `usage` (phase map, accumulation, compact and full
   formats), `runs` (from the `Workflow` call, from a notification), `context`
   (share from a breakdown), `views` (each view as text lines).
3. **The command and the pane** — `session.start`: mode, registration in
   `try`/`catch`, first refresh, the 60 s timer; `command.run`: argument →
   view, pane open + `{}` or `{ text }`; the `ui.render` Pane hook with tabs;
   the script-backed views.
4. **The band** — `ui.render` on `AbovePrompt`: clock lines, kept alongside
   `await next(e)`; refresh triggers (`turn.complete`, Bash calls running
   `task-clock.sh`, the timer).
5. **The merge-request button** — Bash `tool.call` observer, pending closure
   state, the fill-only button, cleared when the clock closes.
6. **Per-phase usage** — `skill.prompt` → phase, `turn.step` → attribution,
   cost delta, `$.store` per session with pruning; band line; `usage` view.
7. **Runs** — `Workflow` observer, `prompt.submit` notification observer, the
   `runs` tab, auto-open + toast, link and resume button.
8. **Context** — the `context` view with the share; the 70% band line.
9. **Hook tests** with `claude-code/testing` — every requirement above that a
   hook carries, each view in both modes, the fill-only buttons, and the
   pass-through of every observed event.
10. **`argument-hint`** on the four public skills that take arguments.
11. **CI and meta tooling** — the `mod-tests` job; `validate-template` reads
    `manifest.mod`.
12. **Docs and decision** — the `AGENTS.md` section (boundary, verdict per
    proposal, how to run the tests), CI tables, `developer-guide.md` section,
    version bump.
13. **Rebuild and run every gate** — `build-plugin.sh`, `claude plugin test`,
    `claude plugin validate`, `test-plugin-scripts.sh`, `validate-plugin.sh
    --fail-on-stale`, shellcheck; a local smoke run of
    `claude -p "/dev-setup clock" --plugin-dir dist/dev-setup` with the
    early-access flag.

## Test strategy

- Test 1 (REQ-1): the build emits `modules: ["./register.ts"]`, the `hooks`
  block is byte-identical to the template's, every manifest-listed mod file is
  in `dist/`; `claude plugin validate` passes and lists the module.
- Test 2 (REQ-2): with stubs answering, an observed `tool.call` (Bash and
  `Workflow`), `prompt.submit` and `turn.step` each come back exactly as the
  stub answered — no field changed, no `deny`; plus a review of validate's
  `calls:` line, which must name no forbidden method.
- Test 3 (REQ-3): `clock` helpers — elapsed from `STARTED_AT` and
  `TOTAL_MINUTES`, one line per open task, nothing for none; band mount with an
  open clock draws the line, with none draws nothing and keeps the next
  handler's content.
- Test 4 (REQ-4): detection — a real `gh pr create` with a URL in the output
  matches; a quoted mention, a `gh pr list`, a create with no URL do not; the
  band button calls `prompt.fill` with the task and the URL and never
  `prompt.submit`; with the clock closed the button is gone.
- Test 5 (REQ-5): the command is registered `immediate`; each view name
  routes to its view; no argument → catalogue; unknown → the views line.
- Test 6 (REQ-6): interactive session → `ui.open` on the right tab and `{}`;
  non-interactive → `{ text }` holding the view.
- Test 7 (REQ-7): stubbed script JSON renders each view; empty values read
  `none` / `not set`; a non-zero exit and a rejected `process.run` each yield
  the one-line failure naming the script.
- Test 8 (REQ-8): frontmatter parsing of fixtures shaped like the public
  `SKILL.md` and one `user-invocable: false` (the test kit has no file system); the catalogue holds exactly the public ones, in
  stable order, with what / when / input / outward mark; a skill added to the
  stubbed listing appears; the "use" button fills `/dev-setup:<name> `.
- Test 9 (REQ-9): share computed from a breakdown fixture (rules, skills,
  agents, MCP tools by server); a usage result without `breakdown` gives the
  total and the "unavailable" line; percent ≥ 70 puts the warning in the band.
- Test 10 (REQ-10): phase map including the prefixed names; a sequence of
  `skill.prompt` + `turn.step` events attributes tokens and cost deltas to the
  right phases; a non-`sdd` skill leaves the phase unchanged; the store key is
  per session and the index is pruned at 20.
- Test 11 (REQ-11): a `Workflow` call adds a run; a `ready-for-mr` and a
  `failed` notification set the outcome; an unrelated notification changes
  nothing; five runs listed; the resume button fills the run id; first launch
  opens the pane and toasts.
- Test 12 (REQ-12): `test-plugin-scripts.sh` stays green on the generated
  plugin; the `hooks` block is unchanged (Test 1); no skill, script or bash
  hook references the mod (grep).
- Test 13 (REQ-13): the `mod-tests` job runs the suite in CI and fails on a
  failing test.
- Test 14 (REQ-14): `validate-plugin.sh --fail-on-stale` resolves every path
  and command the new docs cite; the verdict table covers every proposal of the
  task.

## Notes

- **What only a real session can confirm**, on a client with mods on: the band
  visible above the prompt, `immediate` answering mid-turn, the shape of a
  workflow's task notification at `prompt.submit`, the phase detection on a full
  `sdd`, the context total against `/context` at the same moment. The local
  client is 2.1.285 (early access, flag needed); each item is checked in the
  smoke run where the flag allows it, and otherwise written as pending in the
  `AGENTS.md` verdict — never claimed.
- **DE-17081 cross-check pending.** The acceptance criterion "per-phase numbers
  match DE-17081's script on the same transcript" waits for that script; the
  verdict says so.
- **`breakdown` vs `tokens`.** The breakdown is estimated against the
  compaction window, so its total need not equal `tokens`; the view shows
  `tokens` as the total and labels the split. If `/context`'s header turns out
  to equal the breakdown's total, the command switches to it.
- **Risks.** CI installs the latest CLI, and mods events and methods change
  between releases: `plugin validate --strict` and `mod-tests` will break on an
  incompatible release — the right failure, but a new kind of churn.
  `sec-default` on Team/Enterprise restricts some events to user-installed mods.
  A command named `dev-setup` next to `dev-setup:*` skills in the typeahead is
  new territory; it is checked in the smoke run.
- **Pre-existing, out of scope.** On 2.1.285, `claude plugin validate --strict
  dist/dev-setup` fails on four unquoted `${CLAUDE_PLUGIN_ROOT}` warnings in
  today's `hooks.json`, while CI on `next` is green with the latest CLI: the two
  clients disagree. And `sdd-start.sh` resolved `origin/main` as the default
  fork point with `HEAD` at `next` = `origin/next`. Both deserve tickets of
  their own.
- **Not built, verdict only:** the commit-gate box (a denied commit's failing
  check and output tail, which a `tool.call` observer on Bash could read from
  the hook's deny reason).
