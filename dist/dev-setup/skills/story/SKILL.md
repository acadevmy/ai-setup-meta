---
name: story
description: Writes a user story, or an epic with its stories, from a short description and optional Figma links, checks it against INVEST and the project's product context, and publishes it to ClickUp after the developer approves it. Use when work has to be turned into a ready-to-build backlog item before anyone runs sdd on it.
effort: high
user-invocable: true
disable-model-invocation: true
---

# Story

Turn a raw request into backlog items a developer can build without asking
anyone anything — drafted, reviewed, approved, then created on ClickUp.

**Usage**: `/dev-setup:story "<what the feature should do>" [figma-url…] [--map]`.
`--map` also writes the story map, as a ClickUp Doc page.

## Before you start

- **`reference/intake.md`** — steps 1–4.
- **`reference/model.md`** — the item types, the hierarchy, the relations.
- **`reference/writing-rules.md`** — the rules every item obeys; read it
  first.
- **`reference/templates.md`** — the draft file and each type's body.
- **`reference/publish.md`** — steps 7–8.
- **`${CLAUDE_PLUGIN_ROOT}/reference/turn-discipline.md`** — every question.
- **`${CLAUDE_PLUGIN_ROOT}/reference/clickup-contract.md`** — the intents.

Read these only when the situation calls for them:

| Situation | Read |
|---|---|
| A story too big, with no clean cut | `reference/splitting.md` |
| An INVEST check fails and the fix is not obvious; or you write a task | `reference/invest.md` |
| Over five scenarios or steps, or an imperative one | `reference/gherkin.md` |
| Story or delivery task? How much detail? | `reference/card-essentials.md` |
| More than one user activity, or `--map` | `reference/story-mapping.md` |
| The first draft of a run | `reference/examples.md` |
| Step 6: the agent's contract | `reference/review-checks.md` |

## The flow

| # | Step | Where |
|---|---|---|
| 1 | Product context — `product.md`, the product | `reference/intake.md` |
| 2 | The material — description, Figma frames, vocabulary | `reference/intake.md` |
| 3 | The shape — one story, or an epic with its stories | `reference/intake.md` |
| 4 | The questions — only what the context does not answer | `reference/intake.md` |
| 5 | Drafts in `.stories/<slug>/` | `reference/templates.md` |
| 6 | Validation — `validate-story.sh`, then the `story-reviewer` agent | below |
| 7 | Approval — **the checkpoint** | `reference/publish.md` |
| 8 | Publication on ClickUp, then the drafts are deleted | `reference/publish.md` |

**Step 6.** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/validate-story.sh" --json
.stories/<slug>` checks what a machine can check; fix every error first. Then
the `story-reviewer` agent gets `DRAFTS_DIR`, `PRODUCT_FILES` and
`CHECKS_PATH: ${CLAUDE_PLUGIN_ROOT}/skills/story/reference/review-checks.md`,
and returns proposals: integrate or decline each, once, then re-run the
script.

**Stops:** the questions of step 4 and the approval of step 7. Nothing reaches
ClickUp before the approval.

## Expected output

- one story, or an epic with its stories (and the spikes or tasks they need)
  as subtasks, in the product's ClickUp list, in `BACKLOG`;
- each tagged with its product, plus `da dettagliare` while it has open points;
- with `--map`, a story map page linking them;
- `.stories/<slug>/` gone, or holding only the drafts not created.
