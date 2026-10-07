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

Short by contract: the counts say how much matched, and only what fell short
is listed.

```
---VERIFY-RESULT---
STATUS: pass | fail | pass-with-warnings
COUNTS: requirements <covered>/<total> · tests <found>/<total> · decisions <followed>/<total> · Impact files <touched>/<total>
GAPS:
  - REQ-<N>: <partial|not-found> — <file>:<line> that shows it, or what is missing
  - Test <N>: not-found — <what is missing>
  - Missing: <file listed in Impact, absent from the diff>
  - Unexpected: <file>:<line> — <why it is not support for a listed change>
  - Dependency: <name> — not added to <manifest>
  - Decision "<decision>": <not-found|diverged — actual: ...> — <file>:<line>, or what is missing
SUMMARY: <one-line overall assessment>
---END---
```

- Every `GAPS` entry names its id and either the `<file>:<line>` that shows it
  or what is missing.
- Covered requirements, found tests and followed decisions are not listed:
  `COUNTS` already says how many there are, and a list of what matches is read
  by nobody.
- A **pass** is `STATUS`, `COUNTS` and `SUMMARY`, with no `GAPS` line.

## Classifying the status

- **pass** — every `REQ-N` is `covered`, every test `found`, no missing files,
  every decision `followed`.
- **pass-with-warnings** — every `REQ-N` is at least `partial`, with minor
  unexpected files or minor divergences that have a reasonable justification.
- **fail** — any `REQ-N` is `not-found`, or several tests are `not-found`, or a
  critical decision `diverged`.
