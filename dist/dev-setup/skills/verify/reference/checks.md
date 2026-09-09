# The three checks and the result format

What "the implementation matches the spec" is broken down into, and the exact
report it produces.

## Index

- [Completeness](#completeness)
- [Correctness](#correctness)
- [Coherence](#coherence)
- [The result block](#the-result-block)
- [Classifying the status](#classifying-the-status)

## Completeness

*Is everything the spec promised actually there?*

For each `REQ-N` in `## Requirements`:

1. take the requirement's text;
2. look in the diff for evidence: files, functions, classes or logic that
   correspond to it, and test descriptions that match its intent;
3. classify it:
   - **covered** — clear evidence in both the implementation and the tests;
   - **partial** — implementation without test coverage, or a test whose
     implementation is unclear;
   - **not-found** — no evidence in the diff.

For each entry in `## Test strategy`: find a test case matching it by
description or intent, and classify it **found** or **not-found**.

## Correctness

*Did it touch what the spec said it would touch?*

Compare `## Impact` against the diff:

1. **Files to create** — each listed file appears as a new file;
2. **Files to modify** — each listed file appears as modified;
3. **Dependencies** — each listed dependency was added to `package.json`,
   `pubspec.yaml` or the relevant manifest.

Then flag:

- **Missing** — listed in Impact, absent from the diff;
- **Unexpected** — in the diff, absent from Impact, and not a test file, a
  config file or obvious support. Use judgement: a new type definition
  supporting a listed service is expected; an unrelated module is not.

## Coherence

*Did it build it the way the spec said?*

Read `## Technical decisions`. For each decision, look in the diff for evidence
that it was followed — "use Zod for validation" → Zod imports in the new files;
"repository pattern" → a repository class; "ShadCN/UI components" → ShadCN
imports — and classify it **followed** or **not-found**.

If a decision was not followed, check whether something else was used instead
and say so: the spec saying Zod while the code uses class-validator is a
**divergence**, which is a different finding from an unimplemented decision.

## The result block

```
---VERIFY-RESULT---
STATUS: pass | fail | pass-with-warnings

COMPLETENESS:
  Requirements:
  - REQ-1: <status> — <brief evidence or what's missing>
  - REQ-2: <status> — <brief evidence or what's missing>
  Tests:
  - Test 1: <found|not-found> — <test file:line or what's missing>
  - Test 2: <found|not-found> — <test file:line or what's missing>

CORRECTNESS:
  Expected files touched: <N>/<total>
  Missing: <files listed in Impact but not in the diff, or "none">
  Unexpected: <files in the diff but not in Impact, or "none">
  Dependencies: <all added | the missing ones>

COHERENCE:
  - "<decision>": <followed|not-found|diverged — actual: ...>

SUMMARY: <one-line overall assessment>
---END---
```

## Classifying the status

- **pass** — every `REQ-N` is `covered`, every test `found`, no missing files,
  every decision `followed`.
- **pass-with-warnings** — every `REQ-N` is at least `partial`, with minor
  unexpected files or minor divergences that have a reasonable justification.
- **fail** — any `REQ-N` is `not-found`, or several tests are `not-found`, or a
  critical decision `diverged`.
