# The discovery question bank

How to ask, what to ask, and what the interview has to produce. The interview
rules that are not specific to discovery — one question at a time, end the turn
after asking — are in `${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`.

## Index

- [Closed-first: always use AskUserQuestion](#closed-first-always-use-askuserquestion)
- [Worked examples](#worked-examples)
- [The four phases](#the-four-phases)
- [How hard to push](#how-hard-to-push)
- [The Discovery Summary](#the-discovery-summary)

## Closed-first: always use AskUserQuestion

Every question goes through the `AskUserQuestion` tool with pre-compiled
options. This is the primary interaction method, not a fallback: a closed
question with informed options is answered in one click, and the options
themselves show the developer what you already understood.

How to build one:

- read the task context, the project stack and the conversation so far;
- formulate the question as a closed choice with 2–4 options;
- make each option a realistic, informed suggestion — not a placeholder;
- always include a "To be defined" option when the developer might not have
  decided yet;
- the harness adds an "Other" option for free text on its own.

Turning open questions into closed ones:

| Instead of | Ask |
|---|---|
| "What is the main problem?" | 2–3 likely problems drawn from the task description |
| "Describe the flow" | 2–3 flow variants to pick from or customise |
| "What happens on error?" | 2–3 common strategies (retry, notify, silent log) |

If a question genuinely cannot be pre-compiled — rare — use plain text. That is
the exception, not the rule.

## Worked examples

**Phase 1 — Core Value:**

```json
AskUserQuestion({
  "questions": [{
    "question": "What is the main goal of the notification system?",
    "header": "Core Value",
    "options": [
      { "label": "Cut delays", "description": "Users do not notice important events in time today, which delays their responses." },
      { "label": "Replace email", "description": "Email notifications go unread. A more immediate channel is needed (push/in-app)." },
      { "label": "Engagement", "description": "Increase engagement by pulling users back into the app when something relevant happens." },
      { "label": "To be defined", "description": "Not decided yet — recording it as a gray area." }
    ],
    "multiSelect": false
  }]
})
```

**Phase 3 — an edge case:**

```json
AskUserQuestion({
  "questions": [{
    "question": "What should happen when sending a push notification fails?",
    "header": "Error handling",
    "options": [
      { "label": "Automatic retry", "description": "The system retries up to 3 times with exponential backoff." },
      { "label": "Email fallback", "description": "If the push fails, send an email instead." },
      { "label": "Silent log", "description": "Log the error without retrying. The user sees the in-app notification on their next visit." },
      { "label": "To be defined", "description": "Not decided yet — recording it as a gray area." }
    ],
    "multiSelect": false
  }]
})
```

## The four phases

Work through them mentally, moving on only when the current one is clear enough.

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
  do not move on. Follow up: "what exactly do you mean by X?", "what happens if
  the user does Y instead of X?".
- **Chase the failures.** For every feature, push the developer to think about
  what breaks: database offline, malformed input, missing permissions.
- **Respect a boundary.** "I don't know yet" and "to be defined" are answers.
  Accept them, record them as gray areas, and do not insist.
- **Soft cap.** Aim to gather everything in **10–12 questions**. The developer
  can close the interview at any time by saying they have said everything.

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
