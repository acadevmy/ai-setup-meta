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
- **Concise**: three to five steps. More usually means mixed behaviours.
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
