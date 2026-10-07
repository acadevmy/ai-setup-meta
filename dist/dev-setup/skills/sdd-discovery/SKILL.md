---
name: sdd-discovery
description: Runs a structured discovery interview that turns a raw task into a complete set of requirements. Use when a task needs its requirements, edge cases and constraints gathered before a technical spec is written.
effort: max
user-invocable: false
disable-model-invocation: false
---

# SDD discovery

Interview the developer about a task until there is enough material for a
structured **Discovery Summary** — the input the technical spec is built from.
Act as a Senior Product Manager and Lead System Architect: the goal is complete
requirements, not a filled-in form.

The orchestrator (`sdd`) invokes this skill with the task context already in the
conversation. Invoked on its own, it takes a task id.

## Before you start

- **`reference/question-bank.md`** — draft first, the question budget, how to
  ask (closed-first, a worked example), the four phases to cover, and the
  exact shape of the Discovery Summary. Read it before the first question.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — the rule for every
  interactive step: up to four related questions in one call, and after you
  ask, the turn ends.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — only when a task
  id has to be resolved.

## Procedure

### 1. Get the task context

With a task id in `$ARGUMENTS`, read the task through the `clickup` agent
(`INTENT: read`) and extract `custom_id`, `name`, `description`, `priority`,
`task_id`, `url`. On `STATUS: error`, report it and stop.

Without one, use the context the orchestrator passed. If there is none, ask the
developer for a task id.

### 2. Read the project context

- the rules in `.claude/rules/` — the technical constraints that apply here;
- `REGISTRY.md` — existing components, adopted patterns, past decisions;
- the files the task's requirements point at.

### 3. Present the task

```
Discovery for: <custom_id> — <name>
Priority: <priority>

Description from task:
<description>

Already covered by the task: <one line per phase it answers>
Asking only about the gaps.
```

### 4. Run the interview

Draft the Discovery Summary from the task and the project context first, then
ask what the draft leaves open, within the budget in `question-bank.md`. End
the turn on each call.

### 5. Write the Discovery Summary

Fill in the template from `question-bank.md`. Gray areas are recorded, not
resolved: an unanswered question is information the spec needs.

### 6. Close

Show the summary. Invoked by the orchestrator, hand control back so the spec can
be generated. Invoked on its own, ask whether to proceed to the spec.

## Expected output

- questions only on what the task left open, within the budget;
- a structured Discovery Summary in the conversation context;
- gray areas documented explicitly.
