# The stop point — how far the flow goes

Before the branch is cut, the developer picks where this run ends: after the
spec, after the code, or at one of the closure's steps. The full flow, up to the
merge request, is the default. Whatever the stop point, intake runs in full —
the branch is cut, the task moves to `IN PROGRESS`, the clock starts — because
every stop point leaves work on a branch that belongs to a task in progress.

## Index

- [The six stop points](#the-six-stop-points)
- [The question](#the-question)
- [Saving the answer](#saving-the-answer)
- [Where the flow checks it](#where-the-flow-checks-it)
- [Ending at a stop point](#ending-at-a-stop-point)
- [Resuming](#resuming)

## The six stop points

Each one does everything the one above it does, plus its own row.

| Stop point | `--stop` | What runs | What it leaves |
|---|---|---|---|
| **Spec** | `spec` | Steps 5–7: discovery, the technical spec, its approval | the spec in `.specs/`, `approved`, not committed |
| **Development** | `development` | Step 8: `sdd-dev` implements the plan, with its tests and lint | the code and the spec in the working tree, nothing staged |
| **Review** | `review` | Closure 1–5: stage, `simplify`, `verify`, `review` + REGISTRY, the summary | everything staged, nothing committed, the spec still `approved` |
| **Commit** | `commit` | Closure 6: the spec to `implemented`, the one commit, with the commit hook as the gate | one local commit, nothing pushed |
| **Push** | `push` | Closure 7: `git push -u origin <branch>` | the branch on the remote, no merge request |
| **Merge request** *(default)* | `merge-request` | Closure 8–9: the merge request, the clock stopped, the task to `CODE REVIEW` | the whole flow |

Review comes before the commit because that is where the gates run: the code,
the spec and the REGISTRY entries land in one commit, and a review after the
push would need a second one.

Every stop point before **Merge request** leaves the task in `IN PROGRESS` with
its clock running — the clock measures from `IN PROGRESS` to the merge request,
and that merge request has not happened yet.

## The question

Asked in intake step 2, **in the same `AskUserQuestion` call as the fork point**
— the fork point first, these two after it — so launching costs one stop.
Six stop points do not fit in one question (four options at most), so they are
split by phase: the second question only matters when the first one is
`Closure`.

```json
{
  "question": "How far should this run go?",
  "header": "Stop point",
  "options": [
    { "label": "Closure (Recommended)",
      "description": "Spec, development, then the closure — the next question says how far into it" },
    { "label": "Spec only",
      "description": "Discovery, the spec and its approval. Stops with the approved spec uncommitted: no code" },
    { "label": "Development",
      "description": "Spec, then the implementation with its tests and lint. Stops with the code uncommitted, nothing staged" }
  ],
  "multiSelect": false
},
{
  "question": "If the run reaches the closure, where should it stop?",
  "header": "Closure",
  "options": [
    { "label": "Merge request (Recommended)",
      "description": "Gates, one commit, push, the merge request; the clock stops and the task moves to CODE REVIEW" },
    { "label": "Push",
      "description": "Gates, one commit and the push. No merge request: the task stays IN PROGRESS" },
    { "label": "Commit",
      "description": "Gates and the one commit, through the commit hook. Nothing pushed" },
    { "label": "Review",
      "description": "Stage, simplify, verify, review and REGISTRY. Everything staged, nothing committed" }
  ],
  "multiSelect": false
}
```

**End the turn on the tool call.** On a resume the question is normally not
asked at all — see the next section.

## Saving the answer

The answer travels as `--stop <value>` (the column in the table above) on the
`sdd-start.sh --create` call that cuts the branch. The script saves it beside
the task clock, where `/clear` does not reach it, and every later call for the
task returns it as `STOP_POINT`.

On a resume (`BRANCH_EXISTS: true`), intake reads `STOP_POINT`:

| `STOP_POINT` | `--stop` in `$ARGUMENTS` | The run |
|---|---|---|
| set | no | uses it, **without asking**, and shows it in the brief |
| any | yes | uses the argument, and saves it with `--create --stop <value>` |
| empty | no | asks the two questions on their own, in one call, and saves the answer with `--create --stop <value>` — a branch cut before the stop point was saved |

Changing your mind is `/dev-setup:sdd <id> --stop <value>`: asking on every
resume cost a click each time to protect the rarer case, which an argument
covers.

## Where the flow checks it

- **Spec** → end after step 7, once `sdd-plan` reports the spec approved.
- **Development** → end on `sdd-dev`'s summary, instead of going on to step 9.
- **Review**, **Commit**, **Push** → run `reference/closure.md` up to and
  including that step (5, 6 or 7), then end.
- **Merge request** → the closure runs to the end, as it always has.

A stop point is not a question: when the run reaches it, it ends — do not ask
whether to go on.

## Ending at a stop point

End on the report of the step that ran last — `sdd-plan`'s approval, `sdd-dev`'s
summary, the closure summary — followed by the state the run leaves:

```
Stopped at: Commit — DE-123 — Task title

Branch:  feat(auth)/DE-123_add-user-auth  (base: origin/next)
Spec:    .specs/DE-123-<slug>.md (implemented)
Git:     1 commit, not pushed       ← or: staged / uncommitted, from git status
Task:    IN PROGRESS, clock still running

Resume:  /dev-setup:sdd DE-123
```

## Resuming

Re-running `/dev-setup:sdd <id>` is the resume, and it needs no special path:
intake finds the branch, reads the saved stop point, and step 4 starts from
what is on disk. What each stop point leaves maps onto an existing row:

| Left by | Step 4 reads | Starts at |
|---|---|---|
| Spec | `approved`, no `CHANGED_FILES` beyond the spec | step 8, `sdd-dev` |
| Development, Review | `approved` with `CHANGED_FILES` | the "is the implementation complete?" question, then step 9 from closure 1 — the gates run again over the full change |
| Commit, Push | `implemented` | step 9 at closure 7 — the commit exists; skip the push too when `git status -sb` shows the branch level with its upstream |

When the stop point in force on resume is one the branch has already passed — the
**Spec** stop point on a branch that already has code — say so and end at the
brief: the run has nothing to do.

A merge request opened by hand after an early stop is still caught: the
merge-request hook names the task whose clock is still open.
