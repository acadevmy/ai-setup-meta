# The discovery question bank

How to ask, what to ask, and what the interview has to produce. The interview
rules that are not specific to discovery — one call at a time, up to four
related questions in it, end the turn after asking — are in
`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`.

## Index

- [Draft first, then ask the gaps](#draft-first-then-ask-the-gaps)
- [The budget](#the-budget)
- [Closed-first: always use AskUserQuestion](#closed-first-always-use-askuserquestion)
- [Worked examples](#worked-examples)
- [The four phases](#the-four-phases)
- [How hard to push](#how-hard-to-push)
- [The Discovery Summary](#the-discovery-summary)

## Draft first, then ask the gaps

Before the first question, fill in the Discovery Summary yourself from what
is already written: the task's outcome, notes and acceptance criteria,
`REGISTRY.md`, the rules, the code the task points at. Then ask only what the
draft leaves blank or had to guess — a question whose answer is in the task
is a question the developer already answered once. "Don't ask obvious
questions, dig into the hard parts."

Order what is left by impact: a question whose answer changes the design goes
before one that changes a detail, and a detail can become a gray area instead
of a question.

## The budget

- **First call: up to four questions**, the gaps that matter most, in one
  `AskUserQuestion` call. Its first question always carries the option
  **"Requirements clear: go to spec"** — picked, the interview ends there and
  the draft becomes the summary, in one click.
- **At most one follow-up call**, only for what the first answers opened up.
- **Five questions in all.** What is still open after that goes into Gray
  Areas: the spec approval is where it gets settled, not a third round.

A well-written task reaches the spec in one call; a thin one in two.

## Closed-first: always use AskUserQuestion

Every question goes through the `AskUserQuestion` tool with pre-compiled
options. This is the primary interaction method, not a fallback: a closed
question with informed options is answered in one click, and the options
themselves show the developer what you already understood.

How to build one:

- formulate the question as a closed choice with 2–4 options;
- make the option you would pick the first one, marked **(Recommended)** — a
  developer who agrees accepts it without reading the others;
- make each option a realistic, informed suggestion — not a placeholder;
- include a "To be defined" option when the developer might not have decided
  yet — unless the four slots are better spent; the harness adds "Other" for
  free text on its own.

Turning open questions into closed ones:

| Instead of | Ask |
|---|---|
| "What is the main problem?" | 2–3 likely problems drawn from the task description |
| "Describe the flow" | 2–3 flow variants to pick from or customise |
| "What happens on error?" | 2–3 common strategies (retry, notify, silent log) |

If a question genuinely cannot be pre-compiled — rare — use plain text. That is
the exception, not the rule.

## Worked examples

**The first call** — a notification task whose description already states the
goal (cut response delays) and the channel (push). The draft fills Core Value
and Happy Path from it; three gaps are left, asked together:

```json
AskUserQuestion({
  "questions": [
    {
      "question": "What should happen when sending a push notification fails?",
      "header": "On failure",
      "options": [
        { "label": "Retry, then in-app (Recommended)", "description": "Up to 3 retries with backoff; the in-app notification is there on the next visit." },
        { "label": "Email fallback", "description": "If the push fails, send an email instead." },
        { "label": "Requirements clear: go to spec", "description": "The task and the draft cover it — write the spec now." }
      ],
      "multiSelect": false
    },
    {
      "question": "Who may mute a notification type?",
      "header": "Muting",
      "options": [
        { "label": "Each user (Recommended)", "description": "A per-user setting, per notification type." },
        { "label": "Admins only", "description": "Workspace-wide, set by an admin." },
        { "label": "To be defined", "description": "Not decided yet — recording it as a gray area." }
      ],
      "multiSelect": false
    },
    {
      "question": "Reuse the existing EmailService queue for delivery?",
      "header": "Reuse",
      "options": [
        { "label": "Yes, same queue (Recommended)", "description": "REGISTRY.md lists it; one retry policy for both channels." },
        { "label": "A queue of its own", "description": "Push volume would starve email." }
      ],
      "multiSelect": false
    }
  ]
})
```

Picking "Requirements clear: go to spec" ends the interview whatever the other
answers were.

## The four phases

They are the coverage checklist for the draft, not an order of questions: a
phase the task already answers costs no question at all.

**Phase 1 — Core Value (the "Why").** What is the business problem or user
objective? Why does this task exist? Who benefits? What is the expected value?

**Phase 2 — Happy Path (the "What").** What is the ideal step-by-step flow? What
does the user see? What happens in the system? What are the expected inputs and
outputs?

**Phase 3 — Unhappy Path and Edge Cases.** Error handling, validations, limits.
What happens when something goes wrong? Which edge cases must be handled? Are
there security or permission requirements?

**Phase 4 — Constraints and dependencies (the high-level "How").** Known
technical constraints, external dependencies, architectural preferences. Are
there existing components to reuse? Non-functional requirements (performance,
security, UX)?

> Phase 4 gathers constraints and preferences, **not** solutions. Detailed
> architectural decisions belong to the spec (`sdd-spec`).

## How hard to push

- **Do not settle.** If an answer is vague, incomplete or opens a new ambiguity,
  that is what the one follow-up call is for: "what exactly do you mean by
  X?", "what happens if the user does Y instead of X?".
- **Chase the failures.** For every feature, push the developer to think about
  what breaks: database offline, malformed input, missing permissions.
- **Respect a boundary.** "I don't know yet" and "to be defined" are answers.
  Accept them, record them as gray areas, and do not insist.
- **Hard cap.** [The budget](#the-budget). The developer can close the
  interview at any time.

## The Discovery Summary

The interview's output, in this exact shape:

```markdown
## Discovery Summary: <custom_id> — <name>

### Core Value
<Why this task exists. Business problem, user objective, expected value.>

### Happy Path
<Ideal step-by-step flow. Input, output, expected behavior.>
1. <step>
2. <step>

### Edge Cases and Error Handling
- <edge case>: <expected behavior>

### Constraints and Preferences
- <constraint or preference>

### Existing Components to Reuse
- <component from REGISTRY.md or the codebase>
(or: "None identified")

### Gray Areas
<Aspects still to be defined, open questions, "to be defined" answers.>
- <gray area>
(or: "None — all requirements have been clarified")
```
