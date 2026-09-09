# What the review writes back

A review that only reports is a review that gets repeated. Two artefacts absorb
what it found: `REGISTRY.md`, so the next task does not rediscover the same
component, and the spec, so the run is on the record.

## REGISTRY updates

Only when the agent returned a non-empty `REGISTRY_UPDATES` block.

1. read the current `REGISTRY.md`;
2. for every entry with `ACTION: add` — add the `ENTRY` block to the named
   `SECTION`, and remove that section's `_No ... registered._` placeholder if it
   is still there;
3. for every entry with `ACTION: update` — find the existing entry in the
   section and update only the fields that changed;
4. commit it: `docs(registry): update REGISTRY.md`.

Do not invent entries the agent did not return, and do not reorganise the file
while you are in it: a diff that mixes new entries with a reshuffle is a diff
nobody reviews.

## The spec's `## Review phase`

Take the spec path from the `SPEC` key of `check-prerequisites.sh`. If it is
empty, skip this — the review was invoked outside the SDD flow, and there is no
spec to annotate.

Fill in:

- **State** — `completed`
- **Date** — today, as `YYYY-MM-DD`
- **Outcome** — the status the agent returned (`pass`, `pass-with-warnings`,
  `fail`)
- **Violations** — how many rule violations were found
- **Warnings** — a short list with the rationale (`W-1: missing test for X`), or
  `none`
- **REGISTRY updates** — how many entries were applied, plus a one-line
  add/update summary per section, or `none`

Overwrite that section only and leave the rest of the spec untouched. If the
REGISTRY commit has already been made, add `docs(spec): track review outcome`;
otherwise fold both into one commit.

## The final report

```
Review: <STATUS>
Violations: <count>
Warnings: <count>
REGISTRY updated: <yes/no>
Spec updated: <yes/no>

<SUMMARY from the agent>
```
