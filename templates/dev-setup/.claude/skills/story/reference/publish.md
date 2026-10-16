# Publication — steps 7 and 8

The approval, the ClickUp writes, the cleanup. Every write goes through the
`clickup` agent (`clickup-contract.md`); never call the ClickUp MCP directly.

## Index

- [7. The approval](#7-the-approval)
- [8. Publication](#8-publication)
- [The story map page](#the-story-map-page)
- [The cleanup and the resume](#the-cleanup-and-the-resume)
- [The report](#the-report)

## 7. The approval

Show the tree, in release order, each item as `type [id] title`, with its
scenario count, its tags and its open points:

```
EPIC [EPIC-01] Trash bin — tags: shop
├─ US [US-01] Archive a path — 4 scenarios
├─ US [US-02] Restore an archived path — 3 scenarios, blocked by "Archive a path"
└─ US [US-03] Delete an archived path for good — 3 scenarios — da dettagliare
     To confirm: can a manager delete what an editor archived?
```

With `--map`, show the map above the tree: the backbone in one line, then one
line per release lane listing its stories by title.

Then one sentence for every judgement call the developer should know about —
a story kept whole past five scenarios, a split you chose over another, a
reviewer proposal you declined — and ask, header `Publish`:

- **Publish** — create everything on ClickUp;
- **Change something** — the developer says what; edit the drafts, re-run
  `validate-story.sh`, show the tree again;
- **Keep the drafts** — stop here; `.stories/<slug>/` stays as it is, to be
  published by a later run.

End the turn on the call. Only **Publish** authorises a ClickUp write.

## 8. Publication

**The list** is the `ClickUp list` of `product.md`'s backlog conventions; with
none, resolve `CLICKUP_SETUP_LIST_ID` as the contract says. **The tags** are the
draft's `products`, plus `da dettagliare` when its body has an **Open points**
section. **The description** is the draft's body: everything after the closing
`---` of the frontmatter, unchanged.

Create in this order, one `INTENT: create` per draft:

0. **The story map page**, when the run has a `MAP` draft — first, so every
   Epic can link to it (below).
1. **Each Epic** — `task_type: Epic`, no parent.
2. **Its spikes and tasks** — no `task_type` (the default type), `parent` the
   Epic's `task_id`.
3. **Its stories** — `task_type: User Story`, `parent` the Epic's `task_id`
   when there is one, in an order where every `BLOCKED_BY` target is created
   before the story that waits on it.

The name follows `templates.md` (Titles). After each create:

- **Relations.** For each `BLOCKED_BY` the draft declares, one `INTENT: relate`
  with `relation: blocked_by` and the target's real id. A `RELATED` is written
  by whichever of the two items is created second.
- **Missing tags.** `TAGS_MISSING` is reported, never fixed: the agent does not
  create tags, and neither do you.

## The story map page

**Where.** The ClickUp Doc named by `Story maps` in `product.md`'s backlog
conventions: its document id is the first id after `/docs/` or `/v/dc/` in
the link. When there is none, ask at the approval, header `Map doc`: **Paste a
doc link**, or **Create a doc** — `INTENT: create-doc` in the product's ClickUp
list (`parent_type: list`), named `<product> story maps`, `visibility` as the
developer chooses — and suggest adding its link to `product.md`.

**The three writes.**

1. `INTENT: create-page`, `name` the map's title, `content` the draft's body as
   it is, provisional ids included. Write the returned `"<doc_id>/<page_id>"`
   into the draft's frontmatter as `page`, and keep the page `url`.
2. Each Epic is created with a final section appended to its description:
   `**Story map**` and, on the next line, the page `url`.
3. When every item is created, `INTENT: update-page` with the map draft's
   body as it now is. Each reference was turned into a link as its item was
   created (the cleanup below); one still carrying a provisional id is an
   item that was not created, and the report says so.

The map draft is deleted last, after the update. A run resumed with a `page`
in its frontmatter does not create a second page: it goes straight to the
update.

## The cleanup and the resume

A draft is deleted **only after its create and its relations succeeded**.
Before deleting it, replace its provisional id with the real one — the
`custom_id`, or the `task_id` while ClickUp has not assigned a custom id yet —
in every draft still in the folder, so the ones not yet created point at the item
that now exists:

```bash
grep -rl -- '"US-01"' .stories/<slug>/ | xargs sed -i.bak 's/"US-01"/"DE-17201"/g'
rm -f .stories/<slug>/*.bak .stories/<slug>/US-01.md
```

With a map draft, the same moment turns its reference into a link — the map
is the only draft that cites items in its body:

```bash
sed -i.bak 's#\[US-01\]#[DE-17201](https://app.clickup.com/t/86abc123)#g' .stories/<slug>/MAP-01.md
```

The url is the `url` the agent returned for the task.

When the folder is empty, remove it. `.stories/` is in `.gitignore`: drafts
never reach a commit.

**On an error**, stop creating. If the agent's error carries a `task_id`, the
task exists: report its url, do not create it again — fix its description by
hand or with an `update`. Every draft not yet created stays on disk, with real
ids already in its relations, and a new run of `/dev-setup:story` on the same
folder picks up from there: when `.stories/` already holds drafts, offer to
publish those before starting anything new.

## The report

```
Created on ClickUp:
- MAP Trash bin story map — <page url>      (only with --map)
- EPIC Trash bin — <url>
- US [Trash bin] Archive a path — <url>
- US [Trash bin] Delete an archived path for good — <url> — da dettagliare
Not created: <draft> — <reason>          (only when something failed)
Tags not applied: <tag> on <item>        (only when TAGS_MISSING was not empty)
Open points left: <count> — they are what the developer owes before sdd
```

Open points are the work that remains before an item is really ready: list
them, never bury them.
