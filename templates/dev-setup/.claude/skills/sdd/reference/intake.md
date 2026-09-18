# Intake — task, branch, status, brief

Steps 1 to 4 of the flow: from "start this task" to a working branch with the
task in progress and the developer looking at the brief. The judgement calls
here are two questions — the task and the fork point — and a script does the
rest. The ClickUp calls follow
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`; the turn rule for every
question here is in `${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`.

## Index

- [1. Task selection](#1-task-selection)
- [2. The working branch](#2-the-working-branch)
- [3. Task status, and the clock](#3-task-status-and-the-clock)
- [4. The brief, and what is already on disk](#4-the-brief-and-what-is-already-on-disk)

## 1. Task selection

**With a task id in `$ARGUMENTS`** (e.g. `DE-123`): read it through the
`clickup` agent (`INTENT: read`, `PARAMS: task_id: <id>`). On `STATUS: error`,
tell the developer and stop.

A task that comes back in `BACKLOG` was never planned: before the branch
exists, put it through the backlog gate in
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md` — ask whether to
implement it anyway, and **end the turn on the tool call**. Declined → stop,
leaving the task exactly where it was. Confirmed → carry on: step 3's status
move is the one the developer just authorised, and the rest of the flow is
unchanged.

**Without one**: resolve the task list id as the ClickUp contract describes,
then list what is available:

- `INTENT: filter`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>, status: SPRINT`;
- on `STATUS: error`, tell the developer and stop;
- take the first 5 results sorted by priority (1 = urgent … 4 = low);
- present them with `AskUserQuestion`:

  ```json
  AskUserQuestion({
    "questions": [{
      "question": "Which task do you want to pick up?",
      "header": "Task",
      "options": [
        { "label": "[DE-123] Task title", "description": "Priority: Urgent" },
        { "label": "[DE-124] Task title", "description": "Priority: High" }
      ],
      "multiSelect": false
    }]
  })
  ```

- **end the turn on the tool call**;
- read the chosen task in full (`INTENT: read`).

From the result, keep `custom_id`, `name`, `description` (in full, as the agent
returned it), `priority`, `task_id` and `url`. Everything downstream refers to
these.

## 2. The working branch

The script names the branch and resolves the default fork point, the developer
confirms the fork point, and the script creates the branch. First, report only
— no `--create`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" \
  --task <custom_id> --type <feat|fix|chore> --title "<name>" --json
```

The type comes from the task: a feature → `feat`, a bug → `fix`, maintenance →
`chore`. The script slugifies the title, keeps the id verbatim (the spec lookup
and the merge request title read it back out of the branch name), and resolves
`BASE_BRANCH` — the branch HEAD forked from most recently, never a hard-coded
`main`.

`BRANCH_EXISTS: true` means the task already had a branch: re-run the call with
`--create` (it checks the branch out), skip the question below — the fork point
was decided when the branch was born — and say the task is being resumed; step 4
will show how far it got.

Otherwise confirm the fork point. The resolved `BASE_BRANCH` is the default,
never the decision:

```json
AskUserQuestion({
  "questions": [{
    "question": "Which branch should <BRANCH> fork from?",
    "header": "Base branch",
    "options": [
      { "label": "<BASE_BRANCH> (Recommended)",
        "description": "Resolved from the repository: the ref HEAD forked from most recently" },
      { "label": "<candidate>",
        "description": "Any of develop / next / main that exists and is not the default" }
    ],
    "multiSelect": false
  }]
})
```

The resolved `BASE_BRANCH` is the first option; after it, whichever of
`develop`, `next` and `main` exist in the repository and are not the default.
Any other ref arrives through "Other". **End the turn on the tool call.**

Then create the branch from the answer:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" \
  --task <custom_id> --type <type> --title "<name>" \
  --base <the chosen ref> --create --json
```

Never run `git checkout`/`git pull` by hand in place of these calls: a wrong
fork point makes every diff downstream cover two branches' work. Report
`BRANCH` and `BASE_BRANCH` from the output.

With `--worktree`, the order matters: resolve and confirm the fork point **in
the main checkout** — the report-only call and the question above — then
enter the worktree named after the task, and only there run the `--create`
call with `--base <the chosen ref>`. A fresh worktree forks from the remote default, so
its local HEAD is not a fork point worth resolving.
`${CLAUDE_PLUGIN_ROOT}/reference/worktree.md` covers the rest — the dependency
install, the port, the overlap warning.

## 3. Task status, and the clock

`INTENT: update`, `PARAMS: task_id: <task_id>, status: IN PROGRESS`.

For a task found in `BACKLOG` at step 1, this is the move the developer
authorised through the backlog gate — never make it without that answer.

Then start the clock the closure reads back:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" --task <custom_id> --start --json
```

`STARTED_AT` goes in the brief below. A `REASON: already-running` means this
task was here before and its first stamp stands — say the clock is being
resumed, and report the `TOTAL_DURATION` it already holds. The work clock
section of the ClickUp contract holds the rest.

## 4. The brief, and what is already on disk

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

`SPEC` and `SPEC_STATUS` say whether this task has been here before, and that
decides where the flow actually starts:

| `SPEC_STATUS` | Start at |
|---|---|
| empty (no spec) | step 5, discovery |
| `draft` | step 7, `sdd-plan` — the spec exists and was never approved |
| `approved` | step 8, `sdd-dev` |
| `implemented` | step 9, closure — say so first, the work may already be done |

`approved` with a non-empty `CHANGED_FILES` is a run that stopped between
development and closure. Say so, show the changed files, and ask whether the
implementation is complete — complete → step 9; not yet → step 8, which picks
the plan up where it left off. Never silently redo development over a diff
that already exists.

Never re-run discovery over a spec that exists. Say which step you are starting
from and why, then show the brief:

```
Task:     DE-123 — Task title
Priority: High
Branch:   feat/DE-123-add-user-auth  (base: origin/next)
Status:   IN PROGRESS  (clock started 2026-09-18 14:03)
Spec:     .specs/DE-123-add-user-auth.md (approved) — or "none yet"

Description:
<the task description, as the agent returned it>
```
