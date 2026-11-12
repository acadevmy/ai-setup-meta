# The task on the board

Work that starts from an idea still belongs on the board: without a task it has
no history, no clock and no place in the plan. So kickoff offers to create
one, and on a yes the work continues exactly as if it had started from `sdd`.

## When to ask

Resolve the provider and the list as the tracker contract's "Resolving the
provider and the task list" describes. A tracker and a list → the
classification call of step 2 carries one more question. Provider `none`, or no
list → no question, no stop: the summary says `Board: no tracker configured, no
task created`.

```json
{
  "question": "Create the task on <the provider> for this work?",
  "header": "Board",
  "options": [
    { "label": "Yes, create it (Recommended)", "description": "The branch carries its id, the task moves to IN PROGRESS and its clock starts" },
    { "label": "No task", "description": "A spike, or work the board does not track" }
  ],
  "multiSelect": false
}
```

A release branch gets no task of its own: each piece gets one, when its run of
kickoff comes.

## On a yes

Before the branch exists, through the `tracker` agent:

1. `INTENT: create`, `PARAMS: list_id: <LIST_ID>, name: <title>,
   description: <the Discovery Summary, in full>`. The title is in the team's
   language, the `LANGUAGE` that `mr-meta.sh --json` returns. On `STATUS:
   error`, say so and carry on with no task — the work is not blocked by the
   board.
2. Keep `key`, `task_id` and `url`. From here the work is a tracked task:
   - **the `sdd` route** — `sdd-start.sh` with `--task <key>`, then
     `INTENT: update` to `IN PROGRESS` and `task-clock.sh --task <key>
     --start`, as `sdd`'s intake step 3 does. The yes to this question is the
     developer's answer for that move, whatever status the list gives a new
     task. Then `sdd-spec` with the task id;
   - **under `quick`'s bar** — end with `Next: /dev-setup:quick <key>`:
     `quick` moves the task and starts its clock. When the list puts new tasks
     in `BACKLOG`, its backlog gate asks once more.

The summary says `Board: <key> created (<url>)`.

## On a no

Nothing on the board, and the flow is the one in `SKILL.md`. The summary says
`Board: no task, by choice`.
