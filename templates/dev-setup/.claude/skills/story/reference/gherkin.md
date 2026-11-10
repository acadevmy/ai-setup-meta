# Gherkin for acceptance criteria

The reference for writing scenarios: the keywords, the rules for Given / When
/ Then, and what makes a scenario good. Source: cucumber.io/docs/bdd. In a
story the scenarios use the format of `templates.md` — `**Scenario:**` and
bold keywords — not a `.feature` file; the rules are the same.

## Index

- [Why scenarios](#why-scenarios)
- [Keywords](#keywords)
- [Given, When, Then](#given-when-then)
- [A good scenario](#a-good-scenario)
- [Asynchronous operations](#asynchronous-operations)
- [Many scenarios for data variants](#many-scenarios-for-data-variants)

## Why scenarios

BDD closes the gap between business and engineering through shared
understanding, built from concrete examples. Three practices: **discovery**
(what the system *could* do — structured conversations with real examples),
**formulation** (what it *should* do — examples written as executable
specifications in the domain's language), **automation** (what it *actually*
does — the examples become tests that drive the implementation). The goal is
working, valuable software; tests and documentation are side effects.

## Keywords

- **Scenario** — one concrete case illustrating one rule, as Given-When-Then.
- **Given** — puts the system in a known state, before the interaction.
- **When** — the action or event: what the user does, or what triggers the
  system.
- **Then** — the expected outcome, **observable by the user**.
- **And** / **But** — chain several steps of the same kind without repeating
  the keyword.
- **Background** — setup shared by every scenario; keep it short. In a story,
  put a shared precondition in each scenario's Given instead: ClickUp has no
  Background.
- **Scenario Outline** + **Examples** — one scenario run with several data
  sets, through `<placeholder>` parameters and a table.

## Given, When, Then

- **Given** is context that already exists, not a user action.
- **When** is one action or event — the behaviour under test.
- **Then** is an outcome the user can observe, never an inspection of the
  database or internal state.
- Do not repeat a step's text under different keywords: chain with And / But.

## A good scenario

- **One behaviour**, ideally one `When`.
- **Concise**: three to five steps. More usually means mixed behaviours —
  except the wait of an asynchronous operation, below.
- **Declarative, not imperative**: what the user wants to achieve, not the
  mechanical steps.
- **No UI mechanics**: no "clicks", "fills in the field", "presses the
  button".
- **Readable by the business**: the domain's terms. "Imagine it's 1922":
  avoid technology-specific language.
- **Observable outcomes**: what the user sees, not internal state.

Imperative — avoid:

```markdown
**When** I type "alice@example.com" in the email field
**And** I type "secret" in the password field
**And** I click the "Login" button
**Then** I see "Welcome" in the header
```

Declarative — prefer:

```markdown
**When** I sign in with valid credentials
**Then** I land in my personal area
```

## Asynchronous operations

An asynchronous operation — a save, a list that loads, a sync — is written as
the user lives it: from the trigger to the final outcome, through the wait. A
scenario that skips the wait ("When they confirm, Then they see the success")
leaves the developer to decide what to show meanwhile, and the decision is
often "nothing": the user feels nothing is happening.

- **The whole cycle in every outcome scenario.** Each scenario ending in an
  outcome — success, error, no data — walks the cycle: trigger, the loading
  indicator appears, it disappears at the end, the outcome. Never isolate "in
  progress" in a scenario of its own: the wait is a phase of every behaviour,
  not a behaviour. The failure goes in the `Given` ("the system cannot…");
  the `When` stays the user's action.
- **No explicit wait.** Never "And I wait 5 seconds": the automation framework
  handles the wait. Use a semantic trigger — "once processing ends", "once the
  attempt ends".
- **UI-agnostic.** "Loading indicator", not "spinner" or "skeleton"; "the
  submission is available again", not "the button turns blue".
- **Visual reset and interactivity.** The indicator disappears before the
  outcome is checked. On error, the scenario says how the interface gets
  ready for another attempt — and the answer depends on the case.
- **Length.** Error scenarios reach six or seven steps: the admitted exception
  to three-to-five, because the steps of the wait are phases of one
  behaviour. There is still one `When`.

**Case 1 — asynchronous action (active trigger).** The user starts the
operation: confirms a form, saves, deletes, syncs. The command is locked while
it runs, to prevent double submissions. On failure **no new command
appears**: the error is shown and the original command is enabled again, with
the data entered still there.

```markdown
**Scenario:** the submission succeeds
**Given** the user has filled in the form
**When** they confirm the submission
**Then** they see the loading indicator
**And** once processing ends the indicator disappears
**And** they see the success message "Data saved"

**Scenario:** the submission fails
**Given** the user has filled in the form
**And** the system cannot save the data
**When** they confirm the submission
**Then** they see the loading indicator
**And** once the attempt ends the indicator disappears
**And** they see the message "The data could not be saved"
**And** the submission is available again
```

**Case 2 — resource loading (passive trigger).** The operation starts by
itself: a navigation, a page opening, a filter applied. On failure the screen
is an empty error state: there is no original command to enable again, so **a
dedicated retry action appears**. No data (the empty state) is a third outcome
of the same cycle: same indicator, same disappearing, then the empty-state
message.

```markdown
**Scenario:** the list loads
**When** the user opens the "My todos" page
**Then** they see the loading indicator
**And** once the data is retrieved the indicator disappears
**And** they see the list of their todos

**Scenario:** the list fails to load
**Given** the system cannot retrieve the data
**When** the user opens the "My todos" page
**Then** they see the loading indicator
**And** once the attempt ends the indicator disappears
**And** they see the message "The data could not be loaded"
**And** the "Retry" action is available
```

**Declarative retry.** When the user tries again — confirms again in case 1,
uses "Retry" in case 2 — **do not rewrite the full flows** "retry and succeed"
and "retry and fail": success and error are already covered, and repeating
them doubles the tests without adding a rule. One scenario checks that the
attempt restarts the cycle.

```markdown
**Scenario:** retrying restarts the loading
**Given** the user sees the loading error on the "My todos" page
**When** they retry the loading
**Then** the system starts a new attempt
**And** they see the loading indicator again
```

For case 1 the scenario is the same, with "Given the user sees the submission
error" and "When they confirm the submission again". If the second attempt
behaves differently — a cap on attempts, a different message — that is a new
business rule and earns its own scenario.

## Many scenarios for data variants

When a story passes five scenarios only because the same behaviour repeats
with different data, it is not too big: write one Scenario Outline.

```markdown
**Scenario:** the discount depends on the number of items
**Given** a cart with <items> items
**When** the discount is applied
**Then** the total is <total>

| items | total |
| 1     | 10    |
| 3     | 27    |
```

It counts as one scenario. If the variants change the *behaviour*, not just
the data, they are separate scenarios — and possibly separate stories.
