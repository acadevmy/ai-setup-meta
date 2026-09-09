---
name: auto-sdd
description: Runs the whole Spec-Driven Development flow for a task end to end with no human checkpoints — discovery, spec, approval, development, gates, merge request — replacing each checkpoint with an agent. Use when a task should be taken from the board to an open merge request without supervision.
effort: max
user-invocable: true
disable-model-invocation: true
---

# Auto SDD

The `sdd` flow with the human taken out of it: from task selection to an open
merge request, with no `AskUserQuestion` directed at a person. Each interactive
checkpoint is replaced by an agent or by a documented deterministic rule.

**Invoking this skill *is* auto-mode** — it is not a flag, it is what the skill
does. The supervised flow stays available as `sdd`.

**Usage**: `/dev-setup:auto-sdd [TASK_ID]`. With a task id it processes that
task; without one it takes the next `SPRINT` task from the configured list.

## Before you start

- **`reference/auto-mode.md`** — every step, its agents and its parameters, and
  the bail-out.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents, the
  transitions, and how the task list id is resolved.

## The rules of auto-mode

- **No `AskUserQuestion`, anywhere.** Every decision goes through an agent or a
  rule written down in the reference.
- **The turn discipline of the interactive skills does not apply.** There is no
  human waiting, so an "incomplete work" signal means the work really is
  incomplete: finish the step or bail out.
- **Every loop is bounded.** Reaching a bound without convergence is a bail-out,
  not a reason to keep going.
- **The SDD skills are not modifiable.** This flow orchestrates `sdd-spec`,
  `sdd-dev`, `verify`, `simplify` and `review`; it does not change how they
  work. `sdd-discovery` and `sdd-plan` must **not** be invoked at all — they are
  interactive, and their outputs are produced by step 4 and by the approver
  agent instead.

| Loop | Bound |
|---|---|
| discovery questions | 12 |
| spec review iterations | 3 |
| plan review iterations | 3 |
| re-entries after a `verify` fail | 3 |

## The flow

Steps 1 to 12, all detailed in `reference/auto-mode.md`: task selection →
branch → status `IN PROGRESS` → two-agent discovery → spec → spec approval →
plan approval → methodology → development → simplify, verify, review → push and
merge request → status `CODE REVIEW`.

## Expected output

- a branch named after the task's custom id;
- a spec in `.specs/`, status `implemented`;
- code that follows the approved spec, simplified, verified against it and
  rule-compliant;
- `REGISTRY.md` updated;
- the task moved `SPRINT` → `IN PROGRESS` → `CODE REVIEW`;
- a merge request linking the task and the spec;
- no `AskUserQuestion` invoked anywhere in the run.
