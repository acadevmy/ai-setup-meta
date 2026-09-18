# What the review writes back

A review that only reports is a review that gets repeated. `REGISTRY.md` is what
absorbs it, so the next task does not rediscover the same component.

## REGISTRY updates

Only when the agent returned a non-empty `REGISTRY_UPDATES` block.

1. read the current `REGISTRY.md`;
2. for every entry with `ACTION: add` — add the `ENTRY` block to the named
   `SECTION`, and remove that section's `_No ... registered._` placeholder if it
   is still there;
3. for every entry with `ACTION: update` — find the existing entry in the
   section and update only the fields that changed.

Do not invent entries the agent did not return, and do not reorganise the file
while you are in it: a diff that mixes new entries with a reshuffle is a diff
nobody reviews.

**Leave the change in the working tree — do not commit it.** Inside the SDD flow
the closure step stages and commits everything once, this file included; the
`docs(registry): update REGISTRY.md` commit this reference used to mandate was
the second of three bookkeeping commits per task. Invoked on its own, say the
file changed and let the developer decide which commit carries it.

Nothing is written back into the spec. The spec states what to build; how the
run went is in git and in the merge request.

## The final report

```
Review: <STATUS>
Violations: <count>
Warnings: <count>
REGISTRY updated: <yes/no — uncommitted>
```

Then the agent's `SUMMARY`, verbatim.
