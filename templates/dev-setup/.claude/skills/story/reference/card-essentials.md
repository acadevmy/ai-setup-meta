# Story essentials

When you doubt whether something is a story or a delivery task, when a title
does not stand on its own, or when you have to decide how much detail goes on
the card. Source: Jeff Patton, *User Story Essentials* quick reference.

## Index

- [Stories are for telling, not for specifying](#stories-are-for-telling-not-for-specifying)
- [The three Cs, and beyond](#the-three-cs-and-beyond)
- [What goes on the card](#what-goes-on-the-card)
- [Agree on what to build before building it](#agree-on-what-to-build-before-building-it)
- [Stories versus delivery tasks](#stories-versus-delivery-tasks)
- [From idea to delivery](#from-idea-to-delivery)

## Stories are for telling, not for specifying

User stories are named after **how they are used**, not how they are written.
Kent Beck's original insight: solve the problem of communicating what to
build by getting together and telling stories, to build **shared
understanding**. The conversation is not only about *what* to build but about
*who* will use it and *why* — to find the most valuable thing you can build
for the least cost.

A shared document is not shared understanding: reading the same text,
different people picture different things. Understanding comes from
describing ideas with words and pictures, then combining and refining them
together.

## The three Cs, and beyond

A story is a **token for a conversation**, not the conversation.

- **Card** — one idea per card, with just enough to find the details when
  they are needed, like a library catalogue card. It is for organising,
  prioritising and planning.
- **Conversation** — discuss it with others, let them ask a lot, work towards
  the ideal solution together.
- **Confirmation** — bring models, personas, UI sketches; agree on what to
  build and **record the agreement as confirmation tests** — the acceptance
  criteria.

Then **Construction** (the people who build it, equipped with that shared
understanding) and **Consequences** (working software to learn from, tested
with real users; the improvement ideas restart the cycle).

## What goes on the card

- **A short title** — easy to read in a backlog and to say at a standup. If
  you find yourself referring to the story by its number, the title is not
  working.
- **A description** when the title is not enough — always who, what and why
  (the Connextra sentence).
- **Meta-information** — estimate, value, dependencies, status: on ClickUp,
  these are fields, not text.

## Agree on what to build before building it

Before the team commits to a story, agree on its acceptance criteria. Record
the answers to: *what will we test to confirm it is done?* and *how will we
demonstrate it at a product review?* Write the tests with examples
(Specification by Example, Gojko Adzic).

## Stories versus delivery tasks

Every story describes **a piece of software you can taste**: once built, it
teaches you something. That is the vertical split.

- **Stories** describe something you can deliver and evaluate.
- **Delivery tasks** are the recipe — the work needed to build the story. They
  are not stories.
- Split stories into **smaller stories that are still deliverable**: similar
  recipes, less of each ingredient.
- A whole feature has value for users, but it often takes several stories to
  compose it.
- Software with no UI still needs a way to show that it works.

## From idea to delivery

Stories are split and refined progressively: **opportunities** (ideas and
requests), **discovery** (shape and validate them, find the minimum viable
product), **delivery** (design, decompose and describe the backlog items),
**validation** (review the finished software with the team, stakeholders and
users), **release** (measure against the target outcomes — the most valuable
opportunities often appear once the product is in use).

Two aggregation thresholds: **enough to test with users** (one story in one
sprint can look insignificant; aggregate enough finished parts for a user to
reach a meaningful goal) and **enough to release** (validated parts that add
up to a valuable release).

For a release budget, think in an **opening game** (stories that favour
learning and give the whole picture early, complete but immature), a **mid
game** (value accumulates once the shape is right) and an **end game** (the
value of new stories shrinks: time to release).
