#!/usr/bin/env bash
# figma-screens.sh — the screens behind a Figma link.
#
# A link in a task does not always point at a screen. It can point at:
#   - a screen: compared as it is;
#   - a wrapper: an annotation label above the screen, drawn for whoever reads
#     the file — the screen is its one frame child;
#   - a board: a whole flow, a section with titles, notes and every state of
#     every device side by side — each of its screens is compared on its own.
# Compared as linked, a wrapper fails on its label and a board on everything.
# This script reads the node's hierarchy and returns the screens to compare,
# so the choice is made by the same rule every time, not re-read per run.
#
# Usage:
#   figma-screens.sh --metadata <file> [--json]
#   figma-screens.sh --file-key <key> --node <id> [--json]
#
#   --metadata  what the Figma MCP's get_metadata returned for the node: its
#               XML, or the JSON array a client saved it in when it was too
#               large to show
#   --file-key/--node  the REST API instead (`/v1/files/:key/nodes`, depth 3),
#               with FIGMA_TOKEN read by curl from stdin
#
# Output (--json):
#   KIND        screen | wrapper | board
#   NAME        the linked node's name
#   COUNT       number of screens
#   SCREENS     one line per screen: <node_id>\t<name>\t<W>x<H>\t<label>\t<wrapper_id>
#               — the label and the wrapper empty for a screen with none
#   MISMATCHED  one line per wrapper whose label does not end its name
#               (`D · Home · Start screen` labelled `Empty
#               password`): which state the frame draws is in doubt, and the
#               merge request says so
#   SOURCE      metadata | rest
#   REASON      on exit 3, why
#
# The rule: a wrapper is a frame with a text child and exactly one frame-like
# child. A board is a section, or a frame with at least two wrappers among its
# children, or with at least two side-by-side children of 320 px or more on
# each side. Anything else is a screen. Text on a board — titles, notes — is
# never a screen, nor is a frame holding only text under 120 px on a side (an
# eyebrow badge).
#
# Exit code: 0 · 3 refused (no token, Figma error, nothing readable) · other = error.
#
# Environment: FIGMA_TOKEN, FIGMA_API_BASE (as figma-export.sh)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

METADATA=""
FILE_KEY=""
NODE=""
AS_JSON=false
API_BASE="${FIGMA_API_BASE:-https://api.figma.com/v1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --metadata) METADATA="${2-}"; shift 2 ;;
    --file-key) FILE_KEY="${2-}"; shift 2 ;;
    --node) NODE="${2-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) sed -n '2,47p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
json_set KIND ""
json_set NAME ""
json_set COUNT ""
json_set SCREENS ""
json_set MISMATCHED ""
json_set SOURCE "$([ -n "$METADATA" ] && echo metadata || echo rest)"
json_set REASON ""

finish() {
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
  exit "$1"
}
refuse() {
  json_set REASON "$1"
  finish 3
}

