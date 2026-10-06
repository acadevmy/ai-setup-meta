# Splitting user stories

How to cut a story that is too big into smaller ones that keep their value.
Source: Richard Lawrence, *The Humanizing Work Guide to Splitting User
Stories* (humanizingwork.com).

## Index

- [Vertical, never horizontal](#vertical-never-horizontal)
- [The nine patterns](#the-nine-patterns)
- [Choosing the split](#choosing-the-split)
- [Two checks on every piece](#two-checks-on-every-piece)
- [Context matters](#context-matters)

## Vertical, never horizontal

A story is a **vertical slice**: a change in the system's behaviour that gives
the user visible value and usually crosses several layers (UI, logic, data)
at once.

- **Vertical (right):** "The user can search for a flight on an exact date."
  It touches front end, back end and database, and it can be demonstrated and
  released.
- **Horizontal (wrong):** "Build the table", "write the endpoint", "do the
  UI". Small pieces, but neither independent nor valuable on their own.

Why vertical: the value is explicit in the backlog and conversations are
about real value; less low-value accidental work (most of the value sits in a
few features); faster feedback and more predictability through working
software. Splitting by layer satisfies the S of INVEST and breaks the I and
the V.

## The nine patterns

Try more than one on the same story — one usually fits better. Roughly from
most to least useful:

1. **Workflow Steps.** A story covering a whole workflow splits into the steps
   the user takes. Build the core step end to end first (with shortcuts on the
   others), then add the other steps. *Publishing an article: publish directly
   first, then editorial review, then staging preview.*
2. **Business Rule Variations.** A story often hides several business rules:
   the base rule first, then the variations. *Flight search: basic, then
   maximum stops, nearby airports, flexible dates.*
3. **Major Effort.** Sometimes a story is big because of one part. Do that
   part first — the one that builds the bulk — and the stories that reuse it
   become cheap. *Card payments: the first card brand carries the integration;
   the second and third are small stories.*
4. **Simple/Complex.** When the conversation keeps finding complications, ask
   "what is the simplest version that could work?" Build that core now, defer
   the complications as stories.
5. **Variations in Data.** The complexity comes from the variety of the data.
   Start with the simplest subset and add variants just in time. *Geographic
   search: regions, then cities, then districts; one language, then the
   others.*
6. **Data Entry Methods.** The complexity is in the input, not in the
   behaviour. The simplest input first, the refined ones later. *A date: a
   plain text field first, a calendar picker as a separate story.*
7. **Defer Performance.** "Make it work, then make it fast." A first story
   works correctly but slowly; a later one optimises it. *Product search, then
   product search under 100 ms.*
8. **Operations (CRUD).** Split by the operations on an entity — create,
   read, update, delete, and variants such as sort or filter. Each operation
   is a story.
9. **Break Out a Spike.** **Last resort.** When the solution is so unknown it
   cannot even be estimated, separate a timeboxed investigation (its
   acceptance criteria are the questions answered) from the implementation
   story.

**The meta-pattern — find the complexity and reduce the variations:** find
where the complexity really is (human behaviour, a new integration, an
unknown), list all its variations, and make each split by reducing those
variations to one complete slice through the core of the complexity.

SPIDR (Spike, Paths, Interface, Data, Rules) is a related but distinct model,
by Mike Cohn: a more compact mnemonic for a subset of the same cuts.

## Choosing the split

1. **Prepare the story.** It passes INVEST except Small, which is what you
   are fixing. Check it is a story at all: tasks and components are not
   stories and cannot be split into value — merge them until together they
   represent value.
2. **Apply the patterns.** Generate several alternative splits, starting from
   the meta-pattern.
3. **Pick the winner with two checks:**
   - **Does it reveal low-value work?** Prefer the split that lets you
     deprioritise or throw away one of the resulting stories (80/20). If
     every split hides the waste the same way, change pattern.
   - **Are the pieces roughly equal?** Prefer the split that yields several
     small stories of similar size: four two-point stories beat a five and a
     three — more independent options for whoever prioritises, less variance
     in the estimates.

## Two checks on every piece

1. **Visible value.** Each story adds an observable increment for the user.
   Lawrence accepts stories that are not releasable alone as long as they add
   up to a Minimum Marketable Feature; **this skill does not** — every story
   is deployable and usable alone (`writing-rules.md`, §4). A form with no
   submit or a drag with no save is not a story, even if the MMF would
   complete it.
2. **Small and similar.** When a story reaches the top of the backlog, six to
   ten of them should fit a sprint.

## Context matters

- **Obvious or complicated work:** find all the stories, prioritise the
  valuable and risky ones first.
- **Complex work:** find one or two stories that give value *and* learning,
  and use what you learn to find the others. Listing everything up front only
  simulates predictability.
- **Chaotic work:** splitting is secondary; handle the crisis first.
