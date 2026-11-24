#!/usr/bin/env bash
# figma-export.sh — a Figma frame as a PNG at scale 1, for visual-check.sh.
#
# The comparison is only as honest as the export: a frame rendered at 2x, or
# capped at 1024 px on its longer edge (the MCP screenshot's default), cannot
# be laid over a page rendered at device scale factor 1. So the export is
# always scale 1, PNG, and the script checks what came back: a PNG, with the
# size it reports.
#
# Two sources, one result:
#   - the REST API, with a personal access token in FIGMA_TOKEN — the headless
#     run's way, where no OAuth login exists. The token reaches curl on stdin
#     (`--config -`), never on a command line where `ps` and the logs show it.
#   - a URL the Figma MCP already returned (`download_assets` with
#     `defaultFormat: png`, `defaultScale: 1`) — the interactive way, where the
#     MCP holds the login and this script only downloads and checks the file.
#
# Usage:
#   figma-export.sh --file-key <key> --node <id> --out <png> [--json]
#   figma-export.sh --url <https url> --out <png> [--json]
#
#   --node   `12:345` or `12-345`, as figma-frames.sh or the URL gives it
#
# Output (--json): OUT, WIDTH, HEIGHT, SOURCE (rest | url), REASON.
#
# Exit code: 0 exported · 3 refused (no token, a token or id of the wrong
# shape, Figma answered with an error or no image, the download is not a PNG)
# · other = error.
#
# Environment:
#   FIGMA_TOKEN      a Figma personal access token (REST only)
#   FIGMA_API_BASE   default https://api.figma.com/v1 — the tests point it at a stub

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

FILE_KEY=""
NODE=""
URL=""
OUT=""
AS_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --file-key) FILE_KEY="${2-}"; shift 2 ;;
    --node) NODE="${2-}"; shift 2 ;;
    --url) URL="${2-}"; shift 2 ;;
    --out) OUT="${2-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) sed -n '2,33p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
command -v curl >/dev/null 2>&1 || die "curl not found"
[ -n "$OUT" ] || die "--out is required (see --help)"
if [ -n "$URL" ]; then
  [ -z "$FILE_KEY$NODE" ] || die "--url and --file-key/--node are two sources: pass one"
else
  [ -n "$FILE_KEY" ] && [ -n "$NODE" ] || die "--file-key and --node, or --url, are required (see --help)"
fi

json_set OUT "$OUT"
json_set WIDTH ""
json_set HEIGHT ""
json_set SOURCE "$([ -n "$URL" ] && echo url || echo rest)"
json_set REASON ""

finish() {
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
  exit "$1"
}
refuse() {
  json_set REASON "$1"
  finish 3
}

if [ -z "$URL" ]; then
  figma_rest_get "$FILE_KEY" "$NODE" '/images/{key}?ids={node}&format=png&scale=1' "the export" \
    || refuse "$FIGMA_REFUSAL"
  NODE="$FIGMA_NODE"
  URL="$(printf '%s' "$FIGMA_ANSWER" | jq -r --arg n "$NODE" '.images[$n] // empty')"
  [ -n "$URL" ] || refuse "Figma rendered no image for node $NODE: it is empty, hidden, or not in file $FILE_KEY"
fi

printf '%s' "$URL" | grep -qE '^https://[^[:space:]@]+$' || refuse "the image URL is not a plain https URL"
mkdir -p "$(dirname "$OUT")" || die "cannot create the folder of $OUT"
curl --silent --show-error --fail --location --max-time 120 --output "$OUT" "$URL" \
  || refuse "the image did not download (the URL is short-lived: export it again)"

SIG="$(od -An -tx1 -N8 "$OUT" 2>/dev/null | tr -d ' \n')"
[ "$SIG" = "89504e470d0a1a0a" ] || { rm -f "$OUT"; refuse "the download is not a PNG: export with format png"; }
DIMS="$(od -An -tu1 -j16 -N8 "$OUT" | awk 'NF >= 8 { printf "%d %d", $1*16777216+$2*65536+$3*256+$4, $5*16777216+$6*65536+$7*256+$8; exit }')"
json_set WIDTH "${DIMS% *}"
json_set HEIGHT "${DIMS#* }"
finish 0
