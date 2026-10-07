# The model: what a run produces

Four kinds of backlog item, an optional story map, three relations, one level
of nesting. Use the model to explain to the developer what you are producing
and why.

## The four item types

| Type | What it is | What it is not |
|---|---|---|
| **User Story** (`US`) | A vertical slice: one behaviour a user can use on its own, with a Connextra sentence, INVEST and Gherkin scenarios. It is nearly all of what you write. | A layer, a piece of engine, a technical recipe. |
| **Epic** (`EPIC`) | "A user story too big to fit on one card" (Patton). Written as a story, it fixes the product, technical and design requirements and, when useful, the In/Out scope. It is not estimated or released: it is split into stories. | A theme or an arbitrary folder. |
| **Task** (`TASK`) | The recipe: technical work a story needs that has a deliverable of its own. No Connextra, no INVEST. | Something a user would notice. |
| **Spike** (`SPIKE`) | Timeboxed research that closes a question and unblocks an estimate. It produces knowledge, not production code. | A technical story in disguise. |

And one that is not a backlog item: the **story map** (`MAP`), only with
`--map`. It is the table the epics are laid on — the backbone of user
activities (one Epic each), the walking skeleton, the release lanes — and it is
published as a **ClickUp Doc page**, never as a task: it is planning, not work.
It has no acceptance criteria, is not estimated, is not released, and it is not
a container of tasks: a workspace one level deep has no place above the
epics.

Without `--map`, the map is still how you think about a request with several
activities (`story-mapping.md`) — it is just not written down.

Not produced here: **bugs** — a defect is not a feature request; it goes
through `quick`.

## The hierarchy — one level, never two

The workspace nests one level: an Epic and its subtasks.

- `EPIC` has no parent.
- `US`, `TASK` and `SPIKE` have the `EPIC` as parent, or no parent at all when
  the run produces a single story.
- A story never has subtasks. A spike or a task a story needs is a sibling
  under the same Epic, and the story declares it with `BLOCKED_BY`.
- A `MAP` has no relations: it lists the epics and stories in its body, and
  each Epic links back to it at publication (`publish.md`).

**When to write an Epic.** One story that passes INVEST → a standalone story,
no Epic. Two or more stories → an Epic as their parent. Two or more distinct
user activities (search, choose, pay) → one Epic per activity, each with its
own stories, ordered with `story-mapping.md`.

## The relations

Declared in the draft's frontmatter, **only from the side that is blocked or
that is the child** — never as an inverse property on the other item, so the
two sides cannot drift apart.

| `relationType` | Meaning | On ClickUp |
|---|---|---|
| `PARENT` | The referenced item is this one's parent. At most one. | the subtask's parent |
| `BLOCKED_BY` | This item cannot start or close before the referenced one. Real dependencies only — an artificial one breaks the I of INVEST. | a dependency, "waiting on" |
| `RELATED` | A link with no blocking and no hierarchy. Symmetric: declare it on one side only. | a task link |

Order the entries of `relations` by `relationType` (`PARENT`, `BLOCKED_BY`,
`RELATED`), then by type (`EPIC`, `US`, `SPIKE`, `TASK`), then by id. Reference
an item only if it exists on ClickUp or is drafted in the same run.

## Ids

A draft's id is provisional and progressive per type — `EPIC-01`, `US-01`,
`US-02`, `TASK-01`, `SPIKE-01`, `MAP-01` — unless the item already exists on
ClickUp, in which case its custom id (`DE-123`) is used. Publishing replaces each
provisional id with the real one (`publish.md`).

**Never make the reader keep a table in their head.** Wherever a person reads
the text — the summary, a scenario, a `reason`, the approval tree — cite an
item as `type [id] title` the first time, and by its title or its function
after that. "US-03 and US-04 follow US-01" forces the reader to resolve ids;
"the deletion follows the archiving" does not. The id is for the machine.
