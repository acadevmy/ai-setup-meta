// visual-check.mjs — the engine behind visual-check.sh. Never called directly.
//
// Two subcommands, each printing one flat JSON object on stdout:
//
//   capture --project-dir <dir> --url <url> --width <px> --height <px>
//           --out <png> [--selector <css>] [--clip full|viewport] [--timeout <ms>]
//     Renders the page with the project's own Playwright at the frame's size,
//     device scale factor 1, animations and the caret off, fonts loaded, and
//     writes the PNG. A selector screenshots that element; without one, the
//     page (full height by default, the viewport alone with --clip viewport).
//
//   compare --design <png> --actual <png> --diff <png> --side <png>
//     Decodes both PNGs (8-bit, non-interlaced: what Figma and Chromium write),
//     compares them pixel by pixel over the area they share, and writes the
//     diff image and the design | actual | diff composite.
//
// Node built-ins only: the PNG codec is the zlib inflate/deflate Node ships,
// so the comparison runs wherever Node runs, Playwright or not.

import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { inflateSync, deflateSync } from 'node:zlib'

const argv = process.argv.slice(2)
const command = argv.shift()
const opts = {}
for (let i = 0; i < argv.length; i += 2) opts[argv[i].replace(/^--/, '')] = argv[i + 1]

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n')
}

// ── PNG codec ────────────────────────────────────────────────────────────────

const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])
const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }

function decodePng(file) {
  const buf = readFileSync(file)
  if (buf.length < 8 || !buf.subarray(0, 8).equals(SIGNATURE)) throw new Error(file + ' is not a PNG')
  let pos = 8
  let width = 0, height = 0, depth = 0, type = 0, interlace = 0
  let palette = null, trns = null
  const idat = []
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos)
    const kind = buf.toString('ascii', pos + 4, pos + 8)
    const data = buf.subarray(pos + 8, pos + 8 + len)
    if (kind === 'IHDR') {
      width = data.readUInt32BE(0)
      height = data.readUInt32BE(4)
      depth = data[8]
      type = data[9]
      interlace = data[12]
    } else if (kind === 'PLTE') palette = data
    else if (kind === 'tRNS') trns = data
    else if (kind === 'IDAT') idat.push(data)
    else if (kind === 'IEND') break
    pos += 12 + len
  }
  if (depth !== 8) throw new Error(file + ': bit depth ' + depth + ' is not supported (8 only)')
  if (interlace !== 0) throw new Error(file + ': interlaced PNGs are not supported')
  const channels = CHANNELS[type]
  if (!channels) throw new Error(file + ': colour type ' + type + ' is not supported')

  const raw = inflateSync(Buffer.concat(idat))
  const stride = width * channels
  const pixels = Buffer.alloc(stride * height)
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)]
    const src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1))
    const row = pixels.subarray(y * stride, (y + 1) * stride)
    const prev = y > 0 ? pixels.subarray((y - 1) * stride, y * stride) : null
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? row[x - channels] : 0
      const b = prev ? prev[x] : 0
      const c = prev && x >= channels ? prev[x - channels] : 0
      let v = src[x]
      if (filter === 1) v += a
      else if (filter === 2) v += b
      else if (filter === 3) v += (a + b) >> 1
      else if (filter === 4) {
        const p = a + b - c
        const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c)
        v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c
      }
      row[x] = v & 255
    }
  }

  const rgba = Buffer.alloc(width * height * 4)
  for (let i = 0; i < width * height; i++) {
    const s = i * channels, d = i * 4
    if (type === 6) pixels.copy(rgba, d, s, s + 4)
    else if (type === 2) {
      rgba[d] = pixels[s]; rgba[d + 1] = pixels[s + 1]; rgba[d + 2] = pixels[s + 2]; rgba[d + 3] = 255
    } else if (type === 0 || type === 4) {
      rgba[d] = rgba[d + 1] = rgba[d + 2] = pixels[s]
      rgba[d + 3] = type === 4 ? pixels[s + 1] : 255
    } else {
      const idx = pixels[s]
      rgba[d] = palette[idx * 3]; rgba[d + 1] = palette[idx * 3 + 1]; rgba[d + 2] = palette[idx * 3 + 2]
      rgba[d + 3] = trns && idx < trns.length ? trns[idx] : 255
    }
  }
  return { width, height, data: rgba }
}

