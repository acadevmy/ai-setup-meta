---
name: tracker
description: Explains how the team's task tracker is organised — which tracker the project uses, the canonical workflow statuses and what each one means, and what each task operation returns. Use when a flow has to read a task, move it through the board, or create one, and the board's conventions matter.
user-invocable: false
disable-model-invocation: false
---

# Task tracker operations

The task tracker is where the team's tasks live — ClickUp or Linear, whichever
the project chose at setup. This skill is the board's documentation; the
**calling contract** — the intents, their parameters, the result format, the
canonical statuses and how the provider and the task list are resolved — is in
`${CLAUDE_PLUGIN_ROOT}/reference/tracker-contract.md`, and every tracker call
goes through the `tracker` agent described there.

## Configured at install time

- provider: `${user_config.TRACKER_PROVIDER}`
- task list: `${user_config.TRACKER_LIST_ID}`
- earlier ClickUp list: `${user_config.CLICKUP_SETUP_LIST_ID}` — alone, it
  means ClickUp with this list

Empty or unexpanded = unset. `.claude/tracker.json` and the
`TRACKER_*` variables come first (the contract's resolution order).

## The workflow

```
BACKLOG  ->  (developer confirms)  ->  IN PROGRESS
READY  ->  IN PROGRESS  ->  IN REVIEW  ->  DONE
```

| Status | Meaning |
|---|---|
| BACKLOG | not planned; a flow never picks it up or moves it on its own |
| READY | planned, ready to be picked up |
| IN PROGRESS | someone is working on it |
| IN REVIEW | the PR/MR is open, waiting for a reviewer |
| DONE | merged |
| BLOCKED | an automated run gave up; a human has to resolve the blocker |

These are canonical names. The board's own — `sprint` and `code review` on
ClickUp, `Todo` on Linear — are mapped in `.claude/tracker.json`, and only the
`tracker` agent ever sees them.

## What the operations are for

**Pick the next task.** Filter the list on `READY`, sort by priority
(1 = urgent … 4 = low), take the first. The task's `key` (e.g. `DE-123`,
`ENG-42`) is what goes into the branch name — not the internal `task_id`.

**Read a task.** Returns title, description, status, assignees, custom fields and
`key`. The description comes back in full: it is the requirement text, and
a summarised requirement is lost.

**Move a task.** A status change, optionally with a note. The transition is
validated against the workflow above, so ask for the one the flow has actually
reached.

**Create a task.** A `list_id`, a `name`, a markdown `description`; optionally
a `task_type`, a `parent` and existing `tags`. An Epic is a task with
subtasks, one level deep.

## What not to do

- Do not close or delete tasks: status updates and comments only.
- Do not move a task out of `BACKLOG` without the developer's explicit
  confirmation — the flows ask first, and nothing moves it automatically.
- Do not rewrite an existing task's description from a flow — it is the
  human's input to the work. Only `story` writes one, on the tasks it creates.
