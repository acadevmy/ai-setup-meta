---
name: sdd-dev
description: Implements an approved spec step by step, checking tests and lint after each step. Use when a spec is approved and its implementation plan has to be carried out.
effort: high
user-invocable: false
disable-model-invocation: false
---

# SDD dev

Develop a feature by following the implementation plan of an approved spec. The
spec is the contract: this skill executes it, it does not redesign it.

**Input**: `SPEC_REF` — a path such as `.specs/DE-123-add-auth.md`, or a custom
id such as `DE-123`.

## Before you start

- **`reference/methodologies.md`** — the cycle each layer works in, and the
  test/lint check that closes every step. Which cycle is not a question you ask:
  the `tests.md` rule fixes it per layer, and that reference is how to run it.

## Procedure

### 1. Load the spec

A path is read directly; a custom id is looked up as `.specs/<customId>-*.md`.
If the file does not exist, say so and stop.

**Check the status.** If it is not `approved`, warn the developer:

```
Warning: the spec is not yet approved (status: <status>).
Do you want to proceed with development anyway?
```

Without a confirmation, stop.

### 2. Break the plan into tasks

Parse `## Implementation plan` from the spec. One task per step, in order, each
with its number, description and the files it touches. Show the breakdown, then
start on it:

```
Task breakdown from spec:
[ ] 1. <Step 1> — <involved files>
[ ] 2. <Step 2> — <involved files>
```

Do not ask the developer to confirm the breakdown or its order: the plan was
approved as a whole at the flow's one checkpoint, and re-litigating it here was
a second approval wearing a different hat. A step you cannot carry out as
written is a different case — say which and why, and stop.

### 3. Execute the steps

For each step, in the plan's order:

1. **Announce** it: `Step <N>/<total>: <description>`.
2. **Read the docs** when the step touches a library: prefer the `ctx7` CLI
   (`ctx7 library <name>`, then `ctx7 docs <libraryId> <query>`), falling back
   to the Context7 MCP.
3. **Implement** it following `reference/methodologies.md`.
4. **Check** it — the test and lint commands from that same reference.
5. **Update** the breakdown, marking what is done and what is in progress.

### 4. Summary

```
Development completed for spec: <customId> — <title>

Steps completed: <N>/<total>
Files created: <list>
Files modified: <list>
Tests: <result>
Linter: <result>
```

Hand control back without committing, simplifying or touching the spec's status:
the flow's closure stages the work, runs `simplify` once, verifies against the
spec and produces a single commit. Doing any of it here is what made a task cost
four commits and two `simplify` runs.

## Expected output

- the code implemented as the approved spec describes;
- tests and linter run, and passing;
- nothing committed and nothing pushed.
