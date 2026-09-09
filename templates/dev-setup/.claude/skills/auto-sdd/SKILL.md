---
name: auto-sdd
description: Launches the autonomous SDD workflow for one task — spec, three adversarial challenges, test-first development in an isolated worktree, the project own quality commands — and opens the merge request behind a confirmation. Use when a tracked task should go from the board to a review-ready merge request with no supervision.
effort: medium
user-invocable: true
disable-model-invocation: true
---

# Auto SDD

The launcher of the `auto-sdd` workflow. The orchestration lives in
`workflows/auto-sdd.js` — JavaScript the harness runs, so its bounds are bounds
and its control flow never enters the context. What is left here is what code
cannot do: resolve the task, launch the run, act on what comes back.

**Usage**: `/dev-setup:auto-sdd [TASK_ID]`. For several tasks at once,
`multi-sdd` composes this same workflow.

## Before you start

- **`${CLAUDE_PLUGIN_ROOT}/reference/run-outcomes.md`** — the three outcomes,
  the merge request, the bail-out, the resume, the worktree left behind.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents, the
  transitions, the list id.

## 1. The task

**With a task id in `$ARGUMENTS`**: `INTENT: read`, `PARAMS: task_id: <id>`.

**Without one**: resolve the list id as the contract describes, then
`INTENT: next-task`, `PARAMS: list_id: <CLICKUP_SETUP_LIST_ID>` — the
highest-priority `SPRINT` task. Nothing in `SPRINT` → say so and stop: no run,
no board write.

Keep `custom_id`, `name`, `description` (verbatim), `url` and `task_id`.

## 2. The project context

Two read-only calls:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" --json
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

The base branch is neither guessed nor hard-coded — the second call answers it:

- `TASK_ID` empty → the session sits on a long-lived branch, `BRANCH` is the base;
- `TASK_ID` present → it sits on a task branch already, `BASE_BRANCH` is.

Then `INTENT: update`, `PARAMS: task_id: <task_id>, status: IN PROGRESS`.

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
    "baseBranch": "<the base from step 2>",
    "stack": { "lint": "<LINT_CMD>", "typecheck": "<TYPECHECK_CMD>", "test": "<TEST_CMD>" }
  }
})
```

`branchType` follows the task: feature → `feat`, bug → `fix`, maintenance →
`chore`. A command `detect-stack.sh` left empty stays empty — the workflow skips
it rather than inventing one.

The harness asks the developer to approve the workflow script before it runs —
the checkpoint this flow keeps, and why it needs no `AskUserQuestion`. The run
then works in the background: wait for its notification, never poll.

## 4. The outcome

Exactly one of `needs-human`, `ready-for-mr` or `failed`, each handled in
`${CLAUDE_PLUGIN_ROOT}/reference/run-outcomes.md`, which also holds what the
merge request carries and how an answered `needs-human` resumes. Anything else
means the run broke: show the raw result and stop.

## Expected output

- the task moved `SPRINT` → `IN PROGRESS`, then → `CODE REVIEW` or `BLOCKED`;
- on `ready-for-mr`, a pushed branch and a merge request against the project
  base branch, carrying the spec and the real test output;
- otherwise the objections or the failing output in chat, with the branch and
  the worktree left in place;
- either way, no edit in the developer checkout.