const CRC_TABLE = new Int32Array(256).map((_, n) => {
  let c = n
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  return c
})
function crc32(buf) {
  let c = -1
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 255] ^ (c >>> 8)
  return (c ^ -1) >>> 0
}
function chunk(kind, data) {
  const out = Buffer.alloc(12 + data.length)
  out.writeUInt32BE(data.length, 0)
  out.write(kind, 4, 'ascii')
  data.copy(out, 8)
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length)
  return out
}
function encodePng(img, file) {
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(img.width, 0)
  ihdr.writeUInt32BE(img.height, 4)
  ihdr[8] = 8; ihdr[9] = 6
  const stride = img.width * 4
  const raw = Buffer.alloc((stride + 1) * img.height)
  for (let y = 0; y < img.height; y++) img.data.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride)
  writeFileSync(file, Buffer.concat([SIGNATURE, chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]))
}

// ── Compare ──────────────────────────────────────────────────────────────────
//
// The colour distance is pixelmatch's: YIQ, each pixel blended on white
// first, so a transparent corner in the export and a white page agree. A pixel
// differs above 0.1 of the maximum distance — the same default pixelmatch and
// Playwright's toHaveScreenshot use, loose enough for sub-pixel anti-aliasing.

const MAX_DELTA = 35215
const PIXEL_THRESHOLD = 0.1
const CELL = 16
const SHIFT_RANGE = 32 // px searched each way
const MIN_SHIFT = 2 // a 1 px offset is rounding, not spacing
const MIN_SHIFT_PIXELS = 40 // below this a region is noise
const SHIFT_EXPLAINS = 0.35 // the offset must remove 65% of the difference

function blend(c, a) {
  return 255 + (c - 255) * a
}
function colorDelta(a, i, b, j) {
  const aa = a[i + 3] / 255, ba = b[j + 3] / 255
  const r1 = blend(a[i], aa), g1 = blend(a[i + 1], aa), b1 = blend(a[i + 2], aa)
  const r2 = blend(b[j], ba), g2 = blend(b[j + 1], ba), b2 = blend(b[j + 2], ba)
  const y = (r1 - r2) * 0.29889531 + (g1 - g2) * 0.58662247 + (b1 - b2) * 0.11448223
  const iq = (r1 - r2) * 0.59597799 - (g1 - g2) * 0.2741761 - (b1 - b2) * 0.32180189
  const q = (r1 - r2) * 0.21147017 - (g1 - g2) * 0.52261711 + (b1 - b2) * 0.31114694
  return 0.5053 * y * y + 0.299 * iq * iq + 0.1957 * q * q
}

