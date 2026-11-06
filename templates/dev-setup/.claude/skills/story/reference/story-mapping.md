# Story mapping — as a thinking tool

When the request covers more than one user activity, and always with `--map`.
The map decides which epics exist, which stories each one needs, what is
missing, and in which order the stories are released. Without `--map` you
build it in your head; with `--map` you draft it as `MAP-01.md`
(`templates.md`) and it is published as a ClickUp Doc page. Sources: Jeff Patton, *The New Backlog* and *User Story
Mapping*; Kenneth Rubin, *Essential Scrum*.

## Index

- [Why a flat backlog is not enough](#why-a-flat-backlog-is-not-enough)
- [The map](#the-map)
- [Five binding rules](#five-binding-rules)
- [Slicing the release lanes](#slicing-the-release-lanes)
- [How the map becomes epics and stories](#how-the-map-becomes-epics-and-stories)
- [The checks before you draft](#the-checks-before-you-draft)

## Why a flat backlog is not enough

A prioritised list destroys structure and meaning. Patton's metaphor: "we
pick all the leaves off the tree, put them in a bag, then cut the tree down".
You lose the big picture, you cannot see what is missing, and planning a
release becomes an in/out decision on a hundred cards one at a time.

## The map

Two axes.

- **The backbone** (horizontal, top) — the **user activities**, the big
  things users do, in the order they happen: search, choose, pay, follow up.
  They are all essential: you do not prioritise the backbone against itself.
- **The user tasks** (the ribs under each activity) — the smaller steps that
  complete it, story-sized: candidates for stories.
- **Narrative flow** (left to right) — the order in which you would tell the
  user's story.
- **Priority** (top to bottom) — higher is more necessary. Within a column,
  every card has its own height.
- **Release lanes** — horizontal slices across the whole map, one per
  release, the first being the smallest end-to-end release. Each is titled
  with the outcome it unlocks.

## Five binding rules

1. **Narrative.** Read the backbone aloud left to right: it must sound like a
   story with causality — you cannot wait for the confirmation email before
   paying. The horizontal axis is time only, never importance.
2. **The hamburger.** Every release lane crosses the **whole** backbone: the
   user can complete the journey, however roughly. A first release with
   perfect search, perfect selection and no checkout is three layers of bread
   and no meat.
3. **Gravity.** Within a column, the top is must-have, the bottom is
   nice-to-have; when time runs out, cut from the bottom. No two cards share a
   priority: the map forces the choice.
4. **No architecture.** Every card is a user action or a piece of perceivable
   value. No column called "set up the database" or "create the API" — those
   are tasks inside stories, or the walking skeleton.
5. **Walking skeleton is not the MVP.** The **walking skeleton** serves the
   team: the thinnest end-to-end path through every layer, even if
   meaningless to a customer, to test the technical risk. The **MVP** serves
   the business: the minimum a real customer can use to prove the idea. Ask
   "do we ship without brakes and add them later?" and the question makes no
   sense: the backbone is not negotiable, only the refinement of each piece
   is.

## Slicing the release lanes

Splitting a map is not splitting a story: it draws horizontal lines that group
the stories into increments. There is no set number of lanes — slice whenever
you get a cohesive increment to test or to ship.

**The lane title is an outcome.** Never a sterile label — "Release 1", "MVP",
"Phase 2", "v1.0", "Enhancements", "Delight". Each lane is titled with the
business goal or the user behaviour it unlocks: "First purchase by card",
"Onboarding for beta testers", "Opening to B2B". The title is the filter:
for every story, ask *"is it strictly necessary to reach [title]?"* — if not,
it moves down to the next lane. Under the title, one line says what the user
gets and which pattern drew the line.

**Five patterns for drawing the line** (Patton). Use one or more, top to
bottom:

1. **Walking skeleton** — the very first line: the crudest version of every
   backbone activity, to prove the end-to-end plumbing works. It often has no
   commercial value; here it is the map's Walking Skeleton section, not a
   lane (rule 5).
2. **By outcome** — the fewest cards that let one target user reach a goal
   from start to end. This is the MVP: "buy online" takes exact-text search,
   add to cart, pay by card; PayPal and category browsing fall below the line.
   The first lane is always this slice — but its title is the outcome, never
   the word "MVP".
3. **By persona** — when the product serves several kinds of user, enable
   them one lane at a time instead of building half a product for all: the
   consumer buys first, the business user's dashboards and stock come next.
4. **Necessity vs richness** — the line keeps above it what is strictly
   **necessary** to complete each task and pushes below it what is **rich or
   rare**: edge cases, polish, alternative paths, automation. Later lanes do
   not add flows, they thicken the existing ones (password reset by email
   link, then by SMS or authenticator app).
5. **By learning** — a lane holding only what tests the riskiest business
   hypothesis, ignoring the safe features you already know how to build. Its
   goal is fast learning, not revenue.

Whatever the pattern, the cut is **always horizontal** (rule 2): a lane takes
a little of every activity and sacrifices depth for the completed journey.

## How the map becomes epics and stories

- **The backbone generates the epics.** Each activity becomes exactly one
  Epic, with the same title.
- **The user tasks become stories** under their Epic — the ones that pass
  INVEST once written.
- **The walking skeleton becomes tasks or spikes** under the Epic of the
  activity they cross: not stories, and not held to the story rules.
- **The lanes slice the epics.** Each release takes stories from every Epic,
  in backbone order: "finish all of Search, then start Checkout" is
  waterfall. The epics stay open in parallel.
- **The order of creation** follows the lanes: lane by lane, and within a
  lane, left to right along the backbone — never Epic by Epic. Express what
  really must come first as `BLOCKED_BY`, and say the release order in the
  approval tree (`publish.md`).
- **The lanes live in the map only.** No tag, no field on the tasks carries
  the release: the map page is where the plan is read, and the tasks stay
  free to be re-planned without touching them.

When one Epic is itself too big, zoom: map that Epic alone and its activities
become separate epics. The workspace is one level deep, so they sit side by
side, never nested.

## The checks before you draft

- **Narrative** — the backbone reads as a fluent story.
- **Vertical** — every lane crosses every Epic.
- **Gravity** — every column is in priority order, no ties.
- **Functional** — the map describes the experience, not the system.
- **Walking skeleton ≠ MVP.**
- **Outcome lanes** — every lane is titled with the outcome it unlocks, not a
  label, and every story in it is strictly necessary to that outcome.
- **The elevator pitch** — reading the backbone and then only the first
  release, someone outside the project should understand the base product in
  under sixty seconds. If they get lost, the narrative is broken.
- **Walk the map** — follow it step by step as the user: the missing steps
  show up ("you skipped a couple of things here"). Each one is a story you
  forgot, or a question for step 4.

With `--map`, these seven are the map's **DoR Check** section, each with one
line of real reasoning — never a bare tick. A line that does not hold means
the map is fixed before the drafts are shown.
