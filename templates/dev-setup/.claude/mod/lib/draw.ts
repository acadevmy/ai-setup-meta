// draw.ts — the band and the pane as element trees.
//
// Plain functions over the surface's element table: register.ts resolves the
// table, gathers the state and the handlers, and this module lays them out.
// Every handler is a closure made in register.ts, so `$` never reaches here;
// a test hands in stub constructors and reads the tree back.

import type { BoxProps, ButtonProps, ElementConstructor, LinkProps, RenderElement, TextProps } from 'claude-code'
import type { CatalogueEntry } from './catalogue.ts'
import type { Run } from './runs.ts'
import type { Row, Span, Tone } from './rows.ts'
import { rule } from './rows.ts'
import { canResume } from './runs.ts'
import { catalogueLabelWidth, catalogueRows, entryRows, GUIDE_POINTER, NO_RUNS, runRow, RUNS_NOTE, TAB_LABELS, VIEWS } from './views.ts'
import type { View } from './views.ts'

/** The four elements every surface draws. */
export type Ui = {
  readonly Box: ElementConstructor<BoxProps>
  readonly Text: ElementConstructor<TextProps>
  readonly Button: ElementConstructor<ButtonProps>
  readonly Link: ElementConstructor<LinkProps>
}

/** The theme key each tone is drawn in; `dim` is a weight, not a colour. */
const TONE_COLOR: Readonly<Record<Exclude<Tone, 'dim'>, string>> = {
  accent: 'claude',
  good: 'success',
  warn: 'warning',
  bad: 'error',
}

const DOT = '●'
const RING = '○'

function textProps(span: Span): TextProps {
  const props: { dimColor?: boolean; bold?: boolean; color?: string } = {}
  if (span.tone === 'dim') props.dimColor = true
  else if (span.tone) props.color = TONE_COLOR[span.tone]
  if (span.bold) props.bold = true
  return props
}

function sameStyle(a: Span, b: Span): boolean {
  return a.tone === b.tone && (a.bold ?? false) === (b.bold ?? false)
}

/** One row as elements: adjacent spans of one style become one Text, so a long
 * sentence wraps as a sentence; a blank row keeps its line. */
export function drawRow(ui: Ui, row: Row): RenderElement {
  if (row.length === 0) return ui.Text({ children: [' '] })
  const merged: Span[] = []
  for (const span of row) {
    const last = merged[merged.length - 1]
    if (last && sameStyle(last, span)) merged[merged.length - 1] = { ...last, text: last.text + span.text }
    else merged.push(span)
  }
  const only = merged[0]
  if (merged.length === 1 && only) return ui.Text({ ...textProps(only), children: [only.text] })
  return ui.Box({ flexDirection: 'row', children: merged.map((span) => ui.Text({ ...textProps(span), children: [span.text] })) })
}

export function drawRows(ui: Ui, rows: readonly Row[]): RenderElement[] {
  return rows.map((row) => drawRow(ui, row))
}

/** A URL the engine accepts as a Link's `href`; anything else is drawn as text. */
export function linkable(url: string): boolean {
  return url.length <= 2048 && /^https:\/\/[!-~]+$/.test(url) && !url.includes('@')
}

function urlElement(ui: Ui, url: string): RenderElement {
  return linkable(url) ? ui.Link({ href: url }) : ui.Text({ children: [url] })
}

/** A row with a coloured mark in the gutter: the band's shape. */
function marked(ui: Ui, mark: string, tone: Tone, children: readonly RenderElement[]): RenderElement {
  return ui.Box({
    flexDirection: 'row',
    columnGap: 1,
    children: [ui.Text({ ...textProps({ text: mark, tone }), children: [mark] }), ui.Box({ flexDirection: 'row', columnGap: 1, flexShrink: 1, children: [...children] })],
  })
}

// ── The band ──────────────────────────────────────────────────────────────────

export type BandModel = {
  /** One row per open clock, as `clockRow` builds it. */
  readonly clocks: readonly Row[]
  /** The merge request just created and the tasks a button can close. */
  readonly closure: { readonly url: string; readonly tasks: readonly string[] } | null
  /** The sdd run in progress, as `compactRow` builds it; empty when none. */
  readonly usage: Row
  readonly warning: string | null
}

export type BandActions = {
  readonly close: (task: string, url: string) => void
}

export function bandIsEmpty(band: BandModel): boolean {
  return band.clocks.length === 0 && !band.closure && band.usage.length === 0 && !band.warning
}

