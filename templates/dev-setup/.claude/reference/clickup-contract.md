# The ClickUp contract

Every skill in this plugin that touches ClickUp goes through the `clickup`
subagent. It owns the MCP tool names, the transition table and the output
format; the skills own only the intent they need. This file is that contract,
written once — cite it, do not restate it.

## Index

- [How to call the agent](#how-to-call-the-agent)
- [Intents and parameters](#intents-and-parameters)
- [Reading the result](#reading-the-result)
- [Resolving the task list id](#resolving-the-task-list-id)
- [Status transitions](#status-transitions)
- [The bail-out call](#the-bail-out-call)

## How to call the agent

Launch the `clickup` agent with two lines, an `INTENT` and its `PARAMS`:

```
INTENT: read
PARAMS: task_id: DE-123
```

Never call `mcp__clickup__*` directly from a skill: the agent exists so that the
tool names, the fidelity rule (a description is returned in full, never
summarised) and the transition validation live in one place.

## Intents and parameters

| Intent | Required | Optional | Returns |
|---|---|---|---|
| `read` | `task_id` | — | one task, every field |
| `filter` | `list_id` | `status`, `assignee` | every matching task |
| `next-task` | `list_id` | — | the highest-priority task in `SPRINT` |
| `update` | `task_id`, `status` | `comment` | the updated task |
| `create` | `list_id`, `name`, `description` | `priority`, `assignees`, `due_date` | the created task |

`priority` is numeric and ascending in urgency: `1` urgent, `2` high, `3`
normal, `4` low. When a flow has to pick one task out of a list, sort by that
field and take the first.

## Reading the result

The agent answers with a `---CLICKUP-RESULT---` block ending in `---END---`. It
carries `STATUS: success | error`, the intent, and one `DATA:` block per task
with `task_id`, `custom_id` (`DE-123`), `name`, `description`, `status`,
`priority`, `assignees`, `url` and `custom_fields`.

On `STATUS: error` the block carries an `ERROR:` line. Report it to the
developer and stop — or, in an autonomous flow, bail out. Never retry the same
call hoping for a different answer.

## Resolving the task list id

A flow that starts without a task id needs the list to read from. Look for
`CLICKUP_SETUP_LIST_ID` in this order:

1. the environment variable;
2. the plugin's `userConfig` (set at install time).

**Do not read the project's `.env`.** The setup denies that file to the file
tools and to sandboxed shell commands, and one list id does not justify pulling
a file of secrets into the context window. If neither source has the value, say
so and stop: the fix is for the developer to export the variable or fill it in
through the plugin config.

## Status transitions

```
SPRINT  ->  IN PROGRESS  ->  IN REVIEW / CODE REVIEW  ->  DONE
   |            ^  |
   |            |  v
   +--------- BLOCKED  (until a human resolves the blocker)
```

The agent validates the transition and refuses an invalid one, so ask for the
transition the flow is actually at: `SPRINT -> IN PROGRESS` when work starts,
`IN PROGRESS -> CODE REVIEW` (fallback `IN REVIEW`) when the PR/MR is open,
`-> BLOCKED` on a bail-out, `BLOCKED -> SPRINT` on recovery.

## The bail-out call

A bail-out is **one** `update` call: the status change and the explanation
travel together, because the agent exposes no standalone comment intent.

```
INTENT: update
PARAMS: task_id: <task_id>, status: BLOCKED, comment: "<the note>"
```

The note says which step failed, why, which branch holds the work, and what a
human should try next. Leave the local branch in place — it is the debugging
material.
