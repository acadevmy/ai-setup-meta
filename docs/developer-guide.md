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

- [1. The six commands](#1-the-six-commands)
- [2. A task, end to end](#2-a-task-end-to-end)
- [3. The rules, and when each one loads](#3-the-rules-and-when-each-one-loads)
- [4. The sandbox and the ask rules](#4-the-sandbox-and-the-ask-rules)
- [5. The quality gate on the commit](#5-the-quality-gate-on-the-commit)
- [6. Several tasks at once: worktrees](#6-several-tasks-at-once-worktrees)
- [7. Extending it](#7-extending-it)
- [8. Upgrading](#8-upgrading)
- [9. Troubleshooting](#9-troubleshooting)

---

## 1. The six commands

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
```

| Command | Use it when | Example |
|---|---|---|
| `/dev-setup:setup` | Configuring a project for the first time, or pulling in a new plugin version | `/dev-setup:setup` |
| `/dev-setup:quick` | At most three files, and no new component, dependency or public interface | `/dev-setup:quick DE-123`<br>`/dev-setup:quick fix the 500 on an empty cart` |
| `/dev-setup:sdd` | Anything above that bar — the spec is what a reviewer reads the diff against | `/dev-setup:sdd DE-124`<br>`/dev-setup:sdd DE-124 --worktree` |
| `/dev-setup:auto-sdd` | A well-defined task you do not want to sit through | `/dev-setup:auto-sdd DE-125` |
| `/dev-setup:multi-sdd` | Several independent tasks, unsupervised, from one chat | `/dev-setup:multi-sdd DE-1 DE-2 DE-3`<br>`/dev-setup:multi-sdd --from-sprint 3` |
| `/dev-setup:review` | A branch is ready and you want it read before the merge request | `/dev-setup:review` |

Everything else the flows use — discovery, spec, plan, development, verify, the
board conventions, the git conventions — is a skill the orchestrator invokes by
name. They are not commands and they do not show up in `/help`: one flow, one
entry point.

**Picking between `quick` and `sdd`.** The bar is three files and no new
component, dependency or public interface. Claude may say a task looks
misrouted; the routing is yours, and the command you type is the decision.

**Which one does `review` belong to?** It runs inside `sdd` already, before the
commit. Invoked on its own it reviews the current branch, updates `REGISTRY.md`
in your working tree and commits nothing.

**`validate` is not one of these.** `/project:validate` runs in the plugin's own
repository, not in yours — see [workflow.md](./workflow.md).

---

## 2. A task, end to end

```
/dev-setup:sdd DE-123
       │
       ├─ reads the task, asks which branch to fork from — the default is
       │  resolved from the repository, never hard-coded — then creates
       │  feat/DE-123-…, moves the task to IN PROGRESS and starts the clock
       │
       ├─ discovery — a structured interview, only the questions that matter
       │
       ├─ the technical spec, written to .specs/
       │        ↓
       │   ★ you approve it — the flow's approval checkpoint
       │
       ├─ development against the approved plan, one step at a time
       │
       ├─ simplify → verify against the spec → review + REGISTRY
       │
       ├─ one commit: code + spec + REGISTRY, with the gate running here
       │
       ├─ push, then the merge request  ← your confirmation is required
       │
       └─ the task moves to review, with the link and the time it took
          posted on it
```

Seven things are worth knowing about that shape.

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

**The description is the repository's template, filled in.** The setup writes
one — `.github/PULL_REQUEST_TEMPLATE.md` on GitHub,
`.gitlab/merge_request_templates/Default.md` on GitLab, in Italian or English,
whichever you chose — and every flow fills that file instead of inventing a
body: neither `gh` nor `glab` applies a template to a description passed on the
command line. The title is `<Type>: <what was done> <TASK-ID>`, for instance
`Feat: Add refresh token rotation DE-123`; the commits keep their Conventional
Commits form. The section that matters is the test one: the commands to run and
the route to open, written for a reviewer who has not read the branch. A
template already in the repository is never overwritten — the flows fill the
team's own.

**The methodology is not a question.** Backend logic is test-first, UI is
scenario-first, and `.claude/rules/dev-setup-tests.md` says so — it loads by
itself when you open a test file. Both cycles are written out in the plugin's
`sdd-dev` reference, read by whoever is writing the code.

### The autonomous variant

`/dev-setup:auto-sdd DE-123` runs the same ground as a workflow script: it
writes the spec, has three adversarial reviewers attack it — one looking for a
simpler design, one for scope creep, one for testability — develops in an
isolated worktree so your checkout never moves, and runs the project's own lint,
typecheck and test commands.

It comes back with one of three outcomes:

| Outcome | What it means | What you do |
|---|---|---|
| `ready-for-mr` | Green, committed on its branch | Confirm the push and the merge request |
| `needs-human` | Two of the three lenses refused the spec | Answer the objections (§9) |
| `failed` | The spec, the dev step or a quality command failed | Read the real output; the branch and worktree are left in place |

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
helper, so no token goes in the URL), or keep SSH and let git's network commands
run outside the sandbox through the normal permission prompt. The deny rules
hold either way: they are permission rules, not sandbox boundaries.

---

## 5. The quality gate on the commit

`gate-commit.sh` is a `PreToolUse` hook on `Bash`, and it picks its mode from
what the project already owns, so the checks run once and only once.

**Your project has husky, lefthook, simple-git-hooks or a `core.hooksPath`.**
Then your own tooling runs the per-commit checks and the hook only refuses the
ways around it: `HUSKY=0`, `LEFTHOOK=0`, a `-c core.hooksPath=…` override, a
`GIT_CONFIG_*` injection. (`--no-verify` and `-n` are separately denied.) A
commit *message* that happens to mention `HUSKY=0` is not an attempt to set it —
the scan reads the command with quoted strings removed.

**Your project has no hook manager.** Then the hook is the gate: it runs the
lint, typecheck and test commands detected from your project and denies the
commit with the tail of the real output as the reason. Not a summary of the
failure — the failure.

The full test suite is deliberately not the per-commit gate. That belongs at the
merge-request boundary and in CI, which stays the final word.

The hook is **fail-open**: with no `jq`, or if stack detection cannot run, it
warns on stderr and lets the commit through. It is a quality gate, not a
security boundary — the security boundary is the deny rules and the sandbox, and
blocking every commit on a broken toolchain would be worse than reporting it.

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
| `AGENTS.md`, `CLAUDE.md` — after asking | Git hooks, ESLint, Prettier, CI config |
| `.claude/settings.json` — only if it predates the sandbox, and only after showing you the diff | Dependencies and lock files |
| `REGISTRY.md`, `.env.example` — after asking; they are yours in UPDATE mode | Source code, `.env` |
| `.claude/auto-dev.json` — offered when it is absent, and reconfigured only after asking | `.claude/auto-dev.json` once you have one |

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

### A run came back `needs-human`

Two of the three lenses refused the spec, so nothing was written: no branch, no
worktree, no merge request. You will be shown each objection with its lens and
its reason. There are two honest answers:

- **The objection is wrong.** Say which lens missed something and why. That lens
  is cleared, the run resumes **at development** — the spec and the three
  verdicts come back from cache, so you are not paying for them twice — and your
  overrule is recorded in the outcome and quoted in the merge request.
- **The objection is right.** Then the spec was built on a decision the task
  never made, and there is nothing to resume: put the answer in the task, move
  it back to the sprint, and launch again.

Do not argue the objection back and forth, and do not relaunch hoping for a
different verdict. Two out of three is the gate, it is in code, and the only
thing that moves it is a person.

### A workflow was interrupted

Resume it rather than launching again: a resume replays every finished agent
from the run's journal and only redoes what did not finish, while a fresh launch
redoes the spec and all three challenges at full price. Ask Claude to resume the
run — it has the run id. Resume is same-session only; once the session is gone,
so is the journal.

A `failed` run at the verify stage is the best case for this: fix the cause and
only the commands run again.

### A run says the workflow does not exist

`Workflow "dev-setup:auto-sdd" not found` almost always means a stale install is
shadowing a newer build. Check that the plugin actually ships it, and reinstall
or rebuild if it does not.

### A network call was refused

The host is outside `sandbox.network.allowedDomains`. You will be asked the
first time; answering "yes, and don't ask again" records it in
`.claude/settings.local.json`. If it is a host the whole team needs, add it to
`.claude/settings.json` instead and commit that.

### `git push` fails inside the sandbox

Your `origin` is an SSH remote — see §4. Switch it to HTTPS, or let git's
network commands run outside the sandbox.

### ClickUp does not respond

The first call opens the browser for OAuth. If the session expired, restart
Claude Code and the flow starts again on its own.

### The merge request is open but the task is still IN PROGRESS

`post-merge-request.sh` exists to catch exactly this: it fires on the command
that created the merge request and names the task whose clock is still running.
If no reminder arrived — the merge request was opened from the web UI, `jq` is
missing, the installed plugin predates the hook — the two calls are:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" --task DE-123 --stop --json
```

then move the task to `CODE REVIEW` with the `COMMENT` it returns, verbatim. To
see what is still open in the repository without closing anything, the same
script with `--status` and no `--task` lists it.

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

Make sure the project root actually holds the marker: `package.json` with the
dependencies (Next.js, Angular, React, NestJS), `pubspec.yaml` (Flutter), or
`app.json` with an `expo` key (React Native).

### A rule I expected did not load

Rules load on a path match. Open a file the rule's globs cover and it arrives; if
it still does not, check the `paths:` frontmatter of the file in
`.claude/rules/`. A rule with no `paths:` loads everywhere — if you meant to
scope it and forgot, that is the symptom you would see instead.
