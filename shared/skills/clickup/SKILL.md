---
name: clickup
description: Explains how the team's ClickUp board is organised — the workflow statuses and what each one means, the OAuth prerequisites, and what each task operation returns. Use when a flow has to read a task, move it through the board, or create one, and the board's conventions matter.
user-invocable: false
disable-model-invocation: false
---

# ClickUp operations

ClickUp is where the team's tasks live. This skill is the board's documentation;
the **calling contract** — the intents, their parameters, the result format and
how the task list id is resolved — is in
`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`, and every ClickUp call
goes through the `clickup` agent described there.

## Prerequisites

- the ClickUp MCP configured over OAuth:
  `claude mcp add clickup -t http -s user https://mcp.clickup.com/mcp`
- each developer authenticates with their own ClickUp account (guest accounts
  work)
- every operation works on a specific `list_id` — there is no global `TEAM_ID`

## The workflow

```
SPRINT  ->  IN PROGRESS  ->  IN REVIEW / CODE REVIEW  ->  DONE
```

| Status | Meaning |
|---|---|
| SPRINT | planned in the current sprint, ready to be picked up |
| IN PROGRESS | someone is working on it |
| IN REVIEW / CODE REVIEW | the PR/MR is open, waiting for a reviewer |
| DONE | merged |
| BLOCKED | an automated run gave up; a human has to resolve the blocker |

Two lists use different names for the same stage — `IN REVIEW` and
`CODE REVIEW`. Ask for `CODE REVIEW` and fall back to `IN REVIEW` when the list
does not have it.

## What the operations are for

**Pick the next task.** Filter the list on `SPRINT`, sort by priority
(1 = urgent … 4 = low), take the first. The task's `custom_id` (e.g. `DE-123`)
is what goes into the branch name — not the internal `task_id`.

**Read a task.** Returns title, description, status, assignees, custom fields and
`custom_id`. The description comes back in full: it is the requirement text, and
a summarised requirement is a lost requirement.

**Move a task.** A status change, optionally with a note. The transition is
validated against the workflow above, so ask for the one the flow has actually
reached.

**Create a task.** Needs the destination `list_id`, a `name` and a `description`
(markdown is supported); `priority`, `assignees` and `due_date` are optional.

## What not to do

- Do not close or delete tasks: status updates and comments only.
- Do not write a task's description from a flow — it is the human's input to the
  work, not the work's output.
