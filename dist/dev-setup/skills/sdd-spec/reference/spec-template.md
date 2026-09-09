# The spec document

The exact shape of `.specs/<customId>-<slug>.md`, and the rules for filling it
in. Write every section: a spec with a missing section is not a shorter spec, it
is an unanswered question moved into the code.

## Index

- [Template](#template)
- [Filling it in](#filling-it-in)

## Template

```markdown
# Spec: <Task Title> [<customId>]

> Status: draft
> Task: <ClickUp task URL>
> Branch: <branch name, if already created>
> Created: <today's date YYYY-MM-DD>
> Approved: pending

## Context
<Why this task exists. Background and motivation, from the task description and
the discovery interview.>

## Requirements
<Requirements extracted from the task description, as bullet points. Each one
must be verifiable.>

- REQ-1: <requirement>
- REQ-2: <requirement>

## Technical decisions
<Architectural and technical decisions for this implementation: chosen approach,
patterns, libraries, and why. Reference the patterns already in REGISTRY.md
where they apply.>

## Impact
- **Files to create**: <new files, relative paths>
- **Files to modify**: <existing files, relative paths>
- **Dependencies**: <new dependencies to install, or "none">

## Implementation plan
<Ordered sequence of steps. Each one atomic and verifiable.>

1. <Step 1> — <detailed description>
2. <Step 2> — <detailed description>

## Test strategy
<Recommended testing approach (TDD/BDD/none) with the rationale, then the main
test cases to implement.>

- Test 1: <description>
- Test 2: <description>

## Simplify phase
<Run state of the `simplify` skill after development. Filled in by `sdd-dev`.>

- **State**: pending | completed | skipped
- **Date**: <YYYY-MM-DD when it ran, otherwise "—">
- **Outcome**: <`changes-applied` | `no-changes` | `skipped`, otherwise "—">
- **Changes applied**: <short list of the files/refactors applied, or "none">
- **Notes**: <observations, out-of-scope files, reasons for skipping>

## Review phase
<Run state of the `review` skill after development. Filled in by `review`.>

- **State**: pending | completed
- **Date**: <YYYY-MM-DD when it ran, otherwise "—">
- **Outcome**: <`pass` | `pass-with-warnings` | `fail`, otherwise "—">
- **Violations**: <number of rule violations found, or 0>
- **Warnings**: <short list W-1, W-2, … with the rationale, or "none">
- **REGISTRY updates**: <entries applied + a short add/update summary per section, or "none">

## Notes
<Risks, open questions, additional considerations, useful references.>
```

## Filling it in

- **Requirements** are extracted faithfully from the task description — not
  invented, not broadened. A requirement the task does not state belongs in
  `## Notes` as an open question.
- **Technical decisions** must comply with the rules in `.claude/rules/`. A
  decision that conflicts with a rule is a decision to change, or a rule to
  discuss with the team — never a silent divergence.
- **The implementation plan** is ordered by dependency: foundations first, then
  the features that stand on them.
- **Reuse** what `REGISTRY.md` already records. A new component that duplicates
  a registered one is a finding, not a plan.
- **Test cases** cover the listed requirements. If a requirement has no test
  case, either it is not verifiable — rewrite it — or the strategy is
  incomplete.
- **`## Simplify phase` and `## Review phase`** are always generated with state
  `pending` and `—` placeholders: the `sdd-dev` and `review` flows fill them in
  when they finish.