function compare() {
  const design = decodePng(opts.design)
  const actual = decodePng(opts.actual)
  const w = Math.min(design.width, actual.width)
  const h = Math.min(design.height, actual.height)
  const W = Math.max(design.width, actual.width)
  const H = Math.max(design.height, actual.height)
  const limit = MAX_DELTA * PIXEL_THRESHOLD * PIXEL_THRESHOLD

  const diff = { width: W, height: H, data: Buffer.alloc(W * H * 4) }
  const cols = Math.ceil(W / CELL), rows = Math.ceil(H / CELL)
  const cells = new Int32Array(cols * rows)
  let differing = 0

  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const d = (y * W + x) * 4
      if (x >= w || y >= h) {
        // Outside the shared area: one image has pixels the other lacks.
        diff.data[d] = 255; diff.data[d + 1] = 140; diff.data[d + 2] = 0; diff.data[d + 3] = 255
        continue
      }
      const i = (y * design.width + x) * 4
      const j = (y * actual.width + x) * 4
      if (colorDelta(design.data, i, actual.data, j) > limit) {
        differing++
        cells[Math.floor(y / CELL) * cols + Math.floor(x / CELL)]++
        diff.data[d] = 230; diff.data[d + 1] = 0; diff.data[d + 2] = 60; diff.data[d + 3] = 255
      } else {
        // The design, faded, so a red pixel can be placed on the layout.
        const a = actual.data[j + 3] / 255
        const lum = blend(actual.data[j], a) * 0.299 + blend(actual.data[j + 1], a) * 0.587 + blend(actual.data[j + 2], a) * 0.114
        const v = Math.round(255 - (255 - lum) * 0.15)
        diff.data[d] = diff.data[d + 1] = diff.data[d + 2] = v
        diff.data[d + 3] = 255
      }
    }
  }
  encodePng(diff, opts.diff)

  // Regions: the 16 px cells holding a differing pixel, joined when they touch,
  // largest first. They tell the reader where to look on the composite.
  const seen = new Uint8Array(cols * rows)
  const regions = []
  for (let start = 0; start < cells.length; start++) {
    if (!cells[start] || seen[start]) continue
    let minX = cols, minY = rows, maxX = 0, maxY = 0, count = 0
    const stack = [start]
    seen[start] = 1
    while (stack.length) {
      const k = stack.pop()
      const cx = k % cols, cy = (k - cx) / cols
      count += cells[k]
      minX = Math.min(minX, cx); maxX = Math.max(maxX, cx)
      minY = Math.min(minY, cy); maxY = Math.max(maxY, cy)
      for (const [nx, ny] of [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]]) {
        if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue
        const n = ny * cols + nx
        if (cells[n] && !seen[n]) { seen[n] = 1; stack.push(n) }
      }
    }
    const x = minX * CELL, y = minY * CELL
    regions.push({
      x, y,
      w: Math.min((maxX + 1) * CELL, w) - x,
      h: Math.min((maxY + 1) * CELL, h) - y,
      pixels: count,
    })
  }
  regions.sort((a, b) => b.pixels - a.pixels)

  // Shifts: a region whose content is the same, moved. For each of the largest
  // regions, slide the capture against the design along one axis at a time;
  // an offset that removes most of the difference is a spacing error of that
  // many pixels — the defect this check exists for, and one a global ratio
  // dilutes on a long page. Font rendering differences do not line up at any
  // offset, so they are never reported as a shift.
  const differsAt = (x, y, dx, dy) => {
    const ax = x + dx, ay = y + dy
    if (ax < 0 || ay < 0 || ax >= actual.width || ay >= actual.height) return true
    return colorDelta(design.data, (y * design.width + x) * 4, actual.data, (ay * actual.width + ax) * 4) > limit
  }
  const shifts = []
  for (const r of regions.slice(0, 8)) {
    if (r.pixels < MIN_SHIFT_PIXELS) continue
    // Pad the region by the search range so the moved content is inside it.
    const x0 = Math.max(0, r.x - SHIFT_RANGE), y0 = Math.max(0, r.y - SHIFT_RANGE)
    const x1 = Math.min(design.width, r.x + r.w + SHIFT_RANGE), y1 = Math.min(design.height, r.y + r.h + SHIFT_RANGE)
    const step = (x1 - x0) * (y1 - y0) > 200000 ? 2 : 1
    const count = (dx, dy) => {
      let n = 0
      for (let y = y0; y < y1; y += step) for (let x = x0; x < x1; x += step) if (differsAt(x, y, dx, dy)) n++
      return n
    }
    const base = count(0, 0)
    let best = { dx: 0, dy: 0, n: base }
    for (let d = -SHIFT_RANGE; d <= SHIFT_RANGE; d++) {
      if (d === 0) continue
      const v = count(0, d)
      if (v < best.n) best = { dx: 0, dy: d, n: v }
      const h = count(d, 0)
      if (h < best.n) best = { dx: d, dy: 0, n: h }
    }
    const moved = Math.max(Math.abs(best.dx), Math.abs(best.dy))
    if (moved >= MIN_SHIFT && best.n <= base * SHIFT_EXPLAINS) {
      const where = best.dy > 0 ? 'lower' : best.dy < 0 ? 'higher' : best.dx > 0 ? 'to the right' : 'to the left'
      shifts.push(r.x + ',' + r.y + ' ' + r.w + 'x' + r.h + ': ' + moved + ' px ' + where + ' than the frame')
    }
  }

  // design | actual | diff, 16 px apart, on white.
  const gap = 16
  const side = { width: design.width + actual.width + W + 2 * gap, height: H, data: Buffer.alloc((design.width + actual.width + W + 2 * gap) * H * 4, 255) }
  const paste = (img, ox) => {
    for (let y = 0; y < img.height; y++) {
      for (let x = 0; x < img.width; x++) {
        const s = (y * img.width + x) * 4, d = (y * side.width + ox + x) * 4
        const a = img.data[s + 3] / 255
        side.data[d] = blend(img.data[s], a); side.data[d + 1] = blend(img.data[s + 1], a); side.data[d + 2] = blend(img.data[s + 2], a)
      }
    }
  }
  paste(design, 0)
  paste(actual, design.width + gap)
  paste(diff, design.width + actual.width + 2 * gap)
  encodePng(side, opts.side)

  emit({
    DESIGN_SIZE: design.width + 'x' + design.height,
    ACTUAL_SIZE: actual.width + 'x' + actual.height,
    DIFF_PIXELS: differing,
    COMPARED_PIXELS: w * h,
    REGIONS: regions.slice(0, 8).map((r) => r.x + ',' + r.y + ' ' + r.w + 'x' + r.h + ' (' + r.pixels + ' px)').join('; '),
    REGION_COUNT: regions.length,
    SHIFTS: shifts.join('; '),
  })
}

