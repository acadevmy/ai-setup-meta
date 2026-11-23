#!/usr/bin/env bash
# visual-check.sh — does the UI look like its Figma frame, pixel for pixel?
#
# The design-to-code tools read a frame's structure: its layers, its tokens,
# its auto-layout. A frame that is not well built — a spacer rectangle instead
# of a gap, a padding set on one child and not on its sibling, a text box
# taller than its text — reads as one thing and renders as another, and the
# code faithfully reproduces the reading. Only the rendering shows the
# difference, so this script compares renderings: the frame exported 1:1 by
# figma-export.sh, and the page rendered by the project's own Playwright at
# the same size, device scale factor 1.
#
# Usage:
#   visual-check.sh --design <png> --url <url> [--selector <css>]
#                   [--clip full|viewport] [--width <px> --height <px>]
#                   [--threshold <ratio>] [--name <slug>] [--out-dir <dir>]
#                   [--project-dir <dir>] [--timeout <ms>] [--json]
#   visual-check.sh --design <png> --actual <png> [same options]
#
#   --design      the frame, exported at scale 1 (figma-export.sh)
#   --url         the page to capture — the dev server the caller started
#   --actual      an image already captured: compare only, no browser
#   --selector    capture that element instead of the page: the frame is a
#                 component or a section, not a whole screen
#   --clip        full (default): the whole page height, so a page that grew
#                 or shrank shows as a size mismatch; viewport: the first
#                 screen only, for a frame drawn at one screen's height
#   --width/--height  the viewport; default the design's own size
#   --threshold   share of the compared pixels allowed to differ, default
#                 0.02, at most 0.05: font rendering differs between Figma and
#                 Chromium, a layout shift does not stay under 5%
#   --design-crop x,y,w,h  the part of the design the page renders, in the
#                 frame's pixels: a phone frame's status bar or home indicator
#                 is no page's. The viewport follows the cropped size
#   --name        the folder the images go in, default the design's basename
#   --out-dir     default <git-common-dir>/dev-setup/visual/<branch>/<name>
#   --project-dir where Playwright is resolved from, default the repository
#                 root (the current directory outside a repository)
#
# Output (--json): VERDICT (match | mismatch | unverified), REASON, CAUSE
# (environment | page, on unverified), DESIGN, ACTUAL, DIFF, SIDE_BY_SIDE,
# DESIGN_SIZE, ACTUAL_SIZE, SIZE_MATCH, DIFF_PIXELS, DIFF_RATIO, THRESHOLD,
# REGIONS, REGION_COUNT, SHIFTS, OUT_DIR, PLAYWRIGHT.
#
# Three things make a mismatch, each on its own:
#   - a size that differs by more than 1 px in either direction: on a page
#     captured full height, that is a spacing difference adding up;
#   - a shift: a differing region whose edges line up again once moved 3 px
#     or more along one axis — a gap, a padding or a margin that is not the
#     frame's. Read on where edges sit, row by row, not on pixels: a font
#     Figma and Chromium draw differently is no shift, and a real one next to
#     it is still found. SHIFTS names each one (`x,y WxH: 8 px lower than the
#     frame`), and a global ratio would dilute it on a long page;
#   - more differing pixels than the threshold allows.
# REGIONS lists the differing areas, largest first, as
# `x,y WxH (n px)` in the design's coordinates; SIDE_BY_SIDE is design |
# actual | diff in one image, the one to look at.
#
# Exit code: 0 match · 4 mismatch · 3 unverified (no Node, no Playwright, no
# browser: CAUSE=environment; the page did not load or the selector matched
# nothing: CAUSE=page) · other = error.
#
# It needs Node and, to capture, the project's Playwright: the exception to the
# bash + jq contract, because rendering a page takes a browser. It installs
# nothing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

DESIGN=""
ACTUAL_IN=""
URL=""
SELECTOR=""
CLIP="full"
WIDTH=""
HEIGHT=""
THRESHOLD="0.02"
NAME=""
DESIGN_CROP=""
OUT_DIR=""
PROJECT_DIR=""
TIMEOUT="30000"
AS_JSON=false
MAX_THRESHOLD="0.05"

while [ $# -gt 0 ]; do
  case "$1" in
    --design) DESIGN="${2-}"; shift 2 ;;
    --actual) ACTUAL_IN="${2-}"; shift 2 ;;
    --url) URL="${2-}"; shift 2 ;;
    --selector) SELECTOR="${2-}"; shift 2 ;;
    --clip) CLIP="${2-}"; shift 2 ;;
    --width) WIDTH="${2-}"; shift 2 ;;
    --height) HEIGHT="${2-}"; shift 2 ;;
    --threshold) THRESHOLD="${2-}"; shift 2 ;;
    --name) NAME="${2-}"; shift 2 ;;
    --design-crop) DESIGN_CROP="${2-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2-}"; shift 2 ;;
    --project-dir) PROJECT_DIR="${2-}"; shift 2 ;;
    --timeout) TIMEOUT="${2-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) sed -n '2,65p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$DESIGN" ] || die "--design is required (see --help)"
