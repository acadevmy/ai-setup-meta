#!/usr/bin/env bash
# parse-story.sh — read a task description written by /dev-setup:story.
#
# The flows that start from a ClickUp task (sdd, quick, auto-sdd, multi-sdd)
# behave differently when the task is a story in the format the story command
# writes: its value, happy path and edge cases are already in the scenarios,
# and each scenario becomes one requirement. Recognising that format is a
# pattern match, so it is done here, once, instead of by every flow's prose.
#
# A description in any other shape is `other`, and the flow runs as it always
# did: the new format is used when it is there, never required.
#
# Usage:
#   parse-story.sh [--json] [--file <path>]
#
#   --file <path>   the description; without it, read from stdin
#   --json          emit a flat JSON object
#
# Keys:
#   FORMAT          story | epic | other
#   CONNEXTRA       the "As a …, I want …, so that …" sentence, empty when none
#   SCENARIO_COUNT  how many **Scenario:** blocks the description holds
#   SCENARIOS       newline-separated scenario titles, in order
#   OPEN_POINTS     newline-separated items of the **Open points** section
#   SECTIONS        newline-separated bold section headings, in order
#
# Exit: 0 parsed (whatever the format) · 1 usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
FILE=""

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true ;;
    --file)
      [ $# -ge 2 ] || { printf 'error: --file needs a path\n' >&2; exit 1; }
      FILE="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown argument %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

require_jq

if [ -n "$FILE" ]; then
  [ -f "$FILE" ] || { printf 'error: %s: no such file\n' "$FILE" >&2; exit 1; }
  INPUT=$(cat "$FILE")
else
  INPUT=$(cat)
fi

# One awk pass. ClickUp hands the markdown back with its own spacing — list
# items as "*   item", trailing blanks — so every match tolerates both.
PARSED=$(printf '%s\n' "$INPUT" | awk '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  {
    line = trim($0)
    if (line == "") next
    if (line ~ /^\*\*[A-Z][A-Za-z ]*\*\*$/) {
      h = line; gsub(/\*/, "", h); h = trim(h)
      print "H\t" h
      section = h
      if (h == "User Story" || h == "Introduction") want_connextra = 1
      next
    }
    if (want_connextra) {
      want_connextra = 0
      if (line ~ /^(As an? .+, I want .+, so that|Come .+, voglio .+, cos(ì|i) da)/) print "C\t" line
    }
    if (line ~ /^\*\*Scenario:\*\*/) {
      t = line; sub(/^\*\*Scenario:\*\*[ \t]*/, "", t)
      print "S\t" t
      next
    }
    if (section == "Open points" && line ~ /^[-*][ \t]+/) {
      item = line; sub(/^[-*][ \t]+/, "", item)
      print "O\t" item
    }
  }
')

field() { printf '%s\n' "$PARSED" | awk -F '\t' -v t="$1" '$1 == t { print $2 }'; }

SECTIONS=$(field H)
CONNEXTRA=$(field C | head -1)
SCENARIOS=$(field S)
OPEN_POINTS=$(field O)
SCENARIO_COUNT=0
[ -n "$SCENARIOS" ] && SCENARIO_COUNT=$(printf '%s\n' "$SCENARIOS" | wc -l | tr -d ' ')

has_section() { printf '%s\n' "$SECTIONS" | grep -qxF "$1"; }

FORMAT=other
if has_section "User Story" && [ -n "$CONNEXTRA" ] && has_section "Acceptance Criteria"; then
  FORMAT=story
elif has_section "Introduction" && has_section "Product requirement" \
     && has_section "Technical requirement" && has_section "Design requirement"; then
  FORMAT=epic
fi

json_set FORMAT "$FORMAT"
json_set CONNEXTRA "$CONNEXTRA"
json_set SCENARIO_COUNT "$SCENARIO_COUNT"
json_set SCENARIOS "$SCENARIOS"
json_set OPEN_POINTS "$OPEN_POINTS"
json_set SECTIONS "$SECTIONS"

if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
