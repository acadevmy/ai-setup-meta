# The review checks

The contract of the `story-reviewer` agent: what it checks on the drafts, and
the exact block it returns. The skill passes this file as `CHECKS_PATH`. The
structural checks are not repeated here — `validate-story.sh` has already
passed on the folder.

## Index

- [What the reviewer reads](#what-the-reviewer-reads)
- [The checks](#the-checks)
- [The result block](#the-result-block)
- [What the author does with it](#what-the-author-does-with-it)

## What the reviewer reads

Every draft in `DRAFTS_DIR`, the product context files in `PRODUCT_FILES`, and
the rules the drafts were written against: `writing-rules.md` and `model.md`,
next to this file. It modifies nothing.

## The checks

Per **story**:

1. **INVEST**, letter by letter, with a reason for each — not a tick.
2. **The persona** is one of `product.md`'s personas or actors, never a
   technical role; **the value** is a benefit, not the action repeated.
3. **Vertical.** Not a layer, not a piece of engine, no phantom UI — a
   visible command without its logic, not a list row that does not open yet.
   If it would not survive the aliens question, say what is missing; a
   read-only list is complete, not maimed.
4. **Read vs write, list vs detail.** No complex view and transactional
   action in one story; no detail behaviour inside a list's story — opening
   an item from the list belongs to the detail's story.
5. **Scenarios.** Each one behaviour, declarative, binary, relevant to the
   "I want" clause — never justified by the "so that" alone; grouped by
   business capability, not by screen; every asynchronous outcome walks the
   whole cycle (trigger, indicator, its end, outcome) with the failure in the
   `Given`, no "in progress" scenario of its own, the right reset on error
   (the original command for an action, a retry action for a loading) and a
   single declarative retry scenario; a scenario for the user who may not
   act, when the product has a permission matrix.
6. **Language.** The glossary's terms, one per concept; no vague adjectives;
   no application layers; no reference a reader cannot resolve — an item
   cited by id alone, a bare URL, a coined abbreviation, a section number
   without its title, a file only the author can open
   (`writing-rules.md`, No mental maps).
7. **Inventions.** Anything stated as fact that neither the request, nor the
   material, nor `product.md` supports — it must become an open point.

Per **epic**: the four requirement sections are filled or say why not; its
stories, together, cover the product requirement and nothing outside its
scope.

Per **story map**, when there is one: the backbone reads as a story in time,
with no architecture column; every lane crosses every Epic (no Epic finished
before another starts); each Epic's stories are in priority order with no tie;
the walking skeleton holds tasks and spikes only and is not the MVP; every
lane is titled with the outcome it unlocks, never a label like "MVP" or
"Release 2", and every story in it is strictly necessary to that outcome;
every line of the DoR Check carries real reasoning, not a tick.

Across the run: no two stories overlap; every `BLOCKED_BY` is a real
dependency — it follows causality, like a detail on the list that opens it —
and no real dependency was dodged by duplicating behaviour across stories; no
story is missing from the flow (walk it as the user would).

## The result block

```
---STORY-REVIEW-RESULT---
VERDICT: ready | revise
PROPOSALS:
- ITEM: <id>
  CHECK: <the check number or name>
  PROBLEM: <what is wrong, citing the sentence>
  CHANGE: <the concrete edit, written so it can be applied as it is>
  BASIS: <the rule, the product.md section or the request sentence it rests on>
NOTES: <anything the author should know that is not a proposal, or "">
---END---
```

`ready` when there is nothing worth changing; `revise` when there is at least
one proposal. No proposal without a `BASIS`: a preference is not a finding.

## What the author does with it

Each proposal is integrated, or declined with the reason — the project's
context wins over the reviewer's taste. One review per run: the drafts are
not sent back a second time. A declined proposal the developer should weigh
goes in the approval's judgement calls (`publish.md`).
