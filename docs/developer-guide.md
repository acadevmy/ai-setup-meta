# Developer guide — working with the dev-setup plugin

For the developer of a project the plugin configures. If you have not run
`/dev-setup:setup` yet, start at [onboarding.md](./onboarding.md); if the
project was configured by an older version, read
[migration-v2-to-v3.md](./migration-v2-to-v3.md) first.

The one idea worth having before the details: **the rules are mechanisms, not
paragraphs.** A rule about `.env` is a sandbox deny, a rule about test coverage
is a hook that reads the test runner's output, a rule about React is a file the
harness injects when you open a `.tsx`. Nothing here asks you to remember a
document. [training.md](./training.md) is the long version of that sentence.

## Index

- [1. The commands](#1-the-commands)
- [2. A task, end to end](#2-a-task-end-to-end)
- [3. The rules, and when each one loads](#3-the-rules-and-when-each-one-loads)
- [4. The sandbox and the ask rules](#4-the-sandbox-and-the-ask-rules)
- [5. The quality gate on the commit](#5-the-quality-gate-on-the-commit)
- [6. Several tasks at once: worktrees](#6-several-tasks-at-once-worktrees)
- [7. Extending it](#7-extending-it)
- [8. Upgrading](#8-upgrading)
- [9. Troubleshooting](#9-troubleshooting)

---

## 1. The commands

```
/dev-setup:setup      ← one-off, per project
       │
       ├── /dev-setup:quick     ← a fix or chore: branch, change, commit, MR
       │
       ▼
/dev-setup:sdd        ← the full flow, with one approval
       │                (/dev-setup:auto-sdd for the same flow unsupervised,
       │                 /dev-setup:multi-sdd for up to five of those at once)
       ▼
/dev-setup:review     ← code review against the project rules
       │
       ▼
/dev-setup:beowulf    ← the branch distilled for whoever reviews it
```

| Command | Use it when | Example |
|---|---|---|
| `/dev-setup:setup` | Configuring a project for the first time, or pulling in a new plugin version | `/dev-setup:setup` |
| `/dev-setup:quick` | At most three files, and no new component, dependency or public interface | `/dev-setup:quick DE-123`<br>`/dev-setup:quick fix the 500 on an empty cart` |
| `/dev-setup:sdd` | Anything above that bar — the spec is what a reviewer reads the diff against | `/dev-setup:sdd DE-124`<br>`/dev-setup:sdd DE-124 --worktree` |
| `/dev-setup:auto-sdd` | A well-defined task you do not want to sit through | `/dev-setup:auto-sdd DE-125` |
| `/dev-setup:multi-sdd` | Several independent tasks, unsupervised, from one chat | `/dev-setup:multi-sdd DE-1 DE-2 DE-3`<br>`/dev-setup:multi-sdd --from-sprint 3` |
| `/dev-setup:review` | A branch is ready and you want it read before the merge request | `/dev-setup:review` |
| `/dev-setup:beowulf` | Someone who did not follow the work has to understand it: what changed, the risky points, the decisions, what to try by hand | `/dev-setup:beowulf`<br>`/dev-setup:beowulf --comment` |

Everything else the flows use — discovery, spec, plan, development, verify, the
board conventions, the git conventions — is a skill the orchestrator invokes by
name. They are not commands and they do not show up in `/help`: one flow, one
entry point.

**When one of them runs on its own.** Claude can still pick one up from a plain
request — "write the spec for this", "verify the branch". Run that way, each one
ends by offering the next step of the chain (discovery → spec → approval →
development → verify → review → distill → merge request) and, on a yes, carries on in the
same turn. With a task id, development ends on the `/dev-setup:sdd <id>` command
to type, which resumes at closure. Inside a flow nothing changes: the flow decides what follows.

**Picking between `quick` and `sdd`.** The bar is three files and no new
component, dependency or public interface. Claude may say a task looks
misrouted; the routing is yours, and the command you type is the decision.

**Which one does `review` belong to?** It runs inside `sdd` already, before the
commit. Invoked on its own it reviews the current branch, updates `REGISTRY.md`
in your working tree and commits nothing.

**`validate` is not one of these.** `/project:validate` runs in the plugin's own
repository, not in yours — see [workflow.md](./workflow.md).

### Where you are, without a turn: the band and `/dev-setup`

On a Claude Code that loads mods (2.1.287 and later), the plugin also shows the
state of the work without spending a model turn:

- **above the prompt** — one row per thing to know, each with a coloured mark:
  an open task clock (`● DE-123  in progress  42m`, green); after a `gh pr
  create` / `glab mr create` that created a merge request, its link and a
  `close DE-123` button that fills — never sends — the prompt that stops the
  clock and moves the task to `CODE REVIEW`; while an `sdd` runs, its tokens per
  phase with the phase in progress at full strength, and the cost so far; past
  70% of context, a yellow warning before a long phase compacts it;
- **`/dev-setup`** — a pane with one tab per view (`1`–`6` switch, `r` reloads,
  `Esc` closes). With no argument, the commands with when to use each and
  what each takes, and a `use` button that puts one in the prompt. `/dev-setup
  clock` (one card per open clock — total, current interval, earlier ones, the
  branch's own task marked — and the clocks stopped in the last five minutes),
  `status` (what this session changed: its commits, the files it modified and
  has not committed, the files it committed — nothing the branch carried before
  the session began), `context` (how full, as a meter, and how much of it the plugin
  brings), `usage` (the `sdd` in progress, or the last one: per phase the time, the part of it Claude was working and the part it waited for you, the tokens and their share, the cache hit and the cost; then where the tokens went — main thread or subagents, each model, each kind of token) and
  `runs` (this session's `multi-sdd` runs). Its footer names where the figures
  come from and when they were read. It answers at once, even while Claude is
  working, and in the terminal it adds nothing to the conversation; in
  `claude -p` or VS Code it prints the same rows as text.

None of it is a rule. On an older client, or with mods turned off, the plugin
works exactly the same — without the view.

Two bash hooks carry the rest, on every client. `notify.sh` speaks on a
permission prompt only, and only while a task of this plugin is in play here —
a work clock open, or stopped in the last five minutes: it sends one desktop
notification titled `dev-setup · DE-123` (every task in play when the branch
names none of them), so the merge request or the `BLOCKED` move an autonomous
run waits on reaches you by name. `session-title.sh` names the session
`DE-123 add-user-auth` — at startup or resume on a task branch, and on the
`/dev-setup:sdd`, `quick` or `auto-sdd` prompt that launches one task — so
`claude --resume` lists sessions by task; a title you set yourself is never
replaced. Both are silent otherwise, and let everything through when `jq` or
the repository is missing. During an `sdd` the phases are a task list, and
every closing report ends on a `Next:` line with the command to run next.
[onboarding.md](./onboarding.md#know-where-a-flow-is) has the two user
settings that go with them.

---

## 2. A task, end to end

```
/dev-setup:sdd DE-123
       │
       ├─ reads the task, asks which branch to fork from — the default is
       │  resolved from the repository, never hard-coded — and where this run
       │  should stop (the merge request, by default), then creates
       │  feat(<context>)/DE-123_…, moves the task to IN PROGRESS and starts the clock
       │
       ├─ discovery — one call, up to four questions on what the task leaves
       │  open; "Requirements clear: go to spec" ends it in one click
       │
       ├─ the technical spec, written to .specs/
       │        ↓
       │   ★ you approve it — the flow's approval checkpoint
       │
       ├─ development against the approved plan, one step at a time
       │
       ├─ simplify → the diff packaged once → verify ∥ review + REGISTRY
       │  (verify against the spec and review against the rules run in
       │  parallel, on the same package; a violation counts only once a
       │  second agent has confirmed it)
       │
       ├─ one commit: code + spec + REGISTRY, with the gate running here
       │
       ├─ push, then the merge request  ← your confirmation is required
       │
       └─ the task moves to review, with the link and the time it took
          posted on it
```

What is worth knowing about that shape:

**A backlog task is your call.** A task read in `BACKLOG` was never planned
into a sprint, so the flow stops and asks before anything else happens — no
branch, no board write. Confirming moves it to `IN PROGRESS` like any sprint
task; declining leaves it exactly where it was. No command moves a task out of
the backlog automatically.

**One approval, not five.** The spec is the checkpoint. Development does not
stop between plan steps — the plan was approved whole, and a per-step
confirmation is the same approval wearing a different hat. A step that cannot be
carried out as written does stop, and says why.

**One commit, not four.** The gates run *before* the commit, so the code, the
spec and the REGISTRY entries land together. Committing more often while you
work is fine; nothing requires it.

**Three stops before the code.** Launch (fork point and stop point, one
call), discovery (one call, at most a second, five questions in all) and the
spec approval. Discovery drafts what the task already says and asks only about
the gaps — a well-written task reaches the spec in one click.

**You choose where it stops.** Together with the fork point, the flow asks how
far this run goes — the merge request is the default:

| Stop point | Ends with |
|---|---|
| Spec only | discovery, the spec and its approval — the spec uncommitted, no code |
| Development | the code implemented, tests and lint passing, nothing staged |
| Review | simplify, verify, review + REGISTRY run, everything staged, nothing committed |
| Commit | the one commit, through the commit gate, not pushed |
| Push | the branch on the remote, no merge request |
| Merge request | the whole flow: the merge request, the task in review, the time posted |

Short of the merge request, the task stays `IN PROGRESS` with its clock
running. Run `/dev-setup:sdd DE-123` again to carry on: it reuses the stop
point you chose — saved beside the clock, it survives `/clear` — and starts
from what is on disk — the spec, the uncommitted code, or the commit — without
redoing what is done. `/dev-setup:sdd DE-123 --stop push` changes it.

**The clock runs from IN PROGRESS to the merge request.** The move that starts
the work stamps `task-clock.sh --start`; the move that ends it reads the stamp
back and posts one line on the task — `Time in progress: 2h 15m (14:03 →
16:18)`. It is wall-clock time between two board writes, not an estimate of
effort, and it is never invented: if nothing stamped the start — a flow resumed
in a fresh clone, say — the task moves with no time on it and the session says
so. The stamp lives in the repository's git directory, so it is shared with
every worktree and never lands in a commit. A task picked up twice keeps both
sittings and reports the total.

**The merge request closes the task, whoever opened it.** Those two closing
calls used to live only in the flow's last step, which holds right up to the
moment the merge request is opened by something else — a push that failed and
was retried the next day, a session cleared in between, `vcs-ops` invoked on its
own. The task then stayed `IN PROGRESS` with its clock running, and nothing
anywhere said so. A `PostToolUse` hook now fires on the `gh pr create` /
`glab mr create` that created it: when a task's clock is still open in the
repository it names that task and asks for both calls. It reads the clock and
never stops it — the measurement belongs to whoever posts it. With no task in
progress here, it says nothing at all.

**Branches are `<type>(<context>)/<TASK-ID>_<description>`** —
`feat(auth)/DE-123_add-refresh-token`. The context is the one area the work
touches and is left out when there is none; the description is always English,
whatever language the task is written in. A branch cut under the older
`feat/DE-123-…` form still resolves its task.

**The description is the repository's template, filled in — and short.** The
setup writes one — `.github/PULL_REQUEST_TEMPLATE.md` on GitHub,
`.gitlab/merge_request_templates/Default.md` on GitLab — and every flow fills
that file instead of inventing a body: neither `gh` nor `glab` applies a
template to a description passed on the command line. A few sentences and the
test steps, not a tour of the diff. A template already in the repository is
never overwritten — the flows fill the team's own.

**Language, title and labels are project metadata.** The setup asks whether
merge requests are written in Italian or English and stores the answer in
`.claude/merge-request.json`, with the labels the team uses: the catalogue
(created on the forge if missing) and which of them a merge request gets by
branch type, by task priority, when it breaks something, and on every open.
Edit the file to change any of it — the flows read it through
`${CLAUDE_PLUGIN_ROOT}/scripts/mr-meta.sh` every time. The title is
`<Type>: <what was done> [<TASK-ID>]` in the chosen language —
`Feat: Aggiunta rotazione del refresh token [DE-123]`; the commits keep their
Conventional Commits form, in English. The section that matters is the test
one: the commands to run and the route to open, written for a reviewer who has
not read the branch.

**The methodology is not a question.** Backend logic is test-first, UI is
scenario-first, and `.claude/rules/dev-setup-tests.md` says so — it loads by
itself when you open a test file. Both cycles are written out in the plugin's
`sdd-dev` reference, read by whoever is writing the code.

### The autonomous variant

`/dev-setup:auto-sdd DE-123` runs the same ground as a workflow script: it
writes the spec, has three reviewers improve it — one looking for a simpler
design, one for the scope, one for testability, each grounding its proposal in
the project's ADRs, rules and existing code — integrates their proposals at most
twice, develops in an isolated worktree so your checkout never moves, and runs
the project's own lint, typecheck and test commands.

When the task contradicts the project, one precedence settles it: the project's
architectural choices (ADRs, `.claude/rules/`, `REGISTRY.md`, what the libraries
actually do) first, then what the task promises its users, then how the task
says to build it. The review improves the spec; it never stops the run.

It comes back with one of two outcomes:

| Outcome | What it means | What you do |
|---|---|---|
| `ready-for-mr` | Green, committed on its branch | Confirm the push and the merge request, and read its "to confirm" section (§9) |
| `failed` | The spec, the dev step or a quality command failed | Read the real output; the branch and worktree are left in place |

In a cloud session — a scheduled routine included — the disk goes with the
session, so a `failed` run — or one that broke with no outcome — does not
leave its work there: whatever the worktree holds is committed and the branch
is pushed as it is, with no merge request. When the run never made a branch,
the spec it wrote gets one. That commit and that push are the one way past the
gates — the commands are red, which is why the run failed — so
`save-failed-run.sh` makes them, only in a cloud session, only on the task's
own branch and never forced, with a message that says the hooks were skipped
and why the run failed. The task goes to `BLOCKED` with the same report: why
it failed, what is missing, the tail of the failing output, where the branch
is and how to resume (`/dev-setup:sdd <TASK-ID>` on that branch).

It asks you one thing before it starts — which branch the run forks from, the
ref resolved from the repository offered as the default, the same question
`/dev-setup:sdd` asks — and it asks it before the task moves on the board, so
walking away costs nothing.

It pushes nothing, opens nothing and writes nothing to the board on its own —
those happen in your session, where you can see them.

### Several at once

`/dev-setup:multi-sdd DE-1 DE-2 DE-3` fans that workflow out, one run per task,
each in its own worktree. The human parts come first: a small/large triage, the
questions no agent can answer for you, a warning if two tasks declare the same
file, and the fork point every run inherits — asked once for the set, the ref
resolved from the repository as the default, exactly as `/dev-setup:sdd` asks it
for one branch. Then the runs go, and the outcomes arrive in that chat as they
land.

The cap is **five**, and it is a script that enforces it — the sixth task exits
with the reason. Five is where the review queue becomes the bottleneck: a
fan-out costs `n` times a single run, and it ends with `n` merge requests for
one person to read.

### Headless runs, for a job runner

Two more commands exist for a machine, not for you: a job runner starts them
inside `claude -p` on a disposable checkout, one task per machine, and pushes,
opens the merge request and closes the task itself from the files they leave.
They are left out of the project's `AGENTS.md`, so a session in your project
never pays to describe them.

- **`/dev-setup:auto-dev-select --args <file>`** runs on the host, after the
  runner cloned every repository of the project and before any devcontainer
  exists. A `repo: owner/repo` line in the task, or a single clone, settles
  which repository the task belongs to with no model; otherwise Sonnet reads the
  task and each clone's README, `AGENTS.md` and manifests and chooses, or the
  task goes to `BLOCKED` with the reason. The base branch comes, in order, from
  a `base: <branch>` line, the task's own words, `base_branch` in the clone's
  `.claude/auto-dev.json`, the remote's HEAD, then `main`/`master`/`develop`.
  It writes `selection.json`, whose `hasDevcontainer` is true only for a
  configuration the runner's `devcontainer up`, with no `--config`, reads —
  `.devcontainer/devcontainer.json` or `.devcontainer.json`. A clone with only
  `.devcontainer/<name>/devcontainer.json` runs on the host, and
  `devcontainerNote` says what was ignored; the task is not blocked.
- **`/dev-setup:auto-dev --args <file>`** runs inside the chosen repository's
  devcontainer. It is `auto-sdd` with the cost taken out: the spec hands on a
  context pack — the files, rules and ADRs it rests on — so nothing explores
  the repository twice; one reviewer covers the three focuses and is skipped on
  a small task (three REQ and three steps or fewer); development happens on the
  task branch in the checkout, with no worktree, and ends in one commit, so the
  commit gate runs the checks once. Opus writes, reviews and develops; Haiku
  runs the quality commands through `auto-dev-checks.sh` and waits for them,
  so a suite longer than the ten minutes a Bash call gets is waited for, not
  reported red. It writes `result.json` and `pr-body.md`. A
  command the machine cannot start (its program is not installed) is not run:
  the merge request lists it as not verified, and the commit goes through
  `auto-dev-commit.sh`, which runs the others, because the commit gate would
  run that command and refuse. The result is checked against git: a branch
  with no commit over its base is a `failed` run at stage `dev`, never
  `ready-for-mr`, and a failed run's uncommitted work is saved as
  `changes.patch`.

The board is reached with `auto-dev-clickup.sh` over the ClickUp REST API and a
personal token in `CLICKUP_API_TOKEN` (with `CLICKUP_TEAM_ID` for custom ids),
because a disposable machine has no OAuth login for the MCP. Everything around
the run that does not need judgement is a script — `auto-dev-args.sh`,
`auto-dev-select.sh`, `auto-dev-commit.sh`, `auto-dev-checks.sh`,
`auto-dev-report.sh` — and each
one's `--help` holds its contract. The runner starts `claude -p` with
`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0`: without it, `claude -p` stops the
workflow ten minutes after the launcher's last turn, so `auto-dev-args.sh`
refuses the run at intake. With the Bash sandbox on, the runner also passes
`--add-dir <outputDir>`, because a sandboxed command writes only in the
checkout and the directories added. `auto-sdd`, `multi-sdd` and the interactive flow are unchanged.

### A devcontainer for the runner

The runner builds each repository's devcontainer before `auto-dev` and runs the
quality commands inside it; without one, `auto-dev` runs on the bare machine,
and every command whose toolchain is not there (Flutter, PHP, …) ends up in
the merge request as not verified. **`/dev-setup:devcontainer`** writes it and
proves it. It is optional and not part of `/dev-setup:setup`: run it, in each
of the project's repositories, when that project's unattended runs move to
GCP — on a project set up long ago too.

It needs `.claude/quality-commands.json` (the setup's step 3b), because the
proof is running those commands. It reads what the repository already pins —
`.tool-versions`, `.nvmrc`, `composer.json` and its `ext-*`, `pubspec.yaml`,
`.fvmrc`, the CI's images and services, a development Dockerfile or compose
file, `.env.example` (never `.env`) — through `devcontainer-facts.sh`, shows
you the files with the origin of every version, and writes them under
`.devcontainer/` on your yes. A monorepo gets one `.devcontainer/` at the root
with every toolchain and its services in docker compose: the runner runs
`devcontainer up` at the root with no `--config`, so a per-package
configuration is never read.

The files follow the runner's contract: a non-root user with UID 1000 that
owns every SDK in the image, `bash`, `git` and `curl` inside, the CLI's default
workspace path, no bind of a host path (`~/.ssh`, `~/.gitconfig` — the runner
rewrites SSH git URLs to HTTPS, so no key is needed), no Docker socket,
`privileged`, host network or docker-in-docker, and no secret in the
environment. The runner holds the git credentials only during `up`, so
`postCreateCommand` leaves the quality commands runnable at once: dependencies
installed, uncommitted code generated, the test environment prepared from
`.env.example` when there is none.

Then `devcontainer-check.sh` builds it fresh, the way the runner does, checks
those clauses, and runs the declared preflight and commands with
`devcontainer exec`. A red test is your project's state and is reported as
such; a command that does not start is the devcontainer's to fix. The check
needs Docker and the devcontainer CLI (`npm install -g @devcontainers/cli`)
and runs outside the Bash sandbox, which asks you first; without them the
files are written and reported as not verified. A private dependency on an SSH
URL needs `--ssh-agent`: your SSH agent is forwarded into the check's container,
as VS Code does, since the runner's own credentials exist only on the runner. It builds under a label and a
compose project of its own, and removes what it built, so your own
devcontainer is never touched — but `postCreateCommand` runs on your checkout,
as in any devcontainer: what it installs or generates lands in your working
tree.

**Testcontainers is not supported on GCP.** Tests that start their own
containers need the Docker socket the runner refuses, so when a manifest
declares Testcontainers the command writes nothing for the runner: it names
the files and dependencies and gives you the exclusion to make — in n8n, data
table `autodev_projects`, the project's row, column `gcp_excluded` =
`testcontainers: <owner/repo>`. A devcontainer for VS Code alone is offered,
never assumed.

An existing configuration is never overwritten unasked: you choose between
verifying it, a rewrite shown as a diff, or leaving it.
`/dev-setup:devcontainer --check` only verifies. Commit the result and merge it
into the branch the runner forks from.

### The quality commands your project declares

Which command lints the project, which type-checks it and which runs its tests
is the project's to say, once, in `.claude/quality-commands.json` — not a guess
the plugin remakes on every run. Step 3b of the setup writes it: it proposes
what the project already declares somewhere, asks you to confirm or correct the
three in one question, and runs each one before it finishes.

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

| Key | What it decides |
|---|---|
| `lint`, `typecheck`, `test` | the command, or `null` when the project has none — with the reason under `absent`. A `null` is a decision: the flows skip that command and run the others |
| `preflight` | optional: a readiness check the autonomous launchers run before anything else — a script that checks the toolchain, say |
| `hook_manager` | optional: your hook tool when detection does not know it (`pre-commit`, `captainhook`, `grumphp`); the commit gate defers to it (§5) |

**Every command runs from the repository root.** One that belongs to a
sub-directory says so: `make -C api lint`, `cd api && composer test`.

**Where the candidates come from**, in order of authority: your CI (the `run:`
steps of `.github/workflows/`, the `script:` items of `.gitlab-ci.yml`), your
task runner (`Makefile`, `justfile`, `Taskfile.yml`), your package scripts
(`package.json`, `composer.json`, `pyproject.toml`), the shell blocks of
`README.md` and `AGENTS.md`, and only last the per-language heuristics.
`${CLAUDE_PLUGIN_ROOT}/scripts/quality-candidates.sh --json` shows the list. So a
stack the plugin has never seen still gets its own gates, with no rule written
for it.

**Every flow reads the file the same way**, through `detect-stack.sh`, whose
`COMMANDS_SOURCE` says where the commands came from: `declared` (the file),
`detected` (no file, the heuristics found something) or `none`. A malformed file
is an error, never a silent fallback to the guess.

**The autonomous launchers refuse without it.** Before the board, the fork point
or the workflow, `/dev-setup:auto-sdd` and `/dev-setup:multi-sdd` run
`${CLAUDE_PLUGIN_ROOT}/scripts/quality-preflight.sh --require-declared --allow-unavailable --json`.
It refuses in seconds — no declaration, a rejected one, every command declared
absent — and the run never starts:
a SPRINT task goes to `BLOCKED` with the reason, a BACKLOG task is left as it
was, and `multi-sdd` touches no task. The fix is the project's: run
`/dev-setup:setup` and let step 3b write or repair the declaration.

**An environment that cannot run them does not stop the run.** A command whose
program is not installed, or a red `preflight` — a cloud routine without PHP or
MySQL, say — is a fact about the machine, not about the project. The launcher
says which commands are affected and starts anyway; the dev agent writes the
tests without running those commands, Verify skips them, and the merge request
opens with a **Not verified** section naming each one and why. Whoever merges
runs them, or waits for the CI that does.
`/dev-setup:sdd` and `/dev-setup:quick` do not stop; with `COMMANDS_SOURCE`
`none` they say at the start that nothing will lint or test the work.

### The file an unattended run reads

Step 7d of the setup offers to write `.claude/auto-dev.json` — the project facts
a run nobody is watching cannot ask anyone for:

```json
{
  "clickup_list_ids": ["901214692298"],
  "tag": "claudio",
  "status": { "ready": "sprint", "in_progress": "in progress", "in_review": "in review", "blocked": "blocked" },
  "base_branch": null,
  "figma": { "file_key": "wMJHvCjPaCfK6765aKTfgn", "url": "https://www.figma.com/design/wMJHvCjPaCfK6765aKTfgn/V-Program" },
  "dry_run": false
}
```

| Field | What it decides |
|---|---|
| `clickup_list_ids` | the lists a run pulls work from |
| `tag` | the tag that marks a task as the agent's |
| `status` | this board's own status names, for the moves the flow makes |
| `base_branch` | `null` means "resolve it per run" — the fork point comes from the repository, never from a name frozen on setup day |
| `figma` | the design file, when the project has one; `null` otherwise |
| `dry_run` | `true` runs everything up to the push and stops before the push, the merge request and the board write |

It holds ids and names, no credential, and it is tracked — a runner that clones
the repository is configured by the clone. The plugin's own commands do not read
it: `/dev-setup:sdd`, `/dev-setup:quick`, `/dev-setup:auto-sdd` and
`/dev-setup:multi-sdd` resolve the same facts from your session and from the
repo. Decline it and nothing else changes; a later `/dev-setup:setup` offers it
again.

---

## 3. The rules, and when each one loads

The project's governance is not one document you read at the start of a session.
It is the files under `.claude/rules/`, each declaring in its frontmatter the
globs it applies to. The harness injects a rule when the model touches a
matching file: deterministic, free on the sessions that never touch those files,
and it survives compaction.

| File | Loads |
|---|---|
| `dev-setup-core.md` | always — the only one with no path filter |
| `dev-setup-code-style.md` | on any source file, whatever the language |
| `dev-setup-typescript.md` | on a TypeScript file |
| `dev-setup-react.md` | on a React component |
| `dev-setup-nestjs.md` | on the NestJS files that feed the OpenAPI document |
| `dev-setup-vue.md` | on a single-file component |
| `dev-setup-flutter.md`, `dev-setup-dart-analysis.md` | on Dart, and on the analyzer config |
| `dev-setup-terraform.md` | on HCL |
| `dev-setup-tests.md` | on a test file |
| `dev-setup-backend-services.md` | on the business-logic layer |

Only the rules your stack needs are generated: a Flutter project has no React
rule, a Next project has no Terraform one.

`core.md` is the only unconditional file, and the line that keeps it that way is
consequence, not topic: a rule whose absence produces *worse code* can wait for
the file it applies to, a rule whose absence produces an *unsafe or irreversible
action* cannot. So secrets, untrusted content, supply chain and the gates load
always; design, error handling and naming arrive with the file.

**A rule a machine can check is not in these files at all.** Function length,
naming, `any`, coverage floors and layer imports are ESLint and the test runner.
"One review required" and "no direct push" are branch protection, which the
setup offers to configure. Prose is the place of last resort.

---

## 4. The sandbox and the ask rules

`.claude/settings.json` turns on OS-level isolation for every Bash command
Claude runs — Seatbelt on macOS, bubblewrap on Linux and WSL2 — plus a
permission layer on top. The point of the section below is that a refusal is a
configured decision, not a bug.

### What is denied outright

| Denied | Why |
|---|---|
| Writing `.env`, `.env.local`, `.env.production`, … | The file is yours: reads are open so a task can use the values it needs, but the agent never edits it. Both as a permission rule and in the sandbox, so a shell command cannot go around it |
| Reading `~/.ssh`, `~/.aws`, `~/.kube` | Same reason, one level up |
| `GH_TOKEN`, `GITHUB_TOKEN`, `GITLAB_TOKEN`, `NPM_TOKEN`, `AWS_*`, … | Unset inside sandboxed commands, so a token cannot end up in a URL, in `ps` or in a log |
| `git push --force` / `-f`, in every spelling | Rewriting a shared branch |
| `git push` to `main`, `master`, `next`, `develop` | The reference branches take merge requests |
| `git commit --no-verify` / `-n` | The point of a gate is that it is not optional |
| `claude --dangerously-skip-permissions`, `--permission-mode bypassPermissions` | Those flags remove the checkpoints this file exists to place |
| `npm publish`, `pnpm publish`, `yarn publish` | Publishing is a release decision |
| Editing lock files and anything under `.git/` | Both are generated |
| Network to anything outside the allowlist | Registries and your forge are pre-allowed; the first time something else is needed you are asked, and answering "don't ask again" records it |

### What stops and asks

These are not blocked — they wait for you:

- `gh pr create` / `glab mr create` — the merge request. This is the checkpoint
  the flow used to spend as a summary in chat: you see the real command instead.
- `gh api` / `glab api` with `POST`, `PUT`, `PATCH`, `DELETE` — anything that
  writes to the forge.
- Every ClickUp write: create, update, delete, move, merge, add, remove.

The pattern is the same throughout: **reads are free, outward-facing writes ask.**

### If a deny is in your way

Reads of `.env` are open — a task that calls a real API needs the values, and
the rule that remains is behavioural: a value never lands in a tracked file, a
command line or a tracker comment. What stays denied is writing the `.env`
family and the lock files. If **the project's own test or dev command writes a
denied file**, the sandbox breaks it for every command, not just the ones
Claude writes. The fix is to remove that filename from
`sandbox.filesystem.denyWrite` in `.claude/settings.json` — a deny cannot be
re-opened from `.claude/settings.local.json`, which can only add. The token
variables stay unset either way.

### SSH remotes

A sandboxed command reaches the network only through the sandbox's HTTP(S)
proxy: no raw TCP, no DNS. So with `origin` on `git@host:…`, a `git push` inside
the sandbox cannot even resolve the hostname. The setup asks which way you want
it — switch the remote to HTTPS (`gh auth setup-git`, or the `glab` credential
helper, so no token goes in the URL), or keep SSH. Either way
`sandbox.excludedCommands` carries `git push origin *` and `git push -u origin *`:
the push runs outside the sandbox, towards `origin` only — its URL lives in
`.git/config`, which the sandbox protects, and a push to any other URL stays
sandboxed. `git fetch` on SSH still asks. The deny rules hold either way: they
are permission rules, not sandbox boundaries, and they cover `git push -u origin
main` too.

### `gh` and `glab` run outside the sandbox

`sandbox.excludedCommands` lists `gh *` and `glab *`. On macOS a Go binary verifies
TLS certificates through a system service the sandbox does not let it reach, so
inside the sandbox every call fails with `x509: OSStatus -26276`. Excluding them
removes only the OS-level confinement: the deny rules and the `ask` checkpoints
on `gh pr create` / `glab mr create` and on writing `gh api` / `glab api` calls
still apply, and they see `GH_TOKEN` / `GITLAB_TOKEN`, which is the point — they
are the tools meant to read the token from the environment. A project set up before the entry existed gets it
on the setup's UPDATE — and so does one set up with 3.3.0, whose bare `gh` and
`glab` entries matched only the command with no arguments.

An entry takes a call out of the sandbox only when **every** command in it
matches, and a redirect to a file, a `cd` or a `$(...)` keeps it in. So
`gh pr view 12 --json body | head` stays sandboxed and fails like before: run
`gh` on its own and filter with its `--jq` / `--template` flags instead.

---

## 5. The quality gate on the commit

`gate-commit.sh` is a `PreToolUse` hook on `Bash`, and it picks its mode from
what the project already owns, so the checks run once and only once.

It spawns only on a git commit call: its handler carries the rule
`Bash(*git *commit*)`, the hook's own definition of a commit in permission-rule
syntax, so a `git status` never starts it — and it keeps its own check inside,
for a client that ignores the rule.

**Your project has husky, lefthook, simple-git-hooks or a `core.hooksPath`** —
or declares another hook tool as `hook_manager` in
`.claude/quality-commands.json` (pre-commit, captainhook, grumphp: anything
detection does not recognise). Then your own tooling runs the per-commit checks and the hook only refuses the
ways around it: `HUSKY=0`, `LEFTHOOK=0`, a `-c core.hooksPath=…` override, a
`GIT_CONFIG_*` injection. (`--no-verify` and `-n` are separately denied.) A
commit *message* that happens to mention `HUSKY=0` is not an attempt to set it —
the scan reads the command with quoted strings removed.

**Your project has no hook manager.** Then the hook is the gate: it runs the
lint, typecheck and test commands your project declares (or, with no
declaration, the ones detected) and denies the
commit with the tail of the real output as the reason. Not a summary of the
failure — the failure.

The full test suite is deliberately not the per-commit gate. That belongs at the
merge-request boundary and in CI, which stays the final word.

The hook is **fail-open**: with no `jq`, or if stack detection cannot run, it
warns on stderr and lets the commit through. It is a quality gate, not a
security boundary — the security boundary is the deny rules and the sandbox, and
blocking every commit on a broken toolchain would be worse than reporting it.

The checks get **twenty minutes**. When they run longer, the gate stops them a
minute before its timeout and **lets the commit through, saying so**. The
session is told, you get a message, and the branch keeps a note that
`mr-meta.sh` returns as `UNCHECKED_AT_COMMIT`. The merge request opens with it,
"tests not completed at commit", and the CI runs the full suite. A later commit
whose checks finish green clears the note. `git add -A && git commit` in one
line is gated too: the checks are skipped only when there is nothing to commit
at all.

---

## 6. Several tasks at once: worktrees

A worktree is a second checkout of the same repository with its own files and
its own branch. One task per worktree means two sessions never edit the same
file.

```bash
claude --worktree DE-123     # one terminal
claude --worktree DE-124     # another
```

The worktree lands at `.claude/worktrees/DE-123/`. Inside a session, `--worktree`
on `/dev-setup:sdd` or `/dev-setup:quick` does the same thing.

Four pieces make it actually work:

| Piece | The problem it removes |
|---|---|
| `.worktreeinclude` | A worktree is a clean checkout, so `.env` is absent and the app fails for a reason that looks like a code bug. This file lists, in `.gitignore` syntax, what gets copied in. Add the project's own patterns here rather than copying files by hand |
| `worktree.baseRef` | It takes only `fresh` or `head` — never a branch name. On a project whose work targets `next` while the remote default is still `main`, `fresh` forks from the wrong branch, so the setup writes `head` and the fork point is passed explicitly |
| `PORT_OFFSET` | Every worktree runs the same `dev` script and wants the same port. `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-info.sh --json` gives this worktree's index; start the server on your base port plus that |
| `OVERLAPS` | The same call lists every file more than one active worktree declares in its spec's Impact section, with the branches. A warning, never a gate: two tasks may legitimately touch the same module, and the point is that the rebase is expected rather than discovered |

Dependencies are a step, not a hook: `pnpm install` (or whatever the project
uses) after entering. There is no post-create hook on purpose — a
`WorktreeCreate` hook replaces worktree creation wholesale and would disable
`.worktreeinclude`, which is the one thing that has to keep working.

**While you are in a worktree**, the harness blocks anything reaching back into
the main checkout: an edit outside it, a Bash command whose working directory
resolves there, a `git -C` or `cd` that redirects git out of it. Those are not
permission prompts and there is nothing to approve — do the work inside the
worktree, or open a different session for what belongs outside.

**How many, by which command.** `n` interactive tasks are `n` terminals: a flow
that stops to ask you something needs a chat of its own. `n` unsupervised tasks
are one `/dev-setup:multi-sdd`, up to five.

Cleaning up: leaving the session offers to remove the worktree, and one holding
changes is kept. By hand, `git worktree list` then `git worktree remove <path>`.
A failed run is worth keeping until someone has read it.

---

## 7. Extending it

### Add a rule of your own

The `dev-setup-` prefix is a contract: everything the setup writes into
`.claude/rules/` carries it, everything your team writes there does not. UPDATE
regenerates only the prefixed files and never touches yours.

So: create `.claude/rules/<anything-else>.md`, with the frontmatter the harness
reads.

```markdown
---
paths:
  - "src/payments/**/*.ts"
---

# Payment adapters

- Every adapter implements `PaymentPort` and is registered in `payments.module.ts`.
- Never log a full PAN; the last four digits only.
```

The frontmatter holds the globs and nothing else — the generated rules look
exactly like this. Leave `paths:` out and the rule loads in every session,
everywhere, which is what `dev-setup-core.md` is for and the reason it is
capped. If a rule can be checked by a machine, put it in ESLint or the test
runner instead: a lint error arrives at the moment of the mistake, a paragraph
arrives with luck.

### Add a skill of your own

A project skill goes in `.claude/skills/<name>/SKILL.md` and follows the same
standard as the plugin's:

```markdown
---
name: deploy-preview
description: Deploys the current branch to a preview environment and returns its URL. Use when a branch needs a shareable running instance before review.
---

# Deploy preview
...
```

Three things carry most of the value:

1. **The `description` is the trigger.** It is the only part always in context,
   and "Use when…" is what decides whether the skill is picked. A description
   naming the situation beats one naming the implementation.
2. **`SKILL.md` is a routing document, not a manual** — keep it under 500 words.
   Detail goes in `reference/*.md` next to it, linked by name from `SKILL.md`
   and read only when a run needs it.
3. **Cite a reference by name, never with an `@path` force-load.** An `@path`
   injects the file into every session, which is the opposite of what a
   reference is for.

---

## 8. Upgrading

Two separate things, in this order.

```
/plugin update dev-setup@acadevmy
```

updates the plugin's own skills, agents, scripts and templates. No file in your
project changes.

```
/dev-setup:setup
```

detects **UPDATE** mode and reapplies the templates to the project.

| Regenerated | Left alone |
|---|---|
| `.claude/rules/dev-setup-*.md` — overwritten, and any that your stack no longer needs are removed | `.claude/rules/<your-own>.md` |
| `AGENTS.md` — after asking; the first offer replaces only the plugin-owned tail (agents, commands, where the rules live), quoting the diff, and your sections stay | Git hooks, ESLint, Prettier, CI config |
| A `CLAUDE.md` holding only `@AGENTS.md` — removed without asking, at the root and in every sub-project; one with your own content is moved into its `AGENTS.md` only on your yes | `CLAUDE.local.md` and any instruction file above the project — reported, never touched |
| `.claude/settings.json` — only if it predates the sandbox, and only after showing you the diff | Dependencies and lock files |
| `REGISTRY.md`, `.env.example` — after asking; they are yours in UPDATE mode | Source code, `.env` |
| `.claude/auto-dev.json` — offered when it is absent, and reconfigured only after asking | `.claude/auto-dev.json` once you have one |
| `.claude/merge-request.json` — written when absent, after asking the language; missing catalogue labels are created on the forge | `.claude/merge-request.json` once you have one |
| `.claude/quality-commands.json` — proposed when absent (decline it and the autonomous launchers refuse until you accept it), a rewrite offered when malformed | `.claude/quality-commands.json` once you have a valid one — verified, never rewritten |

The one unasked edit to a file the setup did not write is a single `.gitignore`
line, `.claude/worktrees/`. It adds, never removes; without it every file of
every worktree shows up as untracked in the main checkout.

Keep team customisation out of the regenerated files — a `TEAM_NOTES.md`, or a
section of `REGISTRY.md` you maintain — and an upgrade is always a risk-free
accept-overwrite.

Coming from plugin v2, the changes are large enough to have their own page:
[migration-v2-to-v3.md](./migration-v2-to-v3.md).

---

## 9. Troubleshooting

### The commit was denied

Read the output — the hook denies with the real thing, not a summary. Lint,
types or tests are red; fix and commit again. Do not reach for `--no-verify`: it
is denied, and the same failure will meet you in CI.

If the denial names a bypass instead (`HUSKY=0`, a `core.hooksPath` override),
the project has its own hook manager and something tried to skip it. Run the
project's own checks and commit normally.

If the hook warns on stderr and lets a commit through, `jq` is missing or stack
detection failed. Install `jq`; the gate is fail-open by design and will not
tell you twice.

### AGENTS.md is not loading

Run `/memory`: it lists the instruction files the session loaded. Claude Code
reads `AGENTS.md` only from 2.1.281 on, and only when no `CLAUDE.md`,
`.claude/CLAUDE.md` or `CLAUDE.local.md` sits in the directory or in one above
it — a `CLAUDE.local.md` of your own, or a `CLAUDE.md` in the folder that holds
the repository, is enough to switch it off without an error. The setup lists
every such file in its summary and touches none it did not write. Move the
content out, or set **Project instructions** to `claude-md-and-agents-md` in
`/config` to read both. The built-in AGENTS.md support disabled in `/plugin`,
and the first session after an upgrade from 2.1.276 or earlier, skip it too.

### The merge request lists points to confirm

An autonomous run asks nobody anything, so whatever it had to decide on the
task's behalf is at the top of its merge request:

- **readings to confirm** — where the task admitted two behaviours, the one the
  spec took and why;
- **departures from the task** — where the task said how to build it and the
  project's ADRs, rules or libraries said otherwise, the task sentence and what
  overruled it;
- **open points** — the reviewers' proposals the spec author declined or left
  unanswered, each with the author's answer next to it.

All three are in the spec's technical decisions too. If you disagree with one,
that is review feedback on the merge request like any other: ask for the change
there, or fix it on the branch. Do not relaunch hoping for a different spec — a
fresh run argues the same task from the same sources.

### A workflow was interrupted

Resume it rather than launching again: a resume replays every finished agent
from the run's journal and only redoes what did not finish, while a fresh launch
redoes the spec and all three reviews at full price. Ask Claude to resume the
run — it has the run id. Resume is same-session only; once the session is gone,
so is the journal.

A `failed` run at the verify stage is the best case for this: fix the cause and
only the commands run again.

### A run says the workflow does not exist

`Workflow "dev-setup:auto-sdd-run" not found` almost always means a stale install is
shadowing a newer build. Check that the plugin actually ships it, and reinstall
or rebuild if it does not.

### A network call was refused

The host is outside `sandbox.network.allowedDomains`. You will be asked the
first time; answering "yes, and don't ask again" records it in
`.claude/settings.local.json`. If it is a host the whole team needs, add it to
`.claude/settings.json` instead and commit that.

### `git push` fails inside the sandbox

Your `origin` is an SSH remote and the push was not the plain form the
exclusion matches — see §4. `git push origin <branch>` or
`git push -u origin <branch>`, alone on the line, runs outside the sandbox; a
`cd … &&`, a pipe or a push to a URL keeps it in.

### ClickUp does not respond

The first call opens the browser for OAuth. If the session expired, restart
Claude Code and the flow starts again on its own.

### The merge request is open but the task is still IN PROGRESS

`post-merge-request.sh` exists to catch exactly this: it fires on the command
that created the merge request and names the task whose clock is still running.
The reminder arrives as context next to the command's result
(`additionalContext`), not as a hook error. If none arrived — the merge request
was opened from the web UI, `jq` is missing, the installed plugin predates the
hook — the two calls are:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" --task DE-123 --stop --json
```

then move the task to `CODE REVIEW` with the `COMMENT` it returns, verbatim. To
see what is still open in the repository without closing anything, the same
script with `--status` and no `--task` lists it.

### `/dev-setup` is not in the command list

The client is not loading mods: it is older than 2.1.287, the rollout has not
reached it, or mods are turned off (`--safe-mode`, `disableAllHooks`, managed
settings). On 2.1.285 they are early access: start Claude Code with
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` in its environment. Nothing else in the
plugin depends on them.

### The task moved but carries no time

The clock had nothing to report, and that is the designed outcome rather than a
silent one: the session says which reason it got. `no-start-stamp` means the
start was never stamped — a task resumed in another clone, or a flow that began
before this plugin version. `already-stopped` means the clock was closed
earlier, on a bail-out to `BLOCKED`, and the sitting after it was never opened.

Neither is worth reconstructing by hand, and nothing in the flow will estimate
the number for you: a duration posted on a task reads as a measurement, and an
invented one is worse than none. Start the next sitting by moving the task to
`IN PROGRESS` again.

### The setup did not detect my stack

For the quality commands it does not need to. Step 3b proposes what your CI,
task runner, package scripts and README already run, whatever the language, and
asks; a kind with no candidate is still asked, and you type the command. What
you confirm lands in `.claude/quality-commands.json`, which wins over any
detection — edit it by hand at any time, and re-run `/dev-setup:setup` to have
it verified.

The rules and the profiles do depend on detection. For those, make sure the
project root actually holds the marker: `package.json` with the dependencies
(Next.js, Angular, React, NestJS), `pubspec.yaml` (Flutter), or `app.json` with
an `expo` key (React Native).

### An autonomous run refuses to start

`/dev-setup:auto-sdd` or `/dev-setup:multi-sdd` stopped before the board with a
`quality-preflight.sh` reason. It names the cause: no
`.claude/quality-commands.json` (a project set up before the declaration
existed — run `/dev-setup:setup` once), a malformed one, every command declared
absent. Fix that, and launch again; nothing was started, so there is nothing to
clean up. A program the environment does not have, or a `preflight` that
failed, does not land here: the run starts and its merge request lists those
checks as not verified.

### Every headless merge request lists the same checks as not verified

The runner ran `auto-dev` without the toolchain those commands start: the
repository has no devcontainer, or one that lacks the program. Run
`/dev-setup:devcontainer` in that repository; with a configuration already
there, `/dev-setup:devcontainer --check` names the command that does not
start inside it.

### A rule I expected did not load

Rules load on a path match. Open a file the rule's globs cover and it arrives; if
it still does not, check the `paths:` frontmatter of the file in
`.claude/rules/`. A rule with no `paths:` loads everywhere — if you meant to
scope it and forgot, that is the symptom you would see instead.
