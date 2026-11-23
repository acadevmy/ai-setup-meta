#!/usr/bin/env bash
# figma-frames.sh — the Figma frames a task points at.
#
# A visual check compares the UI with a frame, and a frame is a node: a link to
# the bare file names a whole canvas, not something a page can be compared
# with. This script reads a task description — a story's **Design** section,
# or links written anywhere in the text — and returns every frame link in it,
# with the file key and the node id the Figma tools take. The bare file links
# are returned apart, so the caller can say which design it could not check.
#
# Usage:
#   figma-frames.sh [--file <path>] [--json]     (default: the text on stdin)
#
# Output (--json):
#   COUNT        number of distinct frames
#   FRAMES       one line per frame: <file_key>\t<node_id>\t<name>\t<url> —
#                the node id with a colon (`12:345`), the name the link text
#                gave or empty, the URL as written
#   BARE_FILES   the design links with no node-id, one per line
#
# `/design/`, `/file/` and `/proto/` links count; a branch URL gives its branch
# key; FigJam (`/board/`), Slides and Make links are not frames of a UI and are
# ignored. Exit 0 whatever was found: no frame is an answer, not a failure.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

FILE=""
AS_JSON=false
while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="${2-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || die "file not found: $FILE"
  TEXT="$(cat "$FILE")"
else
  TEXT="$(cat)"
fi

PARSED="$(printf '%s' "$TEXT" | jq -Rs '
  def parse($name; $url):
    $url
    | capture("figma\\.com/(?<kind>design|file|proto)/(?<key>[A-Za-z0-9]+)(?:/branch/(?<branch>[A-Za-z0-9]+))?") as $m
    | (([$url | capture("[?&]node-id=(?<id>[0-9]+(?:-|:|%3[Aa])[0-9]+)") | .id] | first) // "") as $id
    | { key: ($m.branch // $m.key),
        node: ($id | gsub("%3[Aa]"; ":") | gsub("-"; ":")),
        name: $name, url: $url };
  . as $t
  | ([ $t | scan("\\[([^\\]]*)\\]\\((https?://(?:www\\.)?figma\\.com/[^)\\s]+)\\)") | parse(.[0]; .[1]) ]) as $linked
  | ([ $t | scan("https?://(?:www\\.)?figma\\.com/[^)\\s>\\]]+") | sub("[.,;:!?]+$"; "") | parse(""; .) ]) as $bare
  | ($linked + $bare) as $all
  | ($all | map(select(.node != "")) | reduce .[] as $f ([]; if any(.[]; .key == $f.key and .node == $f.node) then . else . + [$f] end)) as $frames
  | { frames: $frames,
      bare: ($all | map(select(.node == "") | .url) | unique) }
')" || die "could not read the text"

json_set COUNT "$(printf '%s' "$PARSED" | jq -r '.frames | length')"
json_set FRAMES "$(printf '%s' "$PARSED" | jq -r '.frames[] | [.key, .node, .name, .url] | join("\t")')"
json_set BARE_FILES "$(printf '%s' "$PARSED" | jq -r '.bare | join("\n")')"

if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
