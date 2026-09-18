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
- [The work clock](#the-work-clock)
- [The backlog gate](#the-backlog-gate)
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

**Do not read the project's `.env` for this.** Reads of that file are open, but
one list id does not justify pulling a file of secrets into the context window.
If neither source has the value, say so and stop: the fix is for the developer
to export the variable or fill it in through the plugin config.

## Status transitions

```
BACKLOG  -- the backlog gate -->  IN PROGRESS
SPRINT  ->  IN PROGRESS  ->  IN REVIEW / CODE REVIEW  ->  DONE
   |            ^  |
   |            |  v
   +--------- BLOCKED  (until a human resolves the blocker)
```

The agent validates the transition and refuses an invalid one, so ask for the
transition the flow is actually at: `SPRINT -> IN PROGRESS` when work starts,
`IN PROGRESS -> CODE REVIEW` (fallback `IN REVIEW`) when the PR/MR is open,
`-> BLOCKED` on a bail-out, `BLOCKED -> SPRINT` on recovery.
`BACKLOG -> IN PROGRESS` is requested only as the recorded answer to the
backlog gate below — never on the flow's own initiative.

## The work clock

Two of those transitions bracket the work, so they bracket the clock too. A
script holds the reading in between — every flow calls it at both ends:

| At the move to | Call | What comes back |
|---|---|---|
| `IN PROGRESS` | `task-clock.sh --task <custom_id> --start --json` | `STARTED_AT`. Already open, it reports `already-running` and keeps the first stamp — a resumed task does not restart its clock |
| `CODE REVIEW` / `BLOCKED` | `task-clock.sh --task <custom_id> --stop --json` | `COMMENT`: the line to post, already written |

Both are `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" …`. `COMMENT`
reads `Time in progress: 2h 15m (2026-09-18 14:03 → 2026-09-18 16:18)`, and it
travels as the `comment` of the status `update` that closes the task — the same
one call, never a second write. On a bail-out it goes after the note, on the
same `BLOCKED` call.

Three rules:

1. **Never write the duration yourself.** Not from the session's length, not
   from the timestamps in the transcript, not as an estimate. The number comes
   from `COMMENT` or it does not exist — a made-up duration on a tracked task
   is worse than a missing one, because it reads like a measurement.
2. **An empty `COMMENT` posts nothing.** `REASON` says why:
   `no-start-stamp` (nobody stamped the start — a flow resumed in a fresh
   clone, say) or `already-stopped`. Move the task, say the clock had nothing,
   and carry on.
3. **No task id, no clock.** `quick` on a plain description has nothing to
   stamp and no task to post it on.

A non-zero exit from the clock is one line of report and nothing more. The
flow's job is the merge request; a stopwatch that failed never holds it up.

## The backlog gate

`BACKLOG` holds work nobody planned into a sprint. No flow picks a backlog
task up on its own: `filter` and `next-task` read `SPRINT`, so a backlog task
only ever arrives as an id the developer typed. When a `read` comes back with
`status: BACKLOG`, stop — before any branch, spec or board write — and ask:

```json
AskUserQuestion({
  "questions": [{
    "question": "<custom_id> is in BACKLOG — it was never planned into a sprint. Implement it anyway?",
    "header": "Backlog",
    "options": [
      { "label": "Implement it", "description": "The task moves to IN PROGRESS and the flow continues" },
      { "label": "Leave it", "description": "Stop here — the task is not touched" }
    ],
    "multiSelect": false
  }]
})
```

End the turn on the call (`turn-discipline.md`). **Implement it** is the only
thing that authorises `BACKLOG -> IN PROGRESS`; from there the flow proceeds
exactly as if the task had been in `SPRINT`. **Leave it** ends the flow with
the task exactly as it was found. The move never happens automatically: a path
with nobody to ask (`next-task`, a scheduled run) treats a backlog task as out
of scope and says so instead of moving it.

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
