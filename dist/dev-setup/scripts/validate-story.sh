#!/usr/bin/env bash
# validate-story.sh — the structural checks on the story drafts.
#
# The `story` skill drafts every backlog item as a file in `.stories/<slug>/`:
# a YAML frontmatter the flow keeps, and a markdown body ClickUp receives. What
# a machine can check about those files is checked here, so the prose and the
# reviewer agent are left with judgement only: a rule a script enforces cannot
# be re-read charitably.
#
# Checked on every draft: the frontmatter (its keys, the type, the id and the
# file name, the relations and their targets), no `{{…}}` placeholder left, no
# `# title` in the body. Per type: a story's Connextra sentence, no conjunction
# in its "I want" clause, its scenarios (at least one, each with exactly one
# When, a Given and a Then); an epic's four requirement sections; a task's and
# a spike's sections; a story map's sections, and across the run that every
# epic is on its backbone, every story in a release lane, and its walking
# skeleton holds tasks and spikes only. English and Italian keywords are both
# accepted.
#
# Usage:
#   validate-story.sh [--json] <draft.md | folder>…
#
#   <draft.md>   one draft
#   <folder>     every *.md directly inside it
#   --json       emit a flat JSON object
#
# Keys:
#   VALID        true when no error was found (warnings do not count)
#   CHECKED      how many drafts were read
#   ITEMS        newline-separated "<id> <type> <title>", in file order
#   ERRORS       newline-separated "<file>: <message>"
#   WARNINGS     newline-separated "<file>: <message>"
#   OPEN_POINTS  newline-separated ids whose body has an **Open points** section
#
# Exit: 0 valid · 3 invalid (ERRORS says why) · 1 usage error
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
TARGETS=()

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true ;;
    -h|--help) usage; exit 0 ;;
    -*) printf 'error: unknown option %s\n' "$1" >&2; usage >&2; exit 1 ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done

