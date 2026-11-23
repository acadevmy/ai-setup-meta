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

- **`reference/methodologies.md`** — the cycle each layer works in (the
  `tests.md` rule fixes it, nobody asks), and the check closing every step.
- **`${CLAUDE_PLUGIN_ROOT}/reference/visual-check.md`** — only with a
  `## Visual check` section in the spec.

## Procedure

### 1. Load the spec

A path is read directly; a custom id is looked up as `.specs/<customId>-*.md`.
If the file does not exist, say so and stop.

**Check the status.** Not `approved` → warn the developer and proceed only on
their confirmation.

### 2. Break the plan into tasks

Parse `## Implementation plan`: one task per step, in order, with its number,
description and files. Show the breakdown, then start on it:

```
Task breakdown from spec:
[ ] 1. <Step 1> — <involved files>
[ ] 2. <Step 2> — <involved files>
```

Do not ask the developer to confirm the breakdown: the plan was approved as a
whole. A step you cannot carry out as written — say which and why, and stop.

### 3. Execute the steps

For each step, in the plan's order:

1. **Announce** it: `Step <N>/<total>: <description>`.
2. **Read the docs** when the step touches a library: prefer the `ctx7` CLI
   (`ctx7 library <name>`, then `ctx7 docs <libraryId> <query>`), falling back
   to the Context7 MCP.
3. **Implement** it following `reference/methodologies.md`.
4. **Check** it — the test and lint commands from that same reference. A
   step completing a page a Visual check row names is compared with its
   frame too: fix what is the code's; the closure asks about the rest.
5. **Update** the breakdown, marking what is done and what is in progress.
6. **Log** a non-obvious choice the step made in the spec's `## Decision log`,
   with the reason, before moving on.

### 4. Summary

```
Development completed for spec: <customId> — <title>

Steps completed: <N>/<total>
Files created: <list>
Files modified: <list>
Tests: <result>
Linter: <result>
Visual: <frame: match | mismatch | not verified (why)>, or "no frames"
```

Do not commit, simplify or touch the spec's status: the flow's closure stages
the work, runs `simplify` once, verifies, reviews and produces the single
commit. The summary is not a stop: the `sdd` flow decides what follows, in
this same turn, without waiting for a prompt.

Invoked on its own: `${CLAUDE_PLUGIN_ROOT}/reference/hand-off.md`.

## Expected output

- the code implemented as the approved spec describes;
- tests and linter run, and passing;
- nothing committed and nothing pushed — that is the closure's job.
