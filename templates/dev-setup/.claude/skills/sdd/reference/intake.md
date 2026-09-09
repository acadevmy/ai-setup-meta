# Intake — task, branch, status, brief

Steps 1 to 4 of the flow: from "start this task" to a working branch with the
task in progress and the developer looking at the brief. The ClickUp calls
follow `${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`; the turn rule for
every question here is in
`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`.

## Index

- [1. Task selection](#1-task-selection)
- [2. The working branch](#2-the-working-branch)
- [3. Task status](#3-task-status)
- [4. The brief](#4-the-brief)

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

The type comes from the task: a feature → `feat/`, a bug → `fix/`, maintenance
→ `chore/`.

**Ask which base branch to use** — it is not always `main`:

1. run `git branch -r --sort=-committerdate | head -10`;
2. strip the `origin/` prefix and drop `HEAD`;
3. build the `AskUserQuestion` options from those branches (at most 4), using
   the branch name as the label and something useful as the description (the
   last commit date, or "the project's main branch" for main/master);
4. the developer can always pick "Other" and type a name.

Then create it:

```bash
git checkout <base-branch>
git pull origin <base-branch>
git checkout -b <type>/<customId>-<short-description>
```

For example `feat/DE-123-add-user-auth`.

## 3. Task status

`INTENT: update`, `PARAMS: task_id: <task_id>, status: IN PROGRESS`.

## 4. The brief

```
Task:     DE-123 — Task title
Priority: High
Branch:   feat/DE-123-add-user-auth
Status:   IN PROGRESS

Description:
<the task description, as the agent returned it>
```
