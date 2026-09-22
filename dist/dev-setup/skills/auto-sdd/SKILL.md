---
name: auto-sdd
description: Launches the autonomous SDD workflow for one task — spec, three adversarial challenges, test-first development in an isolated worktree, the project own quality commands — and opens the merge request behind a confirmation. Use when a tracked task should go from the board to a review-ready merge request with no supervision.
effort: medium
user-invocable: true
disable-model-invocation: true
---

# Auto SDD

The launcher of the `auto-sdd` workflow. The orchestration lives in
`workflows/auto-sdd.js`, JavaScript the harness runs: its bounds are bounds and
its control flow never enters the context. What is left here is what code cannot
do — the task, the launch, the outcome.

**Usage**: `/dev-setup:auto-sdd [TASK_ID]`. For several tasks, `multi-sdd`
composes it.

## Before you start

- **`${CLAUDE_PLUGIN_ROOT}/reference/run-outcomes.md`** — the three outcomes,
  the merge request, the bail-out, the resume.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents, the
  transitions, the backlog gate, the list id.
- **`${CLAUDE_PLUGIN_ROOT}/reference/fork-point.md`** — step 2's question.

## 1. The task

**With a task id in `$ARGUMENTS`**: `INTENT: read`, `PARAMS: task_id: <id>`.
`BACKLOG` → the contract's backlog gate.

**Without one**: resolve the list id as the contract describes, then
`INTENT: next-task`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>` — the
highest-priority `SPRINT` task.

A declined gate or an empty `SPRINT` stops the flow: no run, no board write.
Otherwise keep `custom_id`, `name`, `description` (verbatim), `url`, `task_id`.

## 2. The project context, and the fork point

Two read-only calls:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" --json
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

The second resolves the base branch; `fork-point.md` holds how to read it and
the question that confirms it. Ask before the board write below — a run the
developer walks away from leaves the task where it was.

Then `INTENT: update`, `PARAMS: task_id: <task_id>, status: IN PROGRESS`, then
the clock:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-clock.sh" --task <custom_id> --start --json
```

## 3. The run

```json
Workflow({
  "name": "dev-setup:auto-sdd",
  "args": {
    "taskId": "<custom_id>",
    "title": "<name>",
    "description": "<description, verbatim>",
    "url": "<url>",
    "branchType": "feat",
    "pluginRoot": "${CLAUDE_PLUGIN_ROOT}",
    "baseBranch": "<the ref confirmed in step 2>",
    "stack": { "lint": "<LINT_CMD>", "typecheck": "<TYPECHECK_CMD>", "test": "<TEST_CMD>" }
  }
})
```

`branchType` follows the task: feature → `feat`, bug → `fix`, maintenance →
`chore`. A command `detect-stack.sh` left empty stays empty — the workflow skips
it rather than inventing one.

The harness asks the developer to approve the workflow script before it runs.
That and the fork point are this flow's two stops — plus step 1's backlog gate
when it applies. The run then works in the background: wait for its
notification, never poll.

## 4. The outcome

Exactly one of `needs-human`, `ready-for-mr` or `failed`, each handled in
`${CLAUDE_PLUGIN_ROOT}/reference/run-outcomes.md`. Anything else means the run
broke: show the raw result and stop.

## Expected output

- the task moved `SPRINT` → `IN PROGRESS` → `CODE REVIEW` or `BLOCKED`;
- on `ready-for-mr`, a pushed branch and a merge request carrying the spec and
  the real test output;
- otherwise the objections or the failing output, with the branch and the
  worktree left in place;
- either way, no edit in the developer checkout.
