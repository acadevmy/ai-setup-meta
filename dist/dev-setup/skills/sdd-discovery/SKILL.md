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

- **`reference/question-bank.md`** — how to ask (closed-first, worked examples),
  the four phases to cover, how hard to push, and the exact shape of the
  Discovery Summary. Read it before the first question.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — the rule for every
  interactive step: after you ask, the turn ends. This interview is the case it
  was written for.
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

Let's start the discovery phase. I'll ask you some questions to thoroughly
understand what needs to be implemented. Answer with whatever level of detail
you prefer. If you don't have an answer for something yet, just say "to be defined".
```

### 4. Run the interview

Work through the four phases of `question-bank.md`, one question at a time,
`AskUserQuestion` every time, ending your turn after each. Stop when the phases
are covered, when the developer says they are done, or at the 10–12 question
soft cap.

### 5. Write the Discovery Summary

Fill in the template from `question-bank.md`. Gray areas are recorded, not
resolved: an unanswered question is information the spec needs.

### 6. Close

Show the summary. Invoked by the orchestrator, hand control back so the spec can
be generated. Invoked on its own, ask whether to proceed to the spec.

## Expected output

- an interview of at most 10–12 questions, each answered by the developer;
- a structured Discovery Summary in the conversation context;
- gray areas documented explicitly.
