# Intake — task, branch, status, brief

Steps 1 to 4 of the flow: from "start this task" to a working branch with the
task in progress and the developer looking at the brief. Two of the four steps
are a script call, not a judgement call. The ClickUp calls follow
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`; the turn rule for every
question here is in `${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`.

## Index

- [1. Task selection](#1-task-selection)
- [2. The working branch](#2-the-working-branch)
- [3. Task status](#3-task-status)
- [4. The brief, and what is already on disk](#4-the-brief-and-what-is-already-on-disk)

## 1. Task selection

**With a task id in `$ARGUMENTS`** (e.g. `DE-123`): read it through the
`clickup` agent (`INTENT: read`, `PARAMS: task_id: <id>`). On `STATUS: error`,
tell the developer and stop.

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

One call names the branch, resolves the base and creates it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sdd-start.sh" \
  --task <custom_id> --type <feat|fix|chore> --title "<name>" --create --json
```

The type comes from the task: a feature → `feat`, a bug → `fix`, maintenance →
`chore`. The script slugifies the title, keeps the id verbatim (the spec lookup
and the merge request title read it back out of the branch name), and resolves
`BASE_BRANCH` itself — the branch HEAD forked from most recently, never a
hard-coded `main`. Do not ask the developer which base to use, and do not run
`git checkout`/`git pull` by hand: that question is what the script answers, and
a wrong answer makes every diff downstream cover two branches' work.

Report `BRANCH` and `BASE_BRANCH` from the output.

`BRANCH_EXISTS: true` means the task already had a branch and the script checked
it out rather than creating one. Say so: the task is being resumed, and step 4
will show how far it got.

With `--worktree`, the order matters: read `BASE_BRANCH` from
`check-prerequisites.sh` **in the main checkout**, enter the worktree named after
the task, and only then run the call above with `--base <that ref>`. A fresh
worktree forks from the remote default, so its local HEAD is not a fork point
worth resolving. `${CLAUDE_PLUGIN_ROOT}/reference/worktree.md` covers the rest —
the dependency install, the port, the overlap warning.

## 3. Task status

`INTENT: update`, `PARAMS: task_id: <task_id>, status: IN PROGRESS`.

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

Never re-run discovery over a spec that exists. Say which step you are starting
from and why, then show the brief:

```
Task:     DE-123 — Task title
Priority: High
Branch:   feat/DE-123-add-user-auth  (base: origin/next)
Status:   IN PROGRESS
Spec:     .specs/DE-123-add-user-auth.md (approved) — or "none yet"

Description:
<the task description, as the agent returned it>
```
