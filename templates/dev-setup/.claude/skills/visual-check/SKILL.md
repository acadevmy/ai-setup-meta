---
name: visual-check
description: Compares a running page with its Figma frames rendered 1:1 — the frame exported at scale 1, the page captured at the same size, pixel against pixel — and reports the differences, the displaced content and a side-by-side image. Optional, outside any task. Use when a page has to be checked against Figma on its own — a page already shipped, code written by hand, a fix to re-check — without a spec or a merge request.
argument-hint: "<figma link>… <page url> [--selector <css>] [--viewport WxH] [--threshold <r>]"
user-invocable: true
---

# Visual check

The check `sdd`, `quick` and the autonomous runs make on a task with Figma
frames, run on its own: no branch, no spec, no commit. It reports; nothing
stops and nothing is fixed unasked. The procedure, and how each verdict is
read, is `${CLAUDE_PLUGIN_ROOT}/reference/visual-check.md`: follow it, with the differences below.

**Usage**: `/dev-setup:visual-check <figma link>… <page url> [--selector <css>]
[--viewport WxH] [--threshold <r>]`. `--selector`, `--viewport` and
`--threshold` apply to every frame.

## 1 — The links

```bash
printf '%s' "<the arguments>" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-frames.sh" --json
```

`COUNT` 0 → stop: only a link with a `node-id` names a frame. No page URL in
the arguments → one `AskUserQuestion`, header `Page`, for it, and end the turn.
The page is served by the developer: never start a server.

## 2 — What each link points at

For each frame, `figma-screens.sh` — on `get_metadata`'s output saved under
`<git-common-dir>/dev-setup/visual/`, or with `--file-key`/`--node` when
`FIGMA_TOKEN` is set. A `wrapper` compares its screen child, a phone frame
gets its status bar cropped (**Crop** in the reference).

A `board` → list its screens, numbered, with name, size and label
(`MISMATCHED` called out), and propose the ones the page renders — the width
of the page's device, a name matching the URL. One `AskUserQuestion`, header
`Screens`: **The proposed ones** or **All of them**; the developer names
others through Other. End the turn. At most 12 compared; the rest are listed
as not compared, never dropped.

## 3 — Export and compare

Export every screen at scale 1 (step 1 of the reference: the Figma MCP's
`download_assets`, or `figma-export.sh` with `FIGMA_TOKEN`), then
`visual-check.sh` against the URL, with the row's crop, selector, viewport
and threshold. A panel on a desktop board is captured with `--selector` at
its page's viewport (the reference says why); no selector given → ask for
it in step 2's question.

## 4 — The report

One table, mismatches first: frame (as a link), verdict, `SHIFTS`,
`REGIONS`, `DIFF_RATIO`, and the `SIDE_BY_SIDE` path. Read each
`SIDE_BY_SIDE` image and say in a sentence what differs and whether it
looks like the code or the frame — `get_design_context` on that node gives
the exact padding and gap. A frame `unverified` is listed with its `CAUSE`
and `REASON`: install nothing.

Change no code unless the developer asks for it afterwards. Never raise a
threshold to make a frame pass.
