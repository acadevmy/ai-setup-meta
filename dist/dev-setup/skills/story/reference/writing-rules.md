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
- **"So that" motivates, it does not extend.** Only the "I want" clause sets
  the scope of the scenarios; the "so that" describes the benefit and
  **authorises no scenario**. When the benefit presupposes a capability the
  "I want" does not cover ("I want to see my courses, so that I can resume
  work on one" — resuming needs opening a course), do not bring that
  capability into the story: restate the benefit in terms of what the story
  covers ("so that I know which courses I am working on") and leave the
  capability to its own story.
- **The benefit test.** If you cannot state the benefit without falling back
  on "because they want it", resize or drop the story — do not write a value
  of convenience.

## 2. INVEST

- **Independent** — releasable on its own, without waiting for a *later*
  story. No artificial dependency on another story in progress. A dependency
  is **artificial** when it goes against causality: a story pointing at a
  page that does not exist yet, or needing a piece of a story downstream. It
  is **real** when it follows causality: the detail opened from a list
  depends on the list, its entry point. A real dependency is declared with
  `BLOCKED_BY` and respected in the release order — **never removed by
  duplicating** the upstream behaviour inside the downstream story, nor by
  pulling the downstream behaviour into the upstream one.
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
- **Asynchronous states.** For anything that takes time — a save, a list
  that loads, a sync, a call behind a button — every outcome scenario walks
  the **whole cycle**: the trigger, the loading indicator appearing, its
  disappearing at the end, the outcome. An operation that skips the wait
  feels like nothing happens. Never isolate "in progress" in a scenario of
  its own: the wait is a phase of every outcome, not a behaviour. The failure
  goes in the `Given` ("the system cannot save the data"); the `When` stays
  the user's action. No explicit wait ("waits 5 seconds" → "once processing
  ends"), no named widget ("loading indicator", not "spinner"). Two cases,
  with a different reset on error:
  - **Asynchronous action** (an active trigger: confirm, save, delete,
    sync) — the command is locked while it runs; on error **nothing new
    appears**: the error is shown and the original command is available
    again, with the data entered still there.
  - **Resource loading** (a passive trigger: a navigation, a page opening, a
    filter applied) — on error the screen is an empty error state, so **a
    dedicated retry action appears**. No data (the empty state) is a third
    outcome of the same cycle.
  - **Declarative retry** — one scenario: retrying restarts the cycle and
    the loading indicator shows again. Never rewrite the full "retry and
    succeed" / "retry and fail" flows: they are already covered.

  These scenarios may reach six or seven steps: the steps of the wait are
  phases of one behaviour, not extra behaviours, and there is still one
  `When`. `gherkin.md` has the reference scenarios; `product.md`'s UX
  conventions say how each state is shown.
- **Binary outcome.** Every `Then` passes or fails, never "partially". If you
  cannot picture the test, the criterion is vague: rewrite it.
- **Relevance.** A scenario about something the "I want" clause does not cover
  is scope creep: it belongs to another story. Compare with the "I want"
  alone, never with the "so that" (§1): a benefit that presupposes a
  capability does not make it relevant.
- **Group by business capability, not by screen.** Scenarios sit in the story
  of what the user obtains, not of the screen they obtain it on. Two
  recurring cases:
  - **A story on a list** holds only scenarios of browsing the collection:
    loading, filters, sorting, pagination, empty and error states. Nothing
    about the single item beyond its appearing in the list.
  - **A story on a detail** — its entry point is the navigation itself. When
    the user picks an item of the list, their goal is not "using the list"
    but "seeing the detail": the scenario of opening it from the list goes
    **here**, in the detail's story, which declares the list as `BLOCKED_BY`
    (a real dependency, §2). A list whose items do not open yet is a
    complete story (§4, §5).
- **Ubiquitous language.** The domain's terms, one per concept, the ones in
  `product.md`'s glossary. No synonyms for the same thing inside a story.
- **Roles.** When `product.md` has a permission matrix, a story whose action is
  restricted has a scenario for the user who may not do it.

## 4. Splitting

- **Read vs write.** Never a complex view (lists, filters) and transactional
  logic (create, edit) in one story. Isolate the view from the action.
- **List vs detail.** Within reading too, browsing the collection (the list)
  and consulting one item (the detail) are two capabilities and two stories.
  Opening the detail from the list belongs to the detail's story, which
  depends on the list with `BLOCKED_BY` (§3).
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
  why in your summary. Do not mistake *small* for *maimed*: the question is
  whether the user gets the whole value of the "I want" clause, not the
  neighbouring capabilities too. A read-only list whose items do not open is
  a complete behaviour — I sign in and I see the list; a form that does not
  submit is not, because the capability the "I want" promises stays half done.
- **Never slice horizontally.** No story per architectural layer ("story 1:
  database; story 2: API; story 3: UI"). In a monorepo, a story touches every
  app of its product it needs.
- **Releasable on its own.** Stricter than Lawrence, who accepts stories that
  only add up to a Minimum Marketable Feature: here every story is deployable
  and usable alone. Do not use the MMF to justify a piece of engine. "Usable
  alone" applies to the capability of the "I want", not to the whole flow: a
  list without the detail is usable alone; the detail without the list that
  opens it is not — which is why the detail declares the list as
  `BLOCKED_BY`, never the other way round.

## 5. Anti-patterns

- **No conjunction** ("and", "or") in the "I want" clause: an "and" means two
  features merged — split.
- **No vague adjectives** ("fast", "user-friendly", "intuitive", "clear"):
  numbers ("loads in under 2 seconds"), or `product.md`'s defaults.
- **No prescriptive UI.** Intent ("when the user confirms the submission"),
  not clicks ("clicks the green paper-plane button").
- **No phantom UI.** Never a UI element whose logic waits for a future story.
  Today's interface reflects exactly today's features and is deployable — a
  button that says "Coming soon" is not. A phantom is a **visible command
  without its logic**: a button, an icon, a menu entry, a link that does
  nothing or leads to a page that does not exist. An element that is simply
  **not interactive is not a phantom**: a list row that does not open yet is
  a list row, and the list is legitimate and releasable. It becomes a phantom
  only when it promises an interaction that is not there — a row that leads
  to a missing page. The remedy is never to add the opening to the list's
  story, but to leave it to the detail's.
- **No application layers.** Readable by someone non-technical: "the order is
  processed", "the order creation fails" — not "the server processes the
  order", "it fails on a network error".
- **No mental maps.** Cite items as `model.md` says: type, id and title the
  first time, the title or the function after.
