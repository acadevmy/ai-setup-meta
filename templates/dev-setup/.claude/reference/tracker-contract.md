# The task tracker contract

Every skill in this plugin that touches the task tracker goes through the
`tracker` subagent. It owns the provider, the MCP tool names, the status names
and the transition table; the skills own only the intent they need. This file
is that contract, written once — cite it, do not restate it.

## Index

- [How to call the agent](#how-to-call-the-agent)
- [Intents and parameters](#intents-and-parameters)
- [Reading the result](#reading-the-result)
- [Resolving the provider and the task list](#resolving-the-provider-and-the-task-list)
- [Canonical statuses and transitions](#canonical-statuses-and-transitions)
- [The work clock](#the-work-clock)
- [The backlog gate](#the-backlog-gate)
- [The bail-out call](#the-bail-out-call)

## How to call the agent

Launch the `tracker` agent with two lines, an `INTENT` and its `PARAMS`:

```
INTENT: read
PARAMS: task_id: DE-123
```

Never call a tracker's MCP tools directly from a skill: the agent exists so that
the provider, the tool names, the fidelity rule (a description is returned in
full, never summarised) and the transition validation live in one place. What
each tracker calls its tools and its statuses is in that tracker's adapter,
`${CLAUDE_PLUGIN_ROOT}/reference/tracker-<provider>.md`, which only the agent
reads.

## Intents and parameters

| Intent | Required | Optional | Returns |
|---|---|---|---|
| `read` | `task_id` | — | one task, every field |
| `filter` | `list_id` | `status`, `assignee` | every matching task |
| `next-task` | `list_id` | — | the highest-priority task in `READY` |
| `update` | `task_id`, `status` | `comment` | the updated task |
| `create` | `list_id`, `name`, `description` | `priority`, `assignees`, `due_date` | the created task |

`task_id` is the task's key (`DE-123`, `ENG-42`) or the tracker's own id.
`list_id` is what the provider groups tasks by — a ClickUp list, a Linear team.
`status` is always a canonical status (below), never a board's own name.

`priority` is numeric and ascending in urgency: `1` urgent, `2` high, `3`
normal, `4` low. When a flow has to pick one task out of a list, sort by that
field and take the first.

## Reading the result

The agent answers with a `---TRACKER-RESULT---` block ending in `---END---`. It
carries `STATUS: success | error | unsupported`, the provider, the intent, and
one `DATA:` block per task with `task_id`, `key` (`DE-123`), `name`,
`description`, `status` (canonical), `board_status` (the board's own name),
`priority`, `assignees`, `url` and `custom_fields`.

`key` is what goes into a branch name, a spec file name and the work clock:
it has the shape `PREFIX-123`. A task with no key is reported with an empty
`key`; a flow then uses `task_id` and says so.

On `STATUS: error` the block carries an `ERROR:` line. Report it to the
developer and stop — or, in an autonomous flow, bail out. Never retry the same
call hoping for a different answer.

On `STATUS: unsupported` the block carries `CAPABILITY: <name>`: the configured
tracker cannot do what was asked. It is not a failure of the call. The calling
flow skips that step, says so in one line, and goes on — it never improvises the
step another way.

## Resolving the provider and the task list

The tracker is a project choice, written by the setup in `.claude/tracker.json`
(no credentials in it — it is tracked):

```json
{
  "provider": "clickup",
  "lists": ["901214692298"],
  "status": {
    "backlog": "backlog", "ready": "sprint", "in_progress": "in progress",
    "in_review": ["code review", "in review"], "done": "done", "blocked": "blocked"
  }
}
```

Resolve it in this order — the first that answers wins:

1. the environment: `TRACKER_PROVIDER`, and `TRACKER_LIST_ID` for the list;
2. `.claude/tracker.json` at the root of the repository;
3. the values the `tracker` skill states as "configured at install time" — load
   that skill if it is not in context. The install-time values reach a session
   only there, substituted into the skill's text: no Bash command and no file
   read can see them. An empty value, or one still showing the unexpanded
   `${user_config.…}` placeholder, means not configured;
4. a project configured before `tracker.json` existed: `CLICKUP_SETUP_LIST_ID`
   in the environment, then the install-time one the `tracker` skill states,
   means **ClickUp with that list**, the board's default status names — exactly
   what it meant before. Nothing has to be re-run for it;
5. nothing → the provider is `none`.

`bash "${CLAUDE_PLUGIN_ROOT}/scripts/tracker-config.sh" --json` answers steps 1,
2, the environment half of 4, and 5 in one call (`PROVIDER`, `LIST_ID`, `LISTS`,
`SOURCE`: `env`, `file`, `legacy` or `none`); only the install-time values are
left to the model. **Do not read the project's `.env` for this.** Reads of that
file are open, but one list id does not justify pulling a file of secrets into
the context window.

**Provider `none`.** No tracker: a flow that starts from a task id says it has
no tracker to read it from and stops; a flow that can run from a description
(`quick`, `kickoff`) runs without a board and writes nothing to one. A flow that
needs a list and has none says so and stops: the fix is for the developer to run
the setup, or to export `TRACKER_PROVIDER` and `TRACKER_LIST_ID`.

## Canonical statuses and transitions

The flows speak six statuses. Each board names them its own way, and
`.claude/tracker.json` maps one onto the other; the adapter carries the default
map for its tracker.

| Canonical | Meaning |
|---|---|
| `BACKLOG` | not planned; a flow never picks it up or moves it on its own |
| `READY` | planned, ready to be picked up (a ClickUp sprint list, Linear's Todo) |
| `IN PROGRESS` | someone is working on it |
| `IN REVIEW` | the PR/MR is open, waiting for a reviewer |
| `DONE` | merged |
| `BLOCKED` | an automated run gave up; a human has to resolve the blocker |

```
BACKLOG  -- the backlog gate -->  IN PROGRESS
READY  ->  IN PROGRESS  ->  IN REVIEW  ->  DONE
   |            ^  |
   |            |  v
   +--------- BLOCKED  (until a human resolves the blocker)
```

The agent validates the transition and refuses an invalid one, so ask for the
transition the flow is actually at: `READY -> IN PROGRESS` when work starts,
`IN PROGRESS -> IN REVIEW` when the PR/MR is open, `-> BLOCKED` on a bail-out,
`BLOCKED -> READY` on recovery. `BACKLOG -> IN PROGRESS` is requested only as
the recorded answer to the backlog gate below — never on the flow's own
initiative.

A canonical status can map to more than one board name (`in_review: ["code
review", "in review"]`): the agent tries them in order and moves the task to the
first one the board has.

## The work clock

Two of those transitions bracket the work, so they bracket the clock too. A
script holds the reading in between — every flow calls it at both ends:

| At the move to | Call | What comes back |
|---|---|---|
| `IN PROGRESS` | `task-clock.sh --task <key> --start --json` | `STARTED_AT`. Already open, it reports `already-running` and keeps the first stamp — a resumed task does not restart its clock |
| `IN REVIEW` / `BLOCKED` | `task-clock.sh --task <key> --stop --json` | `COMMENT`: the line to post, already written |

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

`BACKLOG` holds work nobody planned. No flow picks a backlog task up on its
own: `filter` and `next-task` read `READY`, so a backlog task only ever arrives
as an id the developer typed. When a `read` comes back with `status: BACKLOG`,
stop — before any branch, spec or board write — and ask:

```json
AskUserQuestion({
  "questions": [{
    "question": "<key> is in BACKLOG — it was never planned. Implement it anyway?",
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
exactly as if the task had been in `READY`. **Leave it** ends the flow with
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