// ── Capture ──────────────────────────────────────────────────────────────────

const FREEZE_CSS = [
  '*, *::before, *::after {',
  '  animation-duration: 0s !important; animation-delay: 0s !important;',
  '  transition-duration: 0s !important; transition-delay: 0s !important;',
  '  caret-color: transparent !important;',
  '}',
].join('\n')

function loadPlaywright(projectDir) {
  const req = createRequire(join(projectDir, 'package.json'))
  for (const name of ['playwright', '@playwright/test', 'playwright-core']) {
    try {
      return { lib: req(name), name }
    } catch {
      // try the next one
    }
  }
  return null
}

async function capture() {
  const pw = loadPlaywright(opts['project-dir'])
  if (!pw || !pw.lib.chromium) {
    emit({ CAUSE: 'environment', REASON: 'Playwright is not installed in this project (playwright, @playwright/test or playwright-core): add it as a devDependency to capture the UI' })
    process.exit(3)
  }
  const width = Number(opts.width), height = Number(opts.height)
  const timeout = Number(opts.timeout || 30000)
  let browser
  try {
    browser = await pw.lib.chromium.launch()
  } catch {
    // Inside the macOS sandbox Chromium's multi-process launch is refused;
    // one process starts, and the rendering is the same.
    browser = null
  }
  try {
    browser = browser || (await pw.lib.chromium.launch({ args: ['--single-process', '--no-zygote'] }))
  } catch (err) {
    emit({ CAUSE: 'environment', PLAYWRIGHT: pw.name, REASON: 'Chromium did not start (run `npx playwright install chromium` in the project): ' + String(err.message || err).split('\n')[0] })
    process.exit(3)
  }
  try {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, reducedMotion: 'reduce', colorScheme: 'light' })
    const page = await context.newPage()
    try {
      await page.goto(opts.url, { waitUntil: 'networkidle', timeout })
    } catch (err) {
      const first = String(err.message || err).split('\n')[0]
      // The sandbox refusing the connection is this machine's setting, not a
      // broken page: the dev server answers, the browser is not let through.
      if (first.includes('ERR_ACCESS_DENIED')) {
        emit({ CAUSE: 'environment', PLAYWRIGHT: pw.name, REASON: 'the sandbox refused the connection to ' + opts.url + ': set sandbox.network.allowLocalBinding to true in .claude/settings.json (' + first + ')' })
        process.exit(3)
      }
      emit({ CAUSE: 'page', PLAYWRIGHT: pw.name, REASON: 'the page did not load: ' + first })
      process.exit(3)
    }
    await page.addStyleTag({ content: FREEZE_CSS })
    await page.evaluate(() => document.fonts && document.fonts.ready)
    if (opts.selector) {
      const target = page.locator(opts.selector).first()
      try {
        await target.waitFor({ state: 'visible', timeout })
      } catch {
        emit({ CAUSE: 'page', PLAYWRIGHT: pw.name, REASON: 'no visible element matches ' + opts.selector + ' on ' + opts.url })
        process.exit(3)
      }
      await target.screenshot({ path: opts.out, animations: 'disabled', caret: 'hide' })
    } else {
      await page.screenshot({ path: opts.out, fullPage: opts.clip !== 'viewport', animations: 'disabled', caret: 'hide' })
    }
    emit({ PLAYWRIGHT: pw.name })
  } finally {
    await browser.close()
  }
}

try {
  if (command === 'compare') compare()
  else if (command === 'capture') await capture()
  else throw new Error('unknown subcommand: ' + command)
} catch (err) {
  process.stderr.write('error: ' + String(err.message || err) + '\n')
  process.exit(1)
}
