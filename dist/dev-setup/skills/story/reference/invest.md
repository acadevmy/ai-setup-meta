# INVEST and SMART

The diagnostic checklist for a story that "doesn't work" — it almost always
breaks one of six letters — and its counterpart for tasks. Source: Bill Wake,
*INVEST in Good Stories, and SMART Tasks* (xp123.com).

## Index

- [The story is not the documentation](#the-story-is-not-the-documentation)
- [I — Independent](#i--independent)
- [N — Negotiable](#n--negotiable)
- [V — Valuable](#v--valuable)
- [E — Estimable](#e--estimable)
- [S — Small](#s--small)
- [T — Testable](#t--testable)
- [SMART, for tasks](#smart-for-tasks)

## The story is not the documentation

A story lives on three dimensions, the three Cs: the **Card** (a short
reminder, not the full specification), the **Conversation** (where the real
detail emerges) and the **Confirmation** (the acceptance criteria that say
when it is done). The most common mistake is trying to put everything on the
card: the card promises a conversation, it does not replace it.

## I — Independent

Stories should be as self-contained as possible, with no overlap and no rigid
dependency between them — so they can be reordered by value and estimated
alone.

- When two stories intertwine, merge them, or cut them along a different
  boundary.
- Perfect independence is not always possible: make the remaining dependency
  explicit (`BLOCKED_BY`). Classic case: three points for the first report,
  one for each of the next — the first story carries the shared
  infrastructure.

## N — Negotiable

A story is not a contract. It captures the essence; the details are
co-created while building.

- Write the card as a reminder. Details and test ideas are added as notes
  over time, and are not needed to prioritise.
- If you are writing very detailed requirements on the card, stop: that
  detail belongs to the conversation and the acceptance criteria.

## V — Valuable

Every story gives value to the user or the customer, not "technical" value to
the developers. This is the principle behind vertical splitting: "a complete
database layer is of little value to the customer if there is no presentation
layer".

- Split into vertical slices, each crossing every layer and delivering an
  observable behaviour, however small.
- Rephrase technical stories in terms of the value they enable, or fold them
  into the first story that needs them.
- Test: would a real user notice this story if you shipped it? If not, it is
  probably a technical task.

## E — Estimable

Not an exact estimate — enough to order and schedule it. What makes a story
not estimable, and the remedy:

- missing domain knowledge → more conversation with the customer;
- missing technical knowledge → when the gap prevents an estimate, a
  **timeboxed spike** whose only purpose is enough knowledge to estimate;
- the story is too big → split it (S).

## S — Small

At most a few person-weeks, ideally person-days. Big stories are hard to plan
and their estimates are imprecise. Split while keeping the cut vertical: by
workflow step, by business rule (simple case first), by data (a subset first),
by interface or device (one first), by performance ("works", then "works
fast"). Fill a short card with detail through the conversation, not by making
the text longer.

## T — Testable

Writing a story is an implicit promise: "I understand what I want well enough
to write a test for it". If you cannot picture the test, you have not
understood the requirement.

- Every story has acceptance criteria that prove its behaviour — here always
  Gherkin.
- **Operationalise non-functional requirements**: a measurable threshold, not
  an adjective. Not "must be fast".
- An untestable story is usually also under-negotiated or vague: go back to
  the conversation.

## SMART, for tasks

A task is not a story: it is a unit of work for the developers.

- **Specific** — clear enough to know what it involves and avoid duplicate work.
- **Measurable** — there is a criterion for "complete" (it does what it must,
  tests included).
- **Achievable** — whoever takes it can do it, and can ask for help.
- **Relevant** — it contributes to its story; the customer understands why.
- **Time-boxed** — it has a ceiling; if it overruns, the team knows and reacts.

**Quick check on a story:** can it be reordered without depending on others
(I)? Is the card a reminder, not a contract (N)? Would the user notice the
value — is it a vertical slice (V)? Can I estimate it, or do I need a spike
(E)? Is it small enough for fast feedback (S)? Do I already know how I would
test it (T)? One "no" and the story is negotiated, cut or clarified.