[ -f "$DESIGN" ] || die "design image not found: $DESIGN"
if [ -n "$ACTUAL_IN" ]; then
  [ -f "$ACTUAL_IN" ] || die "actual image not found: $ACTUAL_IN"
else
  [ -n "$URL" ] || die "--url or --actual is required (see --help)"
  printf '%s' "$URL" | grep -qE '^(https?|file)://[^[:space:]]+$' || die "--url must be an http(s) or file URL: $URL"
fi
case "$CLIP" in full|viewport) ;; *) die "--clip is full or viewport, not $CLIP" ;; esac
printf '%s' "$TIMEOUT" | grep -qE '^[0-9]+$' || die "--timeout takes milliseconds"
printf '%s' "$THRESHOLD" | grep -qE '^(0(\.[0-9]+)?|\.[0-9]+)$' || die "--threshold is a ratio between 0 and $MAX_THRESHOLD, not $THRESHOLD"
awk -v t="$THRESHOLD" -v m="$MAX_THRESHOLD" 'BEGIN { exit !(t <= m) }' \
  || die "--threshold $THRESHOLD is above $MAX_THRESHOLD: past that, a layout shift passes as font rendering"

finish() {
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
  exit "$1"
}

# png_size <file> — "<width> <height>" from the IHDR chunk, or nothing.
png_size() {
  local sig
  sig=$(od -An -tx1 -N8 "$1" 2>/dev/null | tr -d ' \n')
  [ "$sig" = "89504e470d0a1a0a" ] || return 1
  od -An -tu1 -j16 -N8 "$1" | awk 'NF >= 8 { printf "%d %d\n", $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8; exit }'
}

DESIGN_DIMS="$(png_size "$DESIGN")" || die "not a PNG: $DESIGN"
[ -z "$DESIGN_CROP" ] || printf '%s' "$DESIGN_CROP" | grep -qE '^[0-9]+,[0-9]+,[1-9][0-9]*,[1-9][0-9]*$' \
  || die "--design-crop is x,y,width,height in pixels, not $DESIGN_CROP"
for DIM in "$WIDTH" "$HEIGHT"; do
  [ -z "$DIM" ] || printf '%s' "$DIM" | grep -qE '^[1-9][0-9]{0,4}$' || die "the viewport is not a size in pixels: ${WIDTH}x${HEIGHT}"
done

[ -n "$NAME" ] || NAME="$(basename "$DESIGN" .png)"
NAME="$(printf '%s' "$NAME" | tr -c 'A-Za-z0-9._-' '-' | sed -E 's/-+/-/g; s/^-|-$//g')"
[ -n "$NAME" ] || NAME="frame"
if [ -z "$OUT_DIR" ]; then
  COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  BRANCH="$(printf '%s' "${BRANCH:-detached}" | tr -c 'A-Za-z0-9._-' '-')"
  if [ -n "$COMMON" ]; then
    OUT_DIR="$COMMON/dev-setup/visual/$BRANCH/$NAME"
  else
    OUT_DIR="${TMPDIR:-/tmp}/dev-setup-visual/$NAME"
  fi
fi
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

json_set VERDICT ""
json_set REASON ""
json_set CAUSE ""
json_set DESIGN "$OUT_DIR/design.png"
json_set ACTUAL "$OUT_DIR/actual.png"
json_set DIFF ""
json_set SIDE_BY_SIDE ""
json_set DESIGN_SIZE "${DESIGN_DIMS% *}x${DESIGN_DIMS#* }"
json_set ACTUAL_SIZE ""
json_set SIZE_MATCH ""
json_set DIFF_PIXELS ""
json_set DIFF_RATIO ""
json_set THRESHOLD "$THRESHOLD"
json_set REGIONS ""
json_set REGION_COUNT ""
json_set SHIFTS ""
json_set OUT_DIR "$OUT_DIR"
json_set PLAYWRIGHT ""

unverified() {
  json_set VERDICT unverified
  json_set CAUSE "$1"
  json_set REASON "$2"
  finish 3
}

command -v node >/dev/null 2>&1 || unverified environment "Node is not installed: the comparison and the capture both need it"

[ "$DESIGN" -ef "$OUT_DIR/design.png" ] || cp "$DESIGN" "$OUT_DIR/design.png" || die "cannot copy the design into $OUT_DIR"

ENGINE="$SCRIPT_DIR/visual-check.mjs"
[ -f "$ENGINE" ] || die "the engine is missing: $ENGINE"

