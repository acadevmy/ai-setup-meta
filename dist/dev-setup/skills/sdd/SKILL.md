---
name: sdd
description: Runs the interactive Spec-Driven Development flow for a task — discovery, spec, approval, development, gates, merge request — stopping at each checkpoint for the developer. Use when starting work on a tracked task that should go through spec and review rather than straight to code.
effort: medium
user-invocable: true
disable-model-invocation: true
allowed-tools: AskUserQuestion
---

# SDD

Take a task from the board to an open merge request, **interactively**: a spec,
a plan, and a checkpoint at every decision the developer owns — task choice,
discovery, spec approval, methodology, the final OK. For the same flow without
those checkpoints, use `auto-sdd`.

**Usage**: `/dev-setup:sdd [TASK_ID]`. With a task id (e.g. `DE-123`) it reads
that task; without one it lists what is in `SPRINT` and asks.

## Before you start

- **`reference/intake.md`** — steps 1–4: task selection, the working branch,
  the status update, the brief.
- **`reference/closure.md`** — step 10: commit, simplify, verify, review, push,
  merge request, closing the task and the spec.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — this flow stops for
  the developer four times; that file is the rule for all four.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents, the
  transitions and how the task list id is resolved.

## The flow

| # | Step | Where |
|---|---|---|
| 1–4 | Task selection, branch, status → IN PROGRESS, brief | `reference/intake.md` |
| 5 | Discovery — the structured interview | the `sdd-discovery` skill |
| 6 | Technical spec in `.specs/<customId>-<slug>.md` | the `sdd-spec` skill |
| 7 | Spec review and approval — **checkpoint** | the `sdd-plan` skill |
| 8 | Methodology choice — **checkpoint** | below |
| 9 | Development against the approved plan | the `sdd-dev` skill |
| 10 | Quality, review, merge request | `reference/closure.md` |

Steps 5, 6, 7 and 9 are sub-skills: invoke each one by name, passing the task
context, and wait for it to finish before moving on. They are not user-invocable
— this flow is their entry point.

Step 7 is a hard stop: nothing runs until the developer approves the spec.

## Step 8 — Methodology

After the spec is approved:

```json
AskUserQuestion({
  "questions": [{
    "question": "Which development methodology do you want to use?",
    "header": "Methodology",
    "options": [
      { "label": "TDD (Recommended)", "description": "Red-Green-Refactor — for backend, business logic, APIs, services." },
      { "label": "BDD", "description": "Given/When/Then — for frontend, UI components, user flows." },
      { "label": "None", "description": "Direct development, without a test-first cycle." }
    ],
    "multiSelect": false
  }]
})
```

End the turn on the tool call, and pass the answer to `sdd-dev`.

## Expected output

- a branch named after the task's custom id;
- a spec in `.specs/`, status `implemented`;
- code that follows the approved spec, verified against it, simplified and
  rule-compliant;
- `REGISTRY.md` updated;
- the task moved `SPRINT` → `IN PROGRESS` → `CODE REVIEW`;
- a merge request linking the task and the spec.