export function drawBand(ui: Ui, band: BandModel, actions: BandActions, theirs: RenderElement | null): RenderElement {
  const rows: RenderElement[] = []
  for (const clock of band.clocks) rows.push(marked(ui, DOT, 'good', [drawRow(ui, clock)]))
  if (band.closure) {
    const { url, tasks } = band.closure
    rows.push(
      marked(ui, DOT, 'accent', [
        ui.Text({ bold: true, children: ['merge request open'] }),
        urlElement(ui, url),
        ...tasks.map((task) =>
          ui.Button({
            key: `close-${task}`,
            label: `close ${task}`,
            variant: 'primary',
            onPress: () => actions.close(task, url),
          }),
        ),
        ui.Text({ dimColor: true, children: ['stops the clock · moves it to CODE REVIEW'] }),
      ]),
    )
  }
  if (band.usage.length > 0) rows.push(marked(ui, RING, 'dim', [drawRow(ui, band.usage)]))
  if (band.warning) rows.push(marked(ui, DOT, 'warn', [ui.Text({ color: TONE_COLOR.warn, children: [band.warning] })]))
  if (theirs) rows.push(theirs)
  return ui.Box({ flexDirection: 'column', children: rows })
}

// ── The pane ──────────────────────────────────────────────────────────────────

export type PaneBody =
  | { readonly kind: 'rows'; readonly rows: readonly Row[] }
  | { readonly kind: 'commands'; readonly entries: readonly CatalogueEntry[] }
  | { readonly kind: 'runs'; readonly runs: readonly Run[]; readonly nowMs: number }

export type PaneModel = {
  readonly view: View
  readonly bodyColumns: number
  readonly body: PaneBody
  /** The footer's note on the figures: `read at 10:44`, `live`, or nothing. */
  readonly note: string
  readonly source: string
}

export type PaneActions = {
  readonly show: (view: View) => void
  readonly reload: () => void
  readonly use: (entry: CatalogueEntry) => void
  readonly resume: (run: Run) => void
}

export const PANE_KEYS = '1–7 switch the view · r reloads it · Esc closes'

function drawTabs(ui: Ui, active: View, actions: PaneActions): RenderElement {
  const tabs = VIEWS.map((name, i) => {
    const hotkey = String(i + 1)
    if (name === active) return ui.Text({ bold: true, color: TONE_COLOR.accent, children: [`${hotkey}: ${TAB_LABELS[name]}`] })
    return ui.Button({ key: `tab-${name}`, label: TAB_LABELS[name], hotkey, plain: true, dimColor: true, onPress: () => actions.show(name) })
  })
  return ui.Box({
    flexDirection: 'row',
    columnGap: 2,
    children: [
      ...tabs,
      ui.Box({ flexGrow: 1, children: [ui.Text({ children: [' '] })] }),
      ui.Button({ key: 'reload', label: 'reload', hotkey: 'r', plain: true, dimColor: true, onPress: () => actions.reload() }),
    ],
  })
}

function drawCommands(ui: Ui, entries: readonly CatalogueEntry[], actions: PaneActions): RenderElement[] {
  if (entries.length === 0) return drawRows(ui, catalogueRows(entries))
  const width = catalogueLabelWidth(entries)
  const body: RenderElement[] = []
  entries.forEach((entry, i) => {
    if (i > 0) body.push(drawRow(ui, []))
    body.push(
      ui.Box({
        flexDirection: 'row',
        columnGap: 2,
        children: [
          ui.Button({ key: `use-${entry.name}`, label: 'use', onPress: () => actions.use(entry) }),
          ui.Text({ color: TONE_COLOR.accent, children: [entry.prefix] }),
        ],
      }),
      ui.Box({ flexDirection: 'column', paddingLeft: 9, children: drawRows(ui, entryRows(entry, width)) }),
    )
  })
  body.push(drawRow(ui, []), ui.Text({ dimColor: true, children: [GUIDE_POINTER] }))
  return body
}

function drawRuns(ui: Ui, runs: readonly Run[], nowMs: number, actions: PaneActions): RenderElement[] {
  if (runs.length === 0) return [ui.Text({ dimColor: true, children: [NO_RUNS] })]
  const body = runs.map((run) => {
    const children: RenderElement[] = [drawRow(ui, runRow({ ...run, mergeRequest: '' }, nowMs))]
    if (run.mergeRequest) children.push(urlElement(ui, run.mergeRequest))
    if (canResume(run)) children.push(ui.Button({ key: `resume-${run.taskId}`, label: 'resume', variant: 'primary', onPress: () => actions.resume(run) }))
    return ui.Box({ flexDirection: 'row', columnGap: 2, children })
  })
  return [...body, drawRow(ui, []), ui.Text({ dimColor: true, children: [RUNS_NOTE] })]
}

export function drawPane(ui: Ui, pane: PaneModel, actions: PaneActions): RenderElement {
  const body =
    pane.body.kind === 'commands'
      ? drawCommands(ui, pane.body.entries, actions)
      : pane.body.kind === 'runs'
        ? drawRuns(ui, pane.body.runs, pane.body.nowMs, actions)
        : drawRows(ui, pane.body.rows)
  const footer = [pane.source, pane.note].filter((part) => part !== '').join(' · ')
  return ui.Box({
    flexDirection: 'column',
    children: [
      drawTabs(ui, pane.view, actions),
      drawRow(ui, rule(pane.bodyColumns)),
      ...body,
      drawRow(ui, rule(pane.bodyColumns)),
      ui.Text({ dimColor: true, children: [footer] }),
      ui.Text({ dimColor: true, children: [PANE_KEYS] }),
    ],
  })
}

