---
name: sdd-dev
description: Implements an approved spec step by step, in TDD, BDD or direct mode, checking tests and lint after each step. Use when a spec is approved and its implementation plan has to be carried out.
effort: high
user-invocable: false
disable-model-invocation: false
---

# SDD dev

Develop a feature by following the implementation plan of an approved spec. The
spec is the contract: this skill executes it, it does not redesign it.

**Input**: `SPEC_REF` (a path such as `.specs/DE-123-add-auth.md`, or a custom id
such as `DE-123`) and optionally `METHODOLOGY` (`tdd`, `bdd`, `none`).

## Before you start

- **`reference/methodologies.md`** — the TDD, BDD and direct cycles, and the
  test/lint check that closes every step.

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

### 2. Determine the methodology

If `METHODOLOGY` was not passed in, ask: TDD (backend logic, APIs, services),
BDD (UI components, user flows), or none (tests after).

### 3. Break the plan into tasks

Parse `## Implementation plan` from the spec. One task per step, in order, each
with its number, description and the files it touches. Show the breakdown:

```
Task breakdown from spec:
[ ] 1. <Step 1> — <involved files>
[ ] 2. <Step 2> — <involved files>

Do you want to proceed or change the order?
```

Wait for the confirmation before starting.

### 4. Execute the steps

For each step, in the agreed order:

1. **Announce** it: `Step <N>/<total>: <description>`.
2. **Read the docs** when the step touches a library: prefer the `ctx7` CLI
   (`ctx7 library <name>`, then `ctx7 docs <libraryId> <query>`), falling back
   to the Context7 MCP.
3. **Implement** it following `reference/methodologies.md`.
4. **Check** it — the test and lint commands from that same reference.
5. **Update** the breakdown, marking what is done and what is in progress.

### 5. Simplify

When every step is done, run the `simplify` skill: reuse what already exists,
improve quality, fix what it finds. Commit any changes as
`refactor(<scope>): simplify implementation`.

Then fill in the spec's `## Simplify phase` section — `State`, `Date`,
`Outcome` (`changes-applied`, `no-changes` or `skipped` with the reason),
`Changes applied`, `Notes`. Overwrite that section only and leave the rest of
the spec untouched. Do not make a dedicated commit for the note: fold it into
the refactor commit, or into the next one.

### 6. Summary

```
Development completed for spec: <customId> — <title>

Steps completed: <N>/<total>
Methodology: <tdd/bdd/none>
Files created: <list>
Files modified: <list>
Tests: <result>
Linter: <result>
```

## Expected output

- the code implemented as the approved spec describes;
- tests and linter run, and passing;
- the spec's `## Simplify phase` section filled in.
