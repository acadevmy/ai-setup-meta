# The drafts and their templates

One file per item, in `.stories/<slug>/<id>.md`, where `<slug>` is a short
kebab-case name for the run (`trash-bin`). A draft is a YAML frontmatter and a
markdown body. **The body is exactly what ClickUp receives**; the frontmatter
is for this flow and never leaves the disk. `validate-story.sh` checks both.

Drafts never reach a commit. Before writing the first one, make sure the
project ignores the folder — this adds one line and removes nothing:

```bash
grep -q '^\.stories/' .gitignore 2>/dev/null || printf '\n# Story drafts (dev-setup)\n.stories/\n' >> .gitignore
```

## Index

- [The frontmatter](#the-frontmatter)
- [The story language](#the-story-language)
- [User Story](#user-story)
- [Epic](#epic)
- [Task](#task)
- [Spike](#spike)
- [The optional sections](#the-optional-sections)
- [Titles](#titles)

## The frontmatter

```yaml
---
id: US-02
title: Restore an archived path
type: US
products: [shop]
relations:
  "EPIC-01":
    title: "Trash bin"
    type: EPIC
    relationType: PARENT
    reason: "the epic this story belongs to"
  "US-01":
    title: "Archive a path"
    type: US
    relationType: BLOCKED_BY
    reason: "there is nothing to restore before a path can be archived"
---
```

| Key | Required | Value |
|---|---|---|
| `id` | yes | provisional (`US-01`) or the ClickUp custom id (`model.md`) |
| `title` | yes | short and descriptive, no id in front; the Epic prefix is added at publication |
| `type` | yes | `US`, `EPIC`, `TASK` or `SPIKE` |
| `products` | when `product.md` has a product index | the product tags, `[shop]`; an Epic spanning products lists them all |
| `relations` | no | as above: the key is the referenced id, quoted, at two spaces; its four fields at four spaces |

No other key. Omit an optional key rather than leave it empty, and never leave
a `{{…}}` placeholder. `frontmatter.schema.json` is the formal schema.

## The story language

Section headings stay **in English and in bold** — they are the structure of
the workspace's ClickUp templates. Everything else is written in the story
language, `Story language` in `product.md`; without one, the language the
developer wrote the request in.

| | English | Italian |
|---|---|---|
| Connextra | `As a <persona>, I want <goal>, so that <value>.` | `Come <persona>, voglio <obiettivo>, così da <valore>.` |
| Gherkin | `**Given**` `**When**` `**Then**` `**And**` `**But**` | `**Dato**` `**Quando**` `**Allora**` `**E**` `**Ma**` |
| Open point | `To confirm: …` | `Da confermare: …` |

## User Story

```markdown
**User Story**
As a <persona>, I want <goal>, so that <value>.

**Outcome**
<what changes for the user once it ships, in one or two sentences>

**Acceptance Criteria**
**Scenarios**

**Scenario:** <what this scenario illustrates>
**Given** <a known starting state>
**And** <another precondition>
**When** <the one action or event>
**Then** <an observable, binary outcome>

**Scenario:** <…>
**Given** <…>
**When** <…>
**Then** <…>
```

Two to five scenarios, each opened by its `**Scenario:**` line, each with one
`When`. Then the optional sections that have content.

## Epic

```markdown
**Introduction**
As a <persona>, I want <macro goal>, so that <value>.

<what the module does and why it exists>

**Product requirement**
<the capabilities the epic delivers, as a list>

**Technical requirement**
<constraints, integrations, performance; "None beyond the project defaults" when there are none>

**Design requirement**
<UX, UI, accessibility, the Figma frames; "No design requirement: backend only" when there is none>
```

All four sections, always: when one does not apply, say why instead of leaving
it empty. Then, optionally, **Scope** and the other optional sections. An Epic
has no scenarios of its own — its stories do.

## Task

```markdown
**Task Outcome**
<the verifiable result, never generic>

**Acceptance Criteria**
- *I know this is true when…*
- <what will be observable once it is done>
```

Optionally **Additional Notes**, **Assumptions**, **Risks**, **Resources**.
A task is SMART (`invest.md`).

## Spike

```markdown
**Task Outcome**
<the question to answer, phrased so it can be answered>

**Timebox**
<the maximum time, e.g. "1 day" — when it runs out the spike closes with what was found>

**Expected output**
<a documented answer, a recommendation, a revised estimate, a throwaway prototype — never production code>

**Exit criteria**
- The question has a documented answer
- The items it blocks can be estimated or revised
```

## The optional sections

Include a section only when it has content, in this order, after the type's
required ones:

| Section | On | Holds |
|---|---|---|
| **Scope** | Epic | `In:` and `Out:` lists — the boundaries that stop scope creep |
| **Design** | Story, Epic | the Figma links, one per line: `- [<frame name>](<url>) — <what it shows>`. Only links the developer gave or the Figma file returned |
| **Open points** | all | one `To confirm: …` per unanswered question. **Its presence is what adds the `da dettagliare` tag** |
| **Additional Notes** | all | refinement details, business logic, constraints the developer stated; `[AI-suggested]` for your own |
| **Assumptions** | all | what is assumed and needs validating |
| **Risks** | all | what could go wrong, and who could mitigate it |

The INVEST check is **not** a section: it is a check for whoever writes the
item, not for whoever builds it, and the reviewer runs it.

## Titles

At publication, `publish.md` builds the ClickUp name from `title`:

| Type | Name | Example |
|---|---|---|
| Epic | the title — a noun phrase of three or four words | `Trash bin` |
| Story under an Epic | `[<Epic title>] <title>` | `[Trash bin] Restore an archived path` |
| Task under an Epic | `[<Epic title>] <verb> <deliverable>` | `[Trash bin] Add the archived state to paths` |
| Spike under an Epic | `[<Epic title>] Spike: <question>` | `[Trash bin] Spike: can restores keep the enrolments?` |
| Standalone story | the title | `Sign up for product updates` |

A title must stand on its own in a notification or a search result: if you
find yourself referring to an item by its number, the title is not working.
