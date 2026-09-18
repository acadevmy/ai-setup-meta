---
name: sdd-spec
description: Turns a task and its discovery summary into a technical specification with an ordered implementation plan, written to .specs/. Use when a task's requirements are gathered and the implementation has to be designed before any code is written.
effort: max
user-invocable: false
disable-model-invocation: false
---

# SDD spec

Produce the technical specification and implementation plan for a task, as
`.specs/<customId>-<slug>.md` with status `draft`. The orchestrator (`sdd`)
invokes this skill with the task context and the Discovery Summary already in
the conversation; on its own, it takes a task id.

## Before you start

- **`reference/spec-template.md`** — the document's exact sections and the rules
  for filling them in. The spec is written from that template, not from memory.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — only when a task
  id has to be resolved.

## Procedure

### 1. Get the task context

With a task id in `$ARGUMENTS`, read the task through the `clickup` agent
(`INTENT: read`) and extract `custom_id`, `name`, `description`, `priority`,
`task_id`, `url`. On `STATUS: error`, report it and stop.

Without one, use the context the orchestrator passed. If there is none, ask the
developer for a task id.

### 2. Analyze the project

- read the rules in `.claude/rules/` — the technical constraints that apply;
- read `REGISTRY.md` — existing components, adopted patterns, past decisions;
- find the files the requirements touch;
- check `.specs/` for a spec that already covers this task.

### 3. Make sure discovery happened

A Discovery Summary in the conversation is the input. If one is there, use it and
do not repeat the interview. If it is not, invoke the `sdd-discovery` skill with
the task context and wait for it to finish.

**Do not generate the spec without a Discovery Summary.** Requirements invented
at this stage are the ones that get discovered wrong during development.

### 4. Write the spec

```bash
mkdir -p .specs
```

`<slug>` is a short kebab-case form of the task title. Fill in every section of
`reference/spec-template.md`.

### 5. Show it

```
Spec generated: .specs/<customId>-<slug>.md
Status: draft

<spec content>
```

## Expected output

- `.specs/<customId>-<slug>.md` created with status `draft`;
- the spec shown in full to the developer.
