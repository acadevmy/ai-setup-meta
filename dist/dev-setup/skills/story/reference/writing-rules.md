# The writing rules

What every item obeys. The structural checks — the Connextra sentence, the
scenario count, one `When` per scenario, the conjunction in the "I want"
clause, the frontmatter, leftover placeholders — are also enforced by
`validate-story.sh`; the rest is judgement, and the `story-reviewer` agent
checks it.

## Index

- [0. Ask before you invent](#0-ask-before-you-invent)
- [1. The Connextra sentence](#1-the-connextra-sentence)
- [2. INVEST](#2-invest)
- [3. Acceptance criteria](#3-acceptance-criteria)
- [4. Splitting](#4-splitting)
- [5. Anti-patterns](#5-anti-patterns)

## 0. Ask before you invent

If the business context, the persona or a system constraint is missing and
`product.md` does not answer it, **do not invent it**. Name what is missing
and ask (`intake.md`, step 4).

- ✅ "Before I go on: who performs this action — a signed-in user or a guest?"
- ✅ "You asked for a data export but not the format: CSV or PDF?"
- ❌ *(starts drafting)* "Assuming the user is an administrator…"

What the developer cannot answer yet becomes an **open point** in the item
("To confirm: …"), never a plausible guess. An item with open points is
published with the `da dettagliare` tag.

Technical notes you add on your own initiative are marked `[AI-suggested]`:
they are suggestions for whoever builds it, not requirements.

## 1. The Connextra sentence

- Every story opens with `As a <persona>, I want <goal>, so that <value>` —
  in the story language (`templates.md` has the Italian form).
- **The persona is a real person or a distinct system actor** ("as the
  external billing system"), taken from `product.md`. Never a technical role:
  no "frontend developer", "tech lead", "database".
- **The value is a real benefit.** Never the action repeated ("I want to log
  in so that I can log in").
- **The benefit test.** If you cannot state the benefit without falling back
  on "because they want it", resize or drop the story — do not write a value
  of convenience.

## 2. INVEST

- **Independent** — releasable on its own. No artificial dependency on
  another story in progress.
- **Negotiable** — describe the problem, not the solution. No "use React and
  Elasticsearch", no "click the red trash icon top right".
- **Valuable** — a vertical slice of working software with a direct benefit
  to the user or the business. No "create the receipts table".
- **Estimable** — clear enough to estimate. Under extreme technical
  uncertainty, write a **spike** instead, and have the story declare it with
  `BLOCKED_BY`.
- **Small** — a few days; several stories fit one sprint.
- **Testable** — "done" is measurable through the scenarios. No "the login
  must be very secure", no "shows clearly…".

`invest.md` has the remedy for each letter.

## 3. Acceptance criteria

- **Gherkin, always** — Given / When / Then, even where a checklist would do.
  One rule, one format.
- **One behaviour per scenario, one `When`.** `And` / `But` chain contexts or
  outcomes, never a second action. Two `When`s are two scenarios.
- **Behaviour, not mechanics.** External behaviour, from the user's intent.
  No "When they click the red button, Then it runs `SELECT * FROM users` and
  gets a 401".
- **Occam's razor.** No detail that adds nothing: not the error code, not
  which layer fails ("the order creation fails", not "the server returns 404").
- **Holistic coverage.** The happy path *and* the edge cases.
- **Asynchronous states.** For anything that takes time — a navigation, a
  list that loads, a call behind a button, a state change — a scenario for
  loading, for the error (with retry when there is one) and for the empty
  state. An asynchronous operation left undescribed feels like nothing
  happens. `product.md`'s UX conventions say how each state is shown.
- **Binary outcome.** Every `Then` passes or fails, never "partially". If you
  cannot picture the test, the criterion is vague: rewrite it.
- **Relevance.** A scenario about something the "I want" clause does not cover
  is scope creep: it belongs to another story.
- **Ubiquitous language.** The domain's terms, one per concept, the ones in
  `product.md`'s glossary. No synonyms for the same thing inside a story.
- **Roles.** When `product.md` has a permission matrix, a story whose action is
  restricted has a scenario for the user who may not do it.

## 4. Splitting

- **Read vs write.** Never a complex view (lists, filters) and transactional
  logic (create, edit) in one story. Isolate the view from the action.
- **Core value vs NFR.** Functional value first; performance, scalability and
  advanced security in later stories — unless `product.md` sets a default the
  story simply inherits.
- **Workflow steps.** No lifecycle under the verb "manage": create, edit and
  delete are separate stories.
- **Business rule variations.** Split by option, method or flow (card vs
  PayPal).
- **The pattern catalogue** (Lawrence): Workflow Steps, Business Rule
  Variations, Major Effort, Simple/Complex, Variations in Data, Data Entry
  Methods, Defer Performance, Operations (CRUD), Break Out a Spike. Find where
  the complexity is, list its variations, reduce to one complete slice. Try
  more than one pattern and pick the split that (a) exposes a story you could
  deprioritise or drop and (b) yields small pieces of similar size.
  `splitting.md` has the detail.
- **Two to five scenarios.** More than five usually means the scope is too
  wide: split. (This counts *scenarios per story*; *steps per scenario* —
  ideally three to five — is a separate readability rule.)
- **The atomicity exception.** Do not split when a piece would not be
  releasable. Ask: *"If I finished this story and the rest of the team were
  abducted by aliens, would what I shipped be a complete behaviour a user can
  use, however small — or a piece of engine that does not run?"* A form with
  no submit or a drag with no save is a piece of engine: keep it whole, and say
  why in your summary.
- **Never slice horizontally.** No story per architectural layer ("story 1:
  database; story 2: API; story 3: UI"). In a monorepo, a story touches every
  app of its product it needs.
- **Releasable on its own.** Stricter than Lawrence, who accepts stories that
  only add up to a Minimum Marketable Feature: here every story is deployable
  and usable alone. Do not use the MMF to justify a piece of engine.

## 5. Anti-patterns

- **No conjunction** ("and", "or") in the "I want" clause: an "and" means two
  features merged — split.
- **No vague adjectives** ("fast", "user-friendly", "intuitive", "clear"):
  numbers ("loads in under 2 seconds"), or `product.md`'s defaults.
- **No prescriptive UI.** Intent ("when the user confirms the submission"),
  not clicks ("clicks the green paper-plane button").
- **No phantom UI.** Never a UI element whose logic waits for a future story.
  Today's interface reflects exactly today's features and is deployable — a
  button that says "Coming soon" is not.
- **No application layers.** Readable by someone non-technical: "the order is
  processed", "the order creation fails" — not "the server processes the
  order", "it fails on a network error".
- **No mental maps.** Cite items as `model.md` says: type, id and title the
  first time, the title or the function after.
