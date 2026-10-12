// rows.ts — one model for what a view shows, drawn two ways.
//
// A row is a list of spans: a text with a tone and a weight. The plain-text
// answer joins the spans; the pane draws each one as a Text in the tone's
// colour. Column alignment is padding inside the span, so the two outputs line
// up the same way and a test on the text is a test on what the pane shows.

/** How a span reads: `dim` an aside, `accent` the plugin's own colour,
 * `good` / `warn` / `bad` a state. No tone is the surface's text colour. */
export type Tone = 'dim' | 'accent' | 'good' | 'warn' | 'bad'

export type Span = {
  readonly text: string
  readonly tone?: Tone
  readonly bold?: boolean
}

export type Row = readonly Span[]

export function span(text: string, tone?: Tone, bold?: boolean): Span {
  const result: { text: string; tone?: Tone; bold?: boolean } = { text }
  if (tone) result.tone = tone
  if (bold) result.bold = true
  return result
}

export const dim = (text: string): Span => span(text, 'dim')
export const bold = (text: string): Span => span(text, undefined, true)
export const GAP: Span = span('  ')
export const INDENT: Span = span('  ')

/** The spans joined, trailing blanks dropped: the line the text answer prints. */
export function rowText(row: Row): string {
  return row.map((cell) => cell.text).join('').trimEnd()
}

export function rowsText(rows: readonly Row[]): string[] {
  return rows.map(rowText)
}

/** A line of text as a one-span row. */
export function line(text: string, tone?: Tone, bold?: boolean): Row {
  return [span(text, tone, bold)]
}

/** A `label  value` row: the label dim, padded to `width`, the value as given. */
export function field(label: string, width: number, ...value: Row): Row {
  return [dim(label.padEnd(width)), GAP, ...value]
}

export type Align = 'left' | 'right'

/** The cells padded to their column's width and separated by a gap: a table
 * that lines up in the text answer and in the pane alike. A missing cell is
 * blank; a column aligned `right` holds numbers. */
export function columns(rows: readonly (readonly Span[])[], align: readonly Align[], gap: Span = GAP): Row[] {
  const count = Math.max(0, ...rows.map((row) => row.length))
  const widths = Array.from({ length: count }, (_, i) => Math.max(0, ...rows.map((row) => row[i]?.text.length ?? 0)))
  return rows.map((row) =>
    Array.from({ length: count }, (_, i): Span => {
      const cell = row[i] ?? span('')
      const width = widths[i] ?? 0
      const text = align[i] === 'right' ? cell.text.padStart(width) : cell.text.padEnd(width)
      return { ...cell, text }
    }).flatMap((cell, i) => (i === 0 ? [cell] : [gap, cell])),
  )
}

/** A horizontal rule as wide as the body it is drawn in. */
export function rule(width: number): Row {
  return [dim('─'.repeat(Math.max(0, Math.min(width, 200))))]
}

/** A meter of `width` cells, `percent` of them filled. */
export function meter(percent: number, width: number): string {
  const cells = Math.max(0, width)
  const filled = Math.round((Math.min(100, Math.max(0, percent)) / 100) * cells)
  return '█'.repeat(filled) + '░'.repeat(cells - filled)
}