# Every source becomes one tree: {id, name, kind (frame | section | text |
# other), w, h, x, y, children}.
if [ -n "$METADATA" ]; then
  [ -f "$METADATA" ] || die "metadata file not found: $METADATA"
  RAW="$(jq -r 'if type == "array" then map(.text // "") | join("\n") else . end' "$METADATA" 2>/dev/null || cat "$METADATA")"
  # get_metadata prints one element per line, indented two spaces a level:
  # the depth is the indentation, and three levels are all the rule reads.
  TREE="$(printf '%s\n' "$RAW" | awk '
    function attr(s, k) {
      if (match(s, " " k "=\"[^\"]*\"")) return substr(s, RSTART + length(k) + 3, RLENGTH - length(k) - 4)
      return ""
    }
    /^ *<[a-z-]+ / {
      match($0, /^ */); depth = RLENGTH / 2
      tag = $0; sub(/^ *</, "", tag); sub(/ .*/, "", tag)
      if (depth > 3) next
      printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", depth, tag, attr($0, "id"), attr($0, "name"),
        attr($0, "x"), attr($0, "y"), attr($0, "width"), attr($0, "height")
    }' | jq -R -s '
      def kind: if . == "text" then "text" elif . == "section" then "section"
                elif (. == "frame" or . == "instance" or . == "symbol" or . == "component" or . == "group") then "frame"
                else "other" end;
      def nest($rows; $d):
        if ($rows | length) == 0 then []
        else
          ($rows | to_entries | map(select(.value.depth == $d) | .key)) as $starts
          | [ range(0; $starts | length) as $i
              | $rows[$starts[$i]] + {children: nest($rows[($starts[$i] + 1):($starts[$i + 1] // ($rows | length))]; $d + 1)} ]
        end;
      split("\n") | map(select(. != "") | split("\t")
        | {depth: (.[0] | tonumber), kind: (.[1] | kind), id: .[2], name: (.[3] | gsub("&quot;"; "\"") | gsub("&amp;"; "&")),
           x: ((.[4] | tonumber?) // 0), y: ((.[5] | tonumber?) // 0),
           w: ((.[6] | tonumber?) // 0), h: ((.[7] | tonumber?) // 0)})
      | nest(.; 0) | .[0] // empty')"
else
  [ -n "$FILE_KEY" ] && [ -n "$NODE" ] || die "--metadata, or --file-key and --node, are required (see --help)"
  command -v curl >/dev/null 2>&1 || die "curl not found"
  printf '%s' "$FILE_KEY" | grep -qE '^[A-Za-z0-9]{10,128}$' || refuse "\"$FILE_KEY\" is not a Figma file key"
  NODE="$(printf '%s' "$NODE" | tr '-' ':')"
  printf '%s' "$NODE" | grep -qE '^[0-9]+:[0-9]+$' || refuse "\"$NODE\" is not a node id (12:345)"
  TOKEN="${FIGMA_TOKEN:-}"
  [ -n "$TOKEN" ] || refuse "FIGMA_TOKEN is not set: reading the node over the REST API needs a Figma personal access token"
  printf '%s' "$TOKEN" | grep -qE '^[A-Za-z0-9_-]+$' \
    || refuse "FIGMA_TOKEN does not look like a Figma token (letters, digits, dash, underscore)"
  ANSWER="$(printf 'header = "X-Figma-Token: %s"\n' "$TOKEN" \
    | curl --silent --show-error --max-time 60 --config - \
        "$API_BASE/files/$FILE_KEY/nodes?ids=${NODE/:/%3A}&depth=3")" \
    || refuse "Figma did not answer: the API is unreachable from here"
  printf '%s' "$ANSWER" | jq -e . >/dev/null 2>&1 || refuse "Figma answered with something that is not JSON"
  ERR="$(printf '%s' "$ANSWER" | jq -r '.err // empty | tostring')"
  [ -z "$ERR" ] || refuse "Figma refused the read: $ERR"
  TREE="$(printf '%s' "$ANSWER" | jq --arg n "$NODE" '
    def kind: if . == "TEXT" then "text" elif . == "SECTION" then "section"
              elif (. == "FRAME" or . == "INSTANCE" or . == "COMPONENT" or . == "COMPONENT_SET" or . == "GROUP") then "frame"
              else "other" end;
    def conv: {id, name, kind: (.type | kind),
               x: (.absoluteBoundingBox.x // 0), y: (.absoluteBoundingBox.y // 0),
               w: (.absoluteBoundingBox.width // 0), h: (.absoluteBoundingBox.height // 0),
               children: ((.children // []) | map(conv))};
    .nodes[$n].document // empty | conv')"
fi

[ -n "$TREE" ] && [ "$TREE" != null ] || refuse "nothing readable: no node in what was given"

RESULT="$(printf '%s' "$TREE" | jq '
  def frames: (.children // []) | map(select(.kind == "frame" or .kind == "section"));
  def texts: (.children // []) | map(select(.kind == "text"));
  def wrapper: (texts | length) >= 1 and (frames | length) == 1;
  def overlaps($a; $b): ($a.x < $b.x + $b.w) and ($b.x < $a.x + $a.w) and ($a.y < $b.y + $b.h) and ($b.y < $a.y + $a.h);
  def board:
    .kind == "section"
    or ([(.children // [])[] | select(wrapper)] | length) >= 2
    or ((frames | map(select(.w >= 320 and .h >= 320))) as $big
        | ($big | length) >= 2
          and ([range(0; $big | length) as $i | range($i + 1; $big | length) as $j
                | select(overlaps($big[$i]; $big[$j]))] | length) == 0);
  def screen($wrap):
    if $wrap != null then
      ($wrap | frames[0]) as $s
      | {id: $s.id, name: $s.name, w: $s.w, h: $s.h, label: ($wrap | texts[0].name), wrapper: $wrap.id, wrapperName: $wrap.name}
    else {id, name, w, h, label: "", wrapper: "", wrapperName: ""} end;
  . as $root
  | if board then
      {kind: "board", screens: [frames[]
        | if wrapper then screen(.)
          # A badge or a title box on the board is not a screen: it holds only
          # text, or it is too small on one side to be a page or a component.
          elif ((.children // []) | any(.kind != "text")) or ([.w, .h] | min) >= 120 then screen(null)
          else empty end]}
    elif wrapper then {kind: "wrapper", screens: [screen($root)]}
    else {kind: "screen", screens: [screen(null)]} end
  | .name = $root.name
  | .mismatched = [.screens[] | . as $s
                   | select($s.label != "" and ($s.wrapperName | ascii_downcase | endswith($s.label | ascii_downcase) | not))
                   | "\($s.wrapper)\t\($s.wrapperName)\tlabelled \($s.label)"]')" \
  || die "the hierarchy could not be read"

json_set KIND "$(printf '%s' "$RESULT" | jq -r .kind)"
json_set NAME "$(printf '%s' "$RESULT" | jq -r .name)"
json_set COUNT "$(printf '%s' "$RESULT" | jq -r '.screens | length')"
json_set SCREENS "$(printf '%s' "$RESULT" | jq -r '.screens[] | [.id, .name, "\(.w | floor)x\(.h | floor)", .label, .wrapper] | join("\t")')"
json_set MISMATCHED "$(printf '%s' "$RESULT" | jq -r '.mismatched | join("\n")')"
finish 0
