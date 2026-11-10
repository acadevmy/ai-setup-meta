# The task on the board

Work that starts from an idea still belongs on the board: without a task it has
no history, no clock and no place in the sprint. So kickoff offers to create
one, and on a yes the work continues exactly as if it had started from `sdd`.

## When to ask

Resolve `CLICKUP_SETUP_LIST_ID` as the ClickUp contract's "Resolving the task
list id" describes. Found → the classification call of step 2 carries one more
question. Not found → no question, no stop: the summary says `Board: no list
configured, no task created`.

```json
{
  "question": "Create the task on ClickUp for this work?",
  "header": "Board",
  "options": [
    { "label": "Yes, create it (Recommended)", "description": "The branch carries its id, the task moves to IN PROGRESS and its clock starts" },
    { "label": "No task", "description": "A spike, or work the board does not track" }
  ],
  "multiSelect": false
}
```

## On a yes

**One format on the board.** The task is written the way `story` writes one,
so `sdd` and `quick` read it the same way whoever wrote it, and its scenarios
become the spec's requirements (`parse-story.sh`). From
`${CLAUDE_PLUGIN_ROOT}/skills/story/reference/templates.md`:

- a `feat` is a **User Story** — the Connextra sentence, the outcome, two to
  five scenarios — `task_type: User Story`;
- a `fix` or a `chore` is a **Task** — the outcome and its acceptance criteria
  — with the default type.

Write it from the Discovery Summary, in the story language (`product.md`, or
the `LANGUAGE` that `mr-meta.sh --json` returns). It carries no **Open
points**: what the discovery left open goes in the spec, not on the board.

1. **Draft and check it.** One draft, `.stories/kickoff-<slug>/US-01.md` (or
   `TASK-01.md`), frontmatter with `id`, `title`, `type` and `products` when
   `product.md` indexes them — gitignored as `templates.md` says — then:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-story.sh" --json .stories/kickoff-<slug>
   ```

   Fix every error. No reviewer agent and no approval of its own: the yes to
   this question is the approval, and the spec review comes next anyway.
2. **Create it**, before the branch exists, through the `clickup` agent:
   `INTENT: create`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>, name: <title>,
   description: <the draft's body, after its frontmatter>, task_type: <as
   above>, tags: <products>`. On `STATUS: error`, say so and carry on with no
   task — the work is not blocked by the board. Then delete the draft folder.
3. Keep `custom_id`, `task_id` and `url`. From here the work is a tracked task:
   - **the `sdd` route** — `sdd-start.sh` with `--task <custom_id>`, then
     `INTENT: update` to `IN PROGRESS` and `task-clock.sh --task <custom_id>
     --start`, as `sdd`'s intake step 3 does. The yes to this question is the
     developer's answer for that move, whatever status the list gives a new
     task. Then `sdd-spec` with the task id and the Discovery Summary;
   - **under `quick`'s bar** — end with `Next: /dev-setup:quick <custom_id>`:
     `quick` moves the task and starts its clock. When the list puts new tasks
     in `BACKLOG`, its backlog gate asks once more.

The summary says `Board: <custom_id> created (<url>)`.

## On a no

Nothing on the board, and the flow is the one in `SKILL.md`. The summary says
`Board: no task, by choice`.