if [ -n "$DESIGN_CROP" ]; then
  node "$ENGINE" crop --in "$OUT_DIR/design.png" --out "$OUT_DIR/design.png" --rect "$DESIGN_CROP" >/dev/null \
    || die "the crop $DESIGN_CROP does not fit inside the ${DESIGN_DIMS% *}x${DESIGN_DIMS#* } design"
  DESIGN_DIMS="$(png_size "$OUT_DIR/design.png")" || die "the crop wrote no PNG"
  json_set DESIGN_SIZE "${DESIGN_DIMS% *}x${DESIGN_DIMS#* }"
fi
[ -n "$WIDTH" ] || WIDTH="${DESIGN_DIMS% *}"
[ -n "$HEIGHT" ] || HEIGHT="${DESIGN_DIMS#* }"

if [ -n "$ACTUAL_IN" ]; then
  [ "$ACTUAL_IN" -ef "$OUT_DIR/actual.png" ] || cp "$ACTUAL_IN" "$OUT_DIR/actual.png" || die "cannot copy the capture into $OUT_DIR"
else
  CAPTURE_ARGS=(capture --project-dir "$PROJECT_DIR" --url "$URL" --width "$WIDTH" --height "$HEIGHT"
    --out "$OUT_DIR/actual.png" --clip "$CLIP" --timeout "$TIMEOUT")
  [ -n "$SELECTOR" ] && CAPTURE_ARGS+=(--selector "$SELECTOR")
  CAPTURED="$(node "$ENGINE" "${CAPTURE_ARGS[@]}")"
  STATUS=$?
  json_set PLAYWRIGHT "$(printf '%s' "$CAPTURED" | jq -r '.PLAYWRIGHT // ""' 2>/dev/null)"
  if [ "$STATUS" -eq 3 ]; then
    unverified "$(printf '%s' "$CAPTURED" | jq -r '.CAUSE // "environment"')" \
      "$(printf '%s' "$CAPTURED" | jq -r '.REASON // "the capture did not run"')"
  fi
  [ "$STATUS" -eq 0 ] || die "the capture failed (exit $STATUS)"
fi

COMPARED="$(node "$ENGINE" compare --design "$OUT_DIR/design.png" --actual "$OUT_DIR/actual.png" \
  --diff "$OUT_DIR/diff.png" --side "$OUT_DIR/side-by-side.png")" || die "the comparison failed"

for KEY in ACTUAL_SIZE DIFF_PIXELS REGIONS REGION_COUNT SHIFTS; do
  json_set "$KEY" "$(printf '%s' "$COMPARED" | jq -r --arg k "$KEY" '.[$k] | tostring')"
done
json_set DIFF "$OUT_DIR/diff.png"
json_set SIDE_BY_SIDE "$OUT_DIR/side-by-side.png"

ACTUAL_SIZE="$(json_get ACTUAL_SIZE)"
DESIGN_SIZE="$(json_get DESIGN_SIZE)"
DIFF_PIXELS="$(json_get DIFF_PIXELS)"
COMPARED_PIXELS="$(printf '%s' "$COMPARED" | jq -r '.COMPARED_PIXELS')"
RATIO="$(awk -v d="$DIFF_PIXELS" -v c="$COMPARED_PIXELS" 'BEGIN { printf "%.4f", (c > 0 ? d / c : 1) }')"
json_set DIFF_RATIO "$RATIO"

SIZE_MATCH="$(awk -v a="$DESIGN_SIZE" -v b="$ACTUAL_SIZE" 'BEGIN {
  split(a, x, "x"); split(b, y, "x")
  dw = x[1] - y[1]; dh = x[2] - y[2]
  print ((dw <= 1 && dw >= -1 && dh <= 1 && dh >= -1) ? "true" : "false") }')"
json_set SIZE_MATCH "$SIZE_MATCH"

if [ "$SIZE_MATCH" != true ]; then
  json_set VERDICT mismatch
  json_set REASON "the UI renders at $ACTUAL_SIZE, the frame is $DESIGN_SIZE: a spacing, size or content difference adds up to the gap"
  finish 4
fi
SHIFTS="$(json_get SHIFTS)"
if [ -n "$SHIFTS" ]; then
  json_set VERDICT mismatch
  json_set REASON "content is displaced against the frame: $SHIFTS"
  finish 4
fi
if awk -v r="$RATIO" -v t="$THRESHOLD" 'BEGIN { exit !(r > t) }'; then
  json_set VERDICT mismatch
  json_set REASON "$DIFF_PIXELS pixels differ ($RATIO of the frame, above $THRESHOLD)"
  finish 4
fi
json_set VERDICT match
json_set REASON "$DIFF_PIXELS pixels differ ($RATIO of the frame, within $THRESHOLD)"
finish 0