[ ${#TARGETS[@]} -gt 0 ] || { printf 'error: no draft or folder given\n' >&2; usage >&2; exit 1; }
require_jq

FILES=()
for t in "${TARGETS[@]}"; do
  if [ -d "$t" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && FILES+=("$f")
    done <<EOF
$(find "$t" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
EOF
  elif [ -f "$t" ]; then
    FILES+=("$t")
  else
    printf 'error: %s: no such file or folder\n' "$t" >&2
    exit 1
  fi
done

# ── Per-file pass ─────────────────────────────────────────────────────────────
#
# One awk program per draft. It prints tagged lines: E (error), W (warning),
# I (the item: id, type, title), R (a relation target, checked across the run
# once every id is known) and O (the draft has open points).

check_file() {
  awk -v file="$1" '
    function err(m) { print "E\t" file ": " m }
    function warn(m) { print "W\t" file ": " m }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function unquote(s) { s = trim(s); gsub(/^"|"$/, "", s); return s }
    function close_scenario() {
      if (in_scen) {
        if (whens != 1) err("scenario \"" scen "\" has " whens " When steps (exactly one)")
        if (givens == 0) err("scenario \"" scen "\" has no Given step")
        if (thens == 0) err("scenario \"" scen "\" has no Then step")
        if (steps > 5) warn("scenario \"" scen "\" has " steps " steps (three to five read best)")
      }
      in_scen = 0
    }
    function close_relation() {
      if (rel_key != "") {
        if (r_title == "" || r_type == "" || r_reltype == "" || r_reason == "")
          err("relation \"" rel_key "\" needs title, type, relationType and reason")
        if (r_type != "" && r_type !~ /^(US|EPIC|TASK|SPIKE)$/)
          err("relation \"" rel_key "\" has type " r_type " (US, EPIC, TASK or SPIKE)")
        if (r_reltype != "" && r_reltype !~ /^(PARENT|BLOCKED_BY|RELATED)$/)
          err("relation \"" rel_key "\" has relationType " r_reltype " (PARENT, BLOCKED_BY or RELATED)")
        if (r_reltype == "PARENT") {
          parents++
          if (r_type != "EPIC") err("the parent \"" rel_key "\" is a " r_type ": a parent is always an EPIC")
        }
        if (rel_key == id) err("a relation points at the draft itself")
        print "R\t" file "\t" rel_key
      }
      rel_key = ""; r_title = ""; r_type = ""; r_reltype = ""; r_reason = ""
    }

    BEGIN {
      state = "start"; parents = 0; scenarios = 0; in_scen = 0; rel_key = ""
      bodyline = 0; connextra_next = 0
    }

    /\{\{/ { err("line " NR " keeps a {{…}} placeholder") }

    state == "start" {
      if ($0 != "---") { err("no frontmatter: the first line must be ---"); state = "body" }
      else state = "fm"
      next
    }

    state == "fm" {
      if ($0 == "---") { close_relation(); state = "body"; next }
      if ($0 ~ /^[A-Za-z_]+:/) {
        close_relation()
        key = $0; sub(/:.*/, "", key)
        val = $0; sub(/^[A-Za-z_]+:[ \t]*/, "", val); val = unquote(val)
        section = key
        if (key !~ /^(id|title|type|products|relations|page)$/) err("unknown frontmatter key \"" key "\"")
        if (key == "relations") has_relations = 1
        if (key == "page") has_page = 1
        if (key == "id") id = val
        else if (key == "title") title = val
        else if (key == "type") type = val
        else if (key == "products") {
          inner = val
          if (substr(inner, 1, 1) != "[" || substr(inner, length(inner), 1) != "]") inner = ""
          else inner = trim(substr(inner, 2, length(inner) - 2))
          if (inner == "") err("products must be a non-empty inline list, [shop]")
          has_products = 1
        }
        next
      }
      if (section == "relations") {
        if ($0 ~ /^  "[^"]+":[ \t]*$/) {
          close_relation()
          rel_key = $0; sub(/^  "/, "", rel_key); sub(/":.*$/, "", rel_key)
          next
        }
        if ($0 ~ /^    [A-Za-z]+:/) {
          f = $0; sub(/^    /, "", f); fk = f; sub(/:.*/, "", fk)
          fv = f; sub(/^[A-Za-z]+:[ \t]*/, "", fv); fv = unquote(fv)
          if (rel_key == "") { err("relation field \"" fk "\" outside a quoted id"); next }
          if (fk == "title") r_title = fv
          else if (fk == "type") r_type = fv
          else if (fk == "relationType") r_reltype = fv
          else if (fk == "reason") r_reason = fv
          else err("relation \"" rel_key "\" has an unknown field \"" fk "\"")
          next
        }
        if (trim($0) != "") err("relations: line " NR " is not \"  \\\"<id>\\\":\" nor a four-space field")
      }
      next
    }

    state == "body" {
      line = $0
      if (trim(line) == "") next
      bodyline++
      if (bodyline == 1 && line ~ /^# /) err("the body starts with a # title: the title lives in the frontmatter")

      if (line ~ /^\*\*[A-Z][A-Za-z ]*\*\*[ \t]*$/) {
        close_scenario()
        h = line; gsub(/\*/, "", h); h = trim(h)
        heading[h] = 1
        bsection = h
        if (h == "User Story" || h == "Introduction") connextra_next = 1
        if (h == "Open points") open_points = 1
        next
      }

      if (connextra_next) {
        connextra_next = 0
        connextra = line
      }

      # A story map cites the items it lays out as TYPE [id]: collected per
      # section, checked across the run once every draft is known.
      rest = line
      while (match(rest, /(EPIC|US|TASK|SPIKE) \[[A-Za-z0-9._-]+\]/)) {
        ref = substr(rest, RSTART, RLENGTH)
        rtype = ref; sub(/ .*/, "", rtype)
        rid = ref; sub(/^[A-Z]+ \[/, "", rid); sub(/\]$/, "", rid)
        print "M\t" bsection "\t" rtype "\t" rid
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (bsection == "DoR Check" && line ~ /^[-*][ \t]+/) dor++

      if (line ~ /^\*\*Scenario:\*\*/) {
        close_scenario()
        in_scen = 1; scenarios++
        scen = line; sub(/^\*\*Scenario:\*\*[ \t]*/, "", scen)
        whens = 0; givens = 0; thens = 0; steps = 0
        next
      }
      if (in_scen && line ~ /^\*\*(Given|When|Then|And|But|Dato|Data|Dati|Date|Quando|Allora|E|Ma)\*\*/) {
        steps++
        if (line ~ /^\*\*(When|Quando)\*\*/) whens++
        if (line ~ /^\*\*(Given|Dato|Data|Dati|Date)\*\*/) givens++
        if (line ~ /^\*\*(Then|Allora)\*\*/) thens++
      }
      next
    }

    END {
      close_scenario()
      if (state != "body") err("the frontmatter is never closed with ---")
      if (id == "") err("missing id")
      if (title == "") err("missing title")
      if (type == "") err("missing type")
      if (id != "" && id !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) err("id \"" id "\" is not a plain identifier")
      base = file; sub(/^.*\//, "", base)
      if (id != "" && base != id ".md") err("the file must be named " id ".md")
      if (type != "" && type !~ /^(US|EPIC|TASK|SPIKE|MAP)$/) err("type " type " is not US, EPIC, TASK, SPIKE or MAP")
      if (type == "MAP" && has_relations) err("a MAP has no relations: it lists its items in the body")
      if (type != "MAP" && has_page) err("page is written on a MAP only")
      if (parents > 1) err(parents " PARENT relations (at most one)")
      if (type == "EPIC" && parents > 0) err("an EPIC has no parent: the workspace nests one level")

      if (type == "US") {
        if (!("User Story" in heading)) err("no **User Story** section")
        else if (connextra == "") err("no Connextra sentence under **User Story**")
        else {
          c = connextra
          en = (c ~ /^As an? .+, I want .+, so that .+/)
          it = (c ~ /^Come .+, voglio .+, cos(ì|i) da .+/)
          if (!en && !it) err("the Connextra sentence must read \"As a …, I want …, so that …\" (or \"Come …, voglio …, così da …\")")
          else {
            want = c
            if (en) { sub(/^.*, I want /, "", want); sub(/, so that .*$/, "", want) }
            else { sub(/^.*, voglio /, "", want); sub(/, cos(ì|i) da .*$/, "", want) }
            w = " " want " "
            if (w ~ /[ ,](and|or|e|o|ed|oppure)[ ,]/) err("the \"I want\" clause has a conjunction: two features in one story")
          }
        }
        if (!("Acceptance Criteria" in heading)) err("no **Acceptance Criteria** section")
        if (scenarios == 0) err("no **Scenario:** under the acceptance criteria")
        else if (scenarios == 1) warn("one scenario: a story usually needs two to five (happy path and edge cases)")
        else if (scenarios > 5) warn(scenarios " scenarios: over five usually means split — or state the atomicity exception")
      }
      if (type == "EPIC") {
        n = split("Introduction|Product requirement|Technical requirement|Design requirement", req, "|")
        for (i = 1; i <= n; i++) if (!(req[i] in heading)) err("no **" req[i] "** section")
      }
      if (type == "TASK") {
        if (!("Task Outcome" in heading)) err("no **Task Outcome** section")
        if (!("Acceptance Criteria" in heading)) err("no **Acceptance Criteria** section")
      }
      if (type == "SPIKE") {
        n = split("Task Outcome|Timebox|Expected output|Exit criteria", req, "|")
        for (i = 1; i <= n; i++) if (!(req[i] in heading)) err("no **" req[i] "** section")
      }

      if (type == "MAP") {
        n = split("Introduction|Outcome|Backbone|Walking Skeleton|Release lanes|DoR Check", req, "|")
        for (i = 1; i <= n; i++) if (!(req[i] in heading)) err("no **" req[i] "** section")
        if (("DoR Check" in heading) && dor < 6) warn("the DoR Check has " dor + 0 " lines (six: narrative, vertical, gravity, functional, walking skeleton vs MVP, elevator pitch)")
      }

      print "I\t" id "\t" type "\t" title
      if (open_points) print "O\t" id
    }
  ' "$1"
}

ERRORS=""
WARNINGS=""
ITEMS=""
OPEN_POINTS=""
IDS=""
RELS=""
MAP_DRAFT=""
MAPS=0

add_line() { if [ -n "$1" ]; then printf '%s\n%s' "$1" "$2"; else printf '%s' "$2"; fi; }

for f in "${FILES[@]}"; do
  while IFS=$'\t' read -r tag a b c; do
    case "$tag" in
      E) ERRORS=$(add_line "$ERRORS" "$a") ;;
      W) WARNINGS=$(add_line "$WARNINGS" "$a") ;;
      I) ITEMS=$(add_line "$ITEMS" "$a $b $c"); IDS=$(add_line "$IDS" "$a")
         if [ "$b" = "MAP" ]; then MAPS=$((MAPS + 1)); MAP_DRAFT="$f"; fi ;;
      R) RELS=$(add_line "$RELS" "$a"$'\t'"$b") ;;
      O) OPEN_POINTS=$(add_line "$OPEN_POINTS" "$a") ;;
    esac
  done <<EOF
$(check_file "$f")
EOF
done

# ── Across the run ────────────────────────────────────────────────────────────

DUPS=$(printf '%s\n' "$IDS" | grep -v '^$' | LC_ALL=C sort | uniq -d)
while IFS= read -r d; do
  [ -n "$d" ] && ERRORS=$(add_line "$ERRORS" "id $d is used by more than one draft")
done <<EOF
$DUPS
EOF

# A provisional id points at a draft of this run, so it has to exist here. A
# ClickUp custom id (DE-123) points at an item that already exists.
while IFS=$'\t' read -r from target; do
  [ -n "${target:-}" ] || continue
  if printf '%s' "$target" | grep -qE '^(US|EPIC|TASK|SPIKE)-[0-9]+$' \
     && ! printf '%s\n' "$IDS" | grep -qxF "$target"; then
    ERRORS=$(add_line "$ERRORS" "$from: relation to $target, which is not drafted in this run")
  fi
done <<EOF
$RELS
EOF

# ── The story map, against the drafts it lays out ────────────────────────────

[ "$MAPS" -gt 1 ] && ERRORS=$(add_line "$ERRORS" "$MAPS story maps in one run: at most one")

if [ "$MAPS" -eq 1 ]; then
  # Only the map cites items in its body; the other drafts declare relations.
  MAPREFS=$(check_file "$MAP_DRAFT" | awk -F '\t' '$1 == "M" { print $2 "\t" $3 "\t" $4 }')
  while IFS=$'\t' read -r section rtype rid; do
    [ -n "${rid:-}" ] || continue
    if printf '%s' "$rid" | grep -qE '^(US|EPIC|TASK|SPIKE)-[0-9]+$' \
       && ! printf '%s\n' "$IDS" | grep -qxF "$rid"; then
      ERRORS=$(add_line "$ERRORS" "$MAP_DRAFT: the map cites $rtype [$rid], which is not drafted in this run")
    fi
    if [ "$section" = "Walking Skeleton" ] && [ "$rtype" != "TASK" ] && [ "$rtype" != "SPIKE" ]; then
      ERRORS=$(add_line "$ERRORS" "$MAP_DRAFT: the walking skeleton lists $rtype [$rid]: tasks and spikes only")
    fi
  done <<MAPEOF
$MAPREFS
MAPEOF
  while IFS=' ' read -r iid itype _; do
    [ -n "${iid:-}" ] || continue
    case "$itype" in
      EPIC) where="Backbone" ;;
      US) where="Release lanes" ;;
      *) continue ;;
    esac
    if ! printf '%s\n' "$MAPREFS" | awk -F '\t' -v s="$where" -v i="$iid" '$1 == s && $3 == i { found = 1 } END { exit !found }'; then
      ERRORS=$(add_line "$ERRORS" "$MAP_DRAFT: $itype [$iid] is drafted but missing from the map's $where")
    fi
  done <<MAPEOF
$ITEMS
MAPEOF
fi

VALID=true
[ -n "$ERRORS" ] && VALID=false

json_set VALID "$VALID"
json_set CHECKED "${#FILES[@]}"
json_set ITEMS "$ITEMS"
json_set ERRORS "$ERRORS"
json_set WARNINGS "$WARNINGS"
json_set OPEN_POINTS "$OPEN_POINTS"

if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi

[ "$VALID" = true ] && exit 0
exit 3
