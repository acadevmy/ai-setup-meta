# The visual check — the UI against its Figma frame, 1:1

A frame read through the design-to-code tools gives its structure: layers,
tokens, auto-layout. A frame that is not well built — a spacer rectangle in
place of a gap, a padding on one card and not on its sibling, a text box taller
than its text — reads as one thing and renders as another, and the code
reproduces the reading. Only the rendering shows it. So when a task links Figma
frames, the UI is compared with each frame **as rendered**: the frame exported
at scale 1, the page captured at the same size, pixel against pixel.

**The check reports; a person decides.** A frame is a drawing, and a badly
built one differs from a page that is right, so a mismatch does not stop the
work by itself. With a developer in the session, every mismatch is put in
front of them — the composite, the shifts — and they choose: back to
development, or go on. With nobody to ask, the run goes on. Either way every
difference reaches the merge request: nothing the check found is dropped.

## Index

- [When it applies](#when-it-applies)
- [What a link points at](#what-a-link-points-at)
- [The spec's Visual check section](#the-specs-visual-check-section)
- [1. Export the frame](#1-export-the-frame)
- [2. Serve the page](#2-serve-the-page)
- [3. Compare](#3-compare)
- [4. Read the result](#4-read-the-result)
- [5. The developer decides — or the merge request says it](#5-the-developer-decides--or-the-merge-request-says-it)
- [What it does not cover](#what-it-does-not-cover)

## When it applies

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-frames.sh" --file <the task text> --json
```

`COUNT` above 0 and a change that renders web UI → it applies, once per frame
in `FRAMES`. `BARE_FILES` are links to a whole file, not a frame: nothing can
be compared with them, and the merge request says so. `COUNT` 0 → it does not
apply and nothing mentions it.

## What a link points at

A link is not always a screen. Ask before mapping it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-screens.sh" --file-key <key> --node <id> --json   # FIGMA_TOKEN
bash "${CLAUDE_PLUGIN_ROOT}/scripts/figma-screens.sh" --metadata <file> --json             # get_metadata's output
```

| `KIND` | What it is | Rows |
|---|---|---|
| `screen` | the screen itself | one, the linked node |
| `wrapper` | an annotation label above the screen | one, `node` = the screen child |
| `board` | a whole flow: titles, notes, every state of every device side by side | one per screen **this task renders**, each with its `node` and `name`; the others are listed under the section as not compared |

`SCREENS` gives each screen's node, name, size, label and wrapper. Two
things on a board need a decision of their own:

- **Desktop states that are panels, not pages.** A 464 px login form beside a
  1440 px full-screen frame is the form's column: compare it with its
  `selector` at the **viewport** of the full-screen frame. At its own width
  the page switches to its mobile breakpoint and the comparison means
  nothing.
- **A label that contradicts its frame** (`MISMATCHED`: `D · Home · Start
  screen` labelled `Empty password`). Which state the frame draws
  is in doubt: the spec says which one it took, and the merge request asks.

A run compares at most 12 rows; past that a row is **not verified**, never
dropped — compare it by hand, or split the task.

## The spec's Visual check section

The spec maps every frame to where the page shows it — the one decision the
check cannot make on its own. One row per screen compared:

| Frame | Node | Crop | Route | Selector | Viewport | Clip | State | Threshold |
|---|---|---|---|---|---|---|---|---|
| [Sign up — desktop](https://www.figma.com/design/…?node-id=12-345) | 12:345 | — | `/signup` | `page` | — | full | signed out, empty form | 0.02 |
| [Login — mobile](https://www.figma.com/design/…?node-id=40-1) | 40:2 | 0,59,390,589 | `/login` | `page` | — | full | password empty | 0.02 |
| [Login flow › D · Password typed](https://www.figma.com/design/…?node-id=50-1) | 50:12 | — | `/login` | `#login-form` | 1440x926 | full | password typed | 0.02 |

- **Node** — the node exported: the linked one, the screen inside a wrapper,
  or one screen of a board (`figma-screens.sh`). Compare what the page
  renders, never the board around it.
- **Crop** — `x,y,width,height` of the exported node the page renders, in its
  own pixels: a phone frame's status bar or home indicator is no web page's.
  `—` for the whole node. The page is captured at the cropped size.
- **Route** — the path on the dev server, or a Storybook story URL for a
  component frame.
- **Selector** — `page` for a whole screen; a CSS selector when the frame is
  a component or a section, so only that element is captured.
- **Viewport** — `WxH` the page is captured at when the frame is a component
  or a panel: the full-screen frame of the same device. `—` for the frame's
  own size.
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
  [--width <W> --height <H>] [--clip viewport] [--threshold <ratio>] --name <frame-slug> --json
```

It captures the page with the project's own Playwright at the frame's size,
device scale factor 1, animations off, fonts loaded, and compares.

## 4. Read the result

| Exit | `VERDICT` | What to do |
|---|---|---|
| 0 | `match` | Done for this frame. |
| 4 | `mismatch` | **Read `SIDE_BY_SIDE`** — design, page, diff in red. `SHIFTS` names content that is the frame's, moved (`16,1216 720x80: 8 px lower than the frame`); `REGIONS` the areas that differ; a size gap is spacing adding up. Find the cause on the frame — `get_design_context` on that node gives the exact padding, gap and line height. Fix what is the code's and compare again; what is left goes to step 5. |
| 3, `CAUSE=page` | `unverified` | The page did not load or the selector matched nothing: the server, the route or the state is wrong. Fix it and compare again; still failing, the frame is **not verified**, with the reason. |
| 3, `CAUSE=environment` | `unverified` | No Node, no Playwright in the project, no Chromium, or the sandbox refusing `localhost`. Install nothing: the frame is **not verified**, and the merge request says which and why. |

Never raise a threshold to make a frame pass: a difference hidden is a
difference nobody decides on.

## 5. The developer decides — or the merge request says it

What is left after the fixes — a mismatch the code cannot or should not
remove: a stray nudge in the frame, a text style off its scale, two cards of
one list spaced differently — is a decision, not a failure.

- **A developer is there** (`sdd`, `quick`, the `auto-sdd` and `multi-sdd`
  launchers before the merge request): show each mismatched frame — its
  `SIDE_BY_SIDE` image, `SHIFTS`, `REASON` — and ask **one**
  `AskUserQuestion` (header `Visual`): **Back to development** (fix the
  differences named, then compare again) or **Continue** (they go to the
  merge request as they are). End the turn on the call. On Continue, one
  line per frame in the spec's `## Decision log`:

  ```
  - <date> · **Visual difference kept: <frame name>**: <what differs — the shift, the size>. <why, in the developer's words, or "not given">.
  ```

- **Nobody is there** (a headless run): go on.

Either way the merge request has a **visual check** section, the mismatches
first: each frame as a link, its verdict, `SHIFTS` and `REASON`, and whether
a person kept it or nobody was asked. A frame not verified is listed with its
reason. A reviewer of a UI change reads that section before the diff.

## What it does not cover

Native mobile (Flutter, React Native) renders no page a browser can capture:
its frames get `not compared: native UI`. Hover, focus and motion are states a
static capture does not reach; a frame that draws one is compared only through
the **State** column, never assumed.
