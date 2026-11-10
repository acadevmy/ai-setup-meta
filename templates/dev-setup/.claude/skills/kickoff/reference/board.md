# The task on the board

Work that starts from an idea still belongs on the board: without a task it has
no history, no clock and no place in the sprint. So kickoff offers to create
one, and on a yes the work continues exactly as if it had started from `sdd`.

**Repository first.** The spec is the source, and it lives in the repository;
the task points at it and never becomes a second copy. How much the task says
on its own depends on whether it stands alone.

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

For a release the question is the same and creates the **release task**, the
parent of the pieces' tasks; a piece's run, which already has its parent,
creates its own task without asking.

## Index

- [What the task says](#what-the-task-says)
- [On a yes](#on-a-yes)
- [Pointing the task at the spec](#pointing-the-task-at-the-spec)
- [On a no](#on-a-no)

## What the task says

Written in the team's language, the `LANGUAGE` that `mr-meta.sh --json`
returns. Every body ends with the **Spec** line, filled in once the spec exists
(below).

| Task | Body |
|---|---|
| **feat or fix, single branch** — it stands alone, so it says more | **Goal** (two or three sentences, from the Discovery Summary's context), **Acceptance criteria** (the requirements, one verifiable line each), **Out of scope**, **Spec** |
| **chore, single branch** | **Goal** in one or two sentences, **Spec** |
| **release** — the parent | **Goal** of the release in two or three sentences, **Pieces** (one line each, its title), **Spec** — the release spec |
| **piece of a release** — a subtask | one line on what the piece delivers, **Depends on** (the pieces, by title), **Spec** — the release spec and the piece's row in its `## Pieces` table, plus the piece's own spec once its run writes it |

Never the whole Discovery Summary, never the implementation plan: those are in
the spec, and a copy on the board goes stale the first time the spec changes.

## On a yes

Before the branch exists — the branch carries the task's id — through the
`clickup` agent:

1. `INTENT: create`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>, name: <title>,
   description: <the body above, its Spec line reading "written in the
   repository once the branch exists">`. A piece adds `parent: <the release
   task's task_id>`, read from the `> Task:` line of the release spec. On
   `STATUS: error`, say so and carry on with no task — the work is not blocked
   by the board.
2. Keep `custom_id`, `task_id` and `url`. From here the work is a tracked task:
   - **the `sdd` route** (a single branch or a piece) — `sdd-start.sh` with
     `--task <custom_id>`, then `INTENT: update` to `IN PROGRESS` and
     `task-clock.sh --task <custom_id> --start`, as `sdd`'s intake step 3
     does. The yes to this question is the developer's answer for that move,
     whatever status the list gives a new task. Then `sdd-spec` with the task
     id;
   - **the release** — the release task stays in the status the list gives it,
     with no clock: its pieces carry the clocks and move through the board.
     `sdd-spec` gets its id, so the release spec's `> Task:` line names it
     and every piece finds its parent there. It is closed by a person, when the promotion merge request is
     merged;
   - **under `quick`'s bar** — end with `Next: /dev-setup:quick <custom_id>`:
     `quick` moves the task and starts its clock. When the list puts new tasks
     in `BACKLOG`, its backlog gate asks once more. `quick` writes no spec, so
     the Spec line says `none: quick` from the start.

The summary says `Board: <custom_id> created (<url>)`.

## Pointing the task at the spec

Once `sdd-spec` has written the file, one `INTENT: update`, `PARAMS: task_id:
<task_id>, description: <the same body, the Spec line filled in>`:

```
Spec: `.specs/<file>.md` on `<branch>` — <web url>/blob/<branch>/.specs/<file>.md
```

The web URL comes from `git remote get-url origin` (SSH → https, no `.git`);
GitLab writes `/-/blob/`. It is a branch link, not a permalink, so it follows
the spec as it changes, and it resolves once the branch is pushed. A piece
names both specs: the release's, with its row in `## Pieces`, and its own.

When the update fails, say so in one line and give the developer the Spec line
to paste: the work goes on.

## On a no

Nothing on the board, and the flow is the one in `SKILL.md`. The summary says
`Board: no task, by choice`.
