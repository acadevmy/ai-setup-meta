# Phases B and C — the fan-out and the outcomes

Phase A is over: every task has been triaged, its open business decisions are
answered and appended to its description, and the overlap warning has been shown.
From here nothing asks the developer anything until a run comes back.

## Index

- [The project context, read once](#the-project-context-read-once)
- [The launch](#the-launch)
- [The ledger](#the-ledger)
- [Outcomes as events](#outcomes-as-events)
- [The status view](#the-status-view)
- [What no background run does](#what-no-background-run-does)

## The project context, read once

The stack and the base branch belong to the project, not to the task, so they are
resolved once in the main checkout and shared by every run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" --json
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

The base branch comes from the second call and is never guessed: `TASK_ID` empty
means the session sits on a long-lived branch and `BRANCH` is the base; `TASK_ID`
present means it sits on a task branch and `BASE_BRANCH` is. Getting this wrong
costs `n` branches carrying the whole `main..next` delta, not one.

## The launch

One `Workflow` call per task, **all in the same message** so they start together
rather than in a queue:

```json
Workflow({
  "name": "dev-setup:auto-sdd",
  "args": {
    "taskId": "<custom_id>",
    "title": "<name>",
    "description": "<description + the Answered at pre-flight block>",
    "url": "<url>",
    "branchType": "feat",
    "pluginRoot": "${CLAUDE_PLUGIN_ROOT}",
    "baseBranch": "<the base resolved above>",
    "stack": { "lint": "<LINT_CMD>", "typecheck": "<TYPECHECK_CMD>", "test": "<TEST_CMD>" }
  }
})
```

Move each task `SPRINT → IN PROGRESS` — `INTENT: update` — as you launch it, and
not before: the pre-flight deliberately leaves the board alone so that a dropped
task is never touched.

`branchType` follows the task — feature → `feat`, bug → `fix`, maintenance →
`chore`. Each call returns immediately with a `runId`; the run itself works in
the background, in a worktree the harness gives its dev agent, so the developer
checkout never moves whatever the five runs are doing.

The harness asks the developer to approve each workflow launch, so `n` tasks is
`n` approvals up front. That is the last thing they are asked before the runs go.

Nothing else goes in these calls. Every argument is something phase A resolved
or a script reported, and the workflow is the same one `auto-sdd` launches for a
single task — this command adds no phase, no agent and no rule to it.

## The ledger

Print the table once at launch and keep it as the run of record:

| Task | Run | Branch / worktree | Last seen | Outcome |
|---|---|---|---|---|
| DE-1 | `<runId>` | — | Spec | — |

Record what each launch returned: the `runId`, and the transcript directory when
the result names one. Both are what makes a resume and a status answer possible
later; a lost `runId` means a `needs-human` can only be relaunched from scratch.

## Outcomes as events

A notification arrives per run, in whatever order the runs finish. Handle each
one **as it lands**, on its own, through
`${CLAUDE_PLUGIN_ROOT}/reference/run-outcomes.md` — `ready-for-mr` pushes and
opens the merge request behind the `ask` rule, `failed` reports the real output
and blocks the task, `needs-human` shows the objections and asks.

Two rules make the parallelism worth anything:

- **Never wait for the set.** A run that finished is reported now. Holding four
  outcomes until the fifth lands turns a fan-out back into a queue.
- **A question is not a barrier.** A `needs-human` waiting on an answer stops
  that task and nothing else. When the answer comes, resume that one run with
  `resolved` and `guidance` as `run-outcomes.md` describes; the others carry on
  regardless, and their notifications may well arrive mid-question.

Update the ledger row every time one of these happens. It is the only place the
five runs are visible together.

## The status view

When the developer asks where things stand, answer from what you already have —
**do not poll a running workflow**:

- the ledger, for what each run was last seen doing;
- `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-info.sh" --json`, for the
  worktrees and branches that actually exist on disk right now;
- `<transcriptDir>/journal.jsonl` of a run, when its launch named one — it
  records each agent call that has completed, so the last entry is the phase the
  run is past.

Then name `/workflows` in the terminal: that is the live phase tree, it updates
without spending a turn, and it belongs to the developer rather than to this
chat. Reporting a phase you did not observe is worse than reporting the ledger
and saying what it does not know.

## What no background run does

The workflow pushes nothing, opens nothing and never writes to the board — by
design, so that everything outward-facing happens here, where the `ask` rules put
a person in front of it.

That rule fires per command, and it stays that way: five merge requests are five
confirmations. Do not batch them behind one question, and do not ask for a
combined go-ahead in chat first — the real `gh pr create` / `glab mr create` is
the checkpoint, and a summary of five of them is not.
