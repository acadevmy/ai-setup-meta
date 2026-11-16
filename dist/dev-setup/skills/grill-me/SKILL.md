---
name: grill-me
description: A relentless interview, in rounds, that turns a plan into decisions — on the branch's draft spec, writing each settled decision into the spec and its Decision log, or on a loose idea with no files at all. Adapted from Matt Pocock's grill-me. Use when the developer asks to be grilled or to stress-test a plan, or when kickoff hands over a draft spec before sdd-plan.
effort: high
argument-hint: "[idea | spec path]"
user-invocable: true
disable-model-invocation: false
---

# Grill me

Interview the developer until you share one understanding of the work. The
interview is the method of Matt Pocock's `grill-me` (`reference/grilling.md`);
what this skill adds is where the answers land.

## Before you start

- **`reference/grilling.md`** — the design tree, the rounds, the format.
- **`reference/attribution.md`** — the source and its licence.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — after a round,
  the turn ends.
- **`${CLAUDE_PLUGIN_ROOT}/reference/hand-off.md`** — what follows.

## 1. The subject

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-prerequisites.sh" --json
```

- **`SPEC` in `draft`**, or a spec path in `$ARGUMENTS` → **spec mode**: the
  tree grows from the spec's requirements, technical decisions, plan and
  `## Notes`, and from what the conversation already settled (kickoff's
  Discovery Summary). Do not ask again what the spec already states.
- **`SPEC` approved** → grill it only on an explicit request: a decision that
  changes it puts `Status:` back to `draft`, and `sdd-plan` approves it again.
- **No spec** → **idea mode**: the original, stateless — no file is written.

## 2. The rounds

As `reference/grilling.md` says. Facts are yours to find: an `Explore` agent
reads the code, never the developer. A question a prototype answers better
than words ("how should this feel?") is not grilled: say so and leave it open.

## 3. Where the answers land (spec mode)

After each round, before the next one:

- every settled decision goes into the section of the spec it changes —
  requirement, technical decision, plan step, test case;
- every non-obvious one also goes into `## Decision log`, in the spec's own
  format, with today's date (`date +%F`), the reason and the alternative
  discarded;
- an answer of "I don't know" becomes an open question in `## Notes`.

Nothing is committed here.

## 4. The end

The frontier is empty: every branch visited, nothing silently assumed. Show
the decisions in a short list and ask the developer to confirm the shared
understanding. Then:

- **spec mode**: the hand-off — next `sdd-plan`, on the updated spec;
- **idea mode**: when the idea is software, offer `Next: /dev-setup:kickoff`,
  in this same conversation — the context is the point.

## Expected output

- spec mode: the draft spec updated, its `## Decision log` holding every
  non-obvious decision of the session;
- idea mode: no file, a list of decisions in the conversation.
