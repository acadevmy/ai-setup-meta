# The visual check — the UI against its Figma frame, 1:1

A frame read through the design-to-code tools gives its structure: layers,
tokens, auto-layout. A frame that is not well built — a spacer rectangle in
place of a gap, a padding on one card and not on its sibling, a text box taller
than its text — reads as one thing and renders as another, and the code
reproduces the reading. Only the rendering shows it. So when a task links Figma
frames, the UI is compared with each frame **as rendered**: the frame exported
at scale 1, the page captured at the same size, pixel against pixel.

**The check blocks.** A mismatch is a defect of the change, like a red test:
the work does not reach a commit, or an autonomous run a merge request, until
the frame and the page agree — or, interactively only, until the developer
rules that the frame is the one at fault.

## Index

- [When it applies](#when-it-applies)
- [The spec's Visual check section](#the-specs-visual-check-section)
- [1. Export the frame](#1-export-the-frame)
- [2. Serve the page](#2-serve-the-page)
- [3. Compare](#3-compare)
- [4. Read the result](#4-read-the-result)
- [When the frame is wrong](#when-the-frame-is-wrong)
- [What it does not cover](#what-it-does-not-cover)

## When it applies

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-frames.sh" --file <the task text> --json
```

`COUNT` above 0 and a change that renders web UI → it applies, once per frame
in `FRAMES`. `BARE_FILES` are links to a whole file, not a frame: nothing can
be compared with them, and the merge request says so. `COUNT` 0 → it does not
apply and nothing mentions it.

## The spec's Visual check section

The spec maps every frame to where the page shows it — the one decision the
check cannot make on its own. One row per frame:

| Frame | Node | Crop | Route | Selector | Clip | State | Threshold |
|---|---|---|---|---|---|---|---|
| [Sign up — desktop](https://www.figma.com/design/…?node-id=12-345) | 12:345 | — | `/signup` | `page` | full | signed out, empty form | 0.02 |
| [Login — mobile](https://www.figma.com/design/…?node-id=6594-74990) | 6594:74992 | 0,59,390,589 | `/login` | `page` | full | password empty | 0.02 |

- **Node** — the node exported, the linked one unless it is a presentation
  wrapper: a frame holding an annotation label next to the screen is mapped
  to the screen child, found with `get_metadata`. Compare what the page
  renders, never the board around it.
- **Crop** — `x,y,width,height` of the exported node the page renders, in its
  own pixels: a phone frame's status bar or home indicator is no web page's.
  `—` for the whole node. The page is captured at the cropped size.
- **Route** — the path on the dev server, or a Storybook story URL for a
  component frame.
- **Selector** — `page` for a whole screen; a CSS selector when the frame is
  a component or a section, so only that element is captured.
- **Clip** — `full` (default) captures the whole page height, so a page that
  grew shows as a size mismatch; `viewport` for a frame drawn at one screen's
  height.
- **State** — what has to be true for the page to look like the frame:
  fixture data, a signed-in user, a query parameter. Reached by the route or
  by test fixtures, never by editing the page for the capture.
- **Threshold** — the share of pixels allowed to differ, `0.02` unless the
  frame carries photos or charts drawn from live data; never above `0.05`, the
  script refuses it.

A frame the change does not render — a mobile frame for a web-only task, a
screen another task builds — gets a row with `not compared: <why>` in place of
the route. Every frame of the task has a row.

## 1. Export the frame

Always PNG at **scale 1**, never `get_screenshot`: it caps the longer edge at
1024 px, and a downscaled frame cannot be laid over a page. Into
`<git-common-dir>/dev-setup/visual/` (`git rev-parse --git-common-dir`), never
the working tree.

- **With the Figma MCP** (interactive): `download_assets` with the frame's
  `fileKey` and the row's **Node**, `defaultFormat: "png"`, `defaultScale: 1`.
  Its `export` URL is short-lived: download and check it at once:

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-export.sh" --url "<export url>" --out <dir>/<frame>.png --json
  ```

- **Without it** (headless, `FIGMA_TOKEN` set):

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-export.sh" --file-key <key> --node <id> --out <dir>/<frame>.png --json
  ```

`WIDTH` and `HEIGHT` are the node's size; the page is captured at it, or at
the row's **Crop** when it has one.
Exit 3 → the frame could not be exported: `REASON` says why, and that frame
is **not verified**.

## 2. Serve the page

Start the project's dev server (or Storybook) in the background, with the
command the project's README or package scripts name, on its port plus
`PORT_OFFSET` from `worktree-info.sh` in a worktree. Wait until the route
answers. Stop it when the check is done.

## 3. Compare

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/visual-check.sh" --design <dir>/<frame>.png \
  --url http://localhost:<port><route> [--design-crop <x,y,w,h>] [--selector "<css>"] \
  [--clip viewport] [--threshold <ratio>] --name <frame-slug> --json
```

It captures the page with the project's own Playwright at the frame's size,
device scale factor 1, animations off, fonts loaded, and compares.

## 4. Read the result

| Exit | `VERDICT` | What to do |
|---|---|---|
| 0 | `match` | Done for this frame. |
| 4 | `mismatch` | **Read `SIDE_BY_SIDE`** — design, page, diff in red. `SHIFTS` names content that is the frame's, moved (`16,1216 720x80: 8 px lower than the frame`); `REGIONS` the areas that differ; a size gap is spacing adding up. Find the cause on the frame — `get_design_context` on that node gives the exact padding, gap and line height — fix the code, compare again. |
| 3, `CAUSE=page` | `unverified` | The page did not load or the selector matched nothing: the server, the route or the state is wrong. Fix it and compare again. |
| 3, `CAUSE=environment` | `unverified` | No Node, no Playwright in the project, no Chromium, or the sandbox refusing `localhost`. Install nothing: the frame is **not verified**, and the merge request says which and why. |

A shift is never "close enough": the frame said 24 px and the page shows 32.
Fix the value the frame states, not the threshold — lowering the bar to pass
is the one move the check exists to refuse.

## When the frame is wrong

The frame is a drawing, and drawings have defects of their own: a stray
nudge, a text style off its scale, two cards of one list spaced differently.
**Interactively**, a mismatch that the frame causes is the developer's call,
asked once per frame with the composite in front of them. Accepted, it goes
into the spec's `## Decision log`:

```
- <date> · **Visual divergence accepted: <frame name>**: <what differs, and why the frame is wrong>. Discarded: matching the frame, because <reason>.
```

and the merge request lists it under the visual check. **Autonomously**, there
is nobody to make that call: the run fails, and the failure names the frame,
`SHIFTS` and the composite's path, so the person who picks it up can.

## What it does not cover

Native mobile (Flutter, React Native) renders no page a browser can capture:
its frames get `not compared: native UI`. Hover, focus and motion are states a
static capture does not reach; a frame that draws one is compared only through
the **State** column, never assumed.
