#!/usr/bin/env bash
# validate-plugin.sh — static checks on the quality of the distributed skills.
#
# Usage: bash scripts/validate-plugin.sh [OPTIONS]
#
# Options:
#   --json              Machine-readable output on stdout (UPPER_SNAKE keys)
#   --strict            Ignore the baseline: report the repo's real state
#   --fail-on-stale     Fail if the baseline holds entries already fixed
#   --update-baseline   Rewrite the baseline with the current findings
#   --baseline FILE     Alternative baseline (default: scripts/validate-baseline.txt)
#   -h, --help          This message
#
# Exit code: 0 = ok · 1 = findings not in the baseline · 2 = usage or dependency error
#
# Prerequisites: jq
#
# The checks (numbering from DE-16471):
#   1  SKILL_LINES             SKILL.md over 500 lines
#   2  SKILL_WORDS             SKILL.md over 500 words (200 when force-loaded)
#   3  DESCRIPTION_TRIGGER     description with no trigger clause ("Use when...")
#   4  DESCRIPTION_LENGTH      description over 1024 characters
#   5  REFERENCE_DEPTH         reference not linked directly from SKILL.md
#   6  REFERENCE_INDEX         reference over 100 lines with no index at the top
#   7  FORCE_LOAD_REFERENCE    an @path reference to a reference file
#   8  COMMAND_SKILL_DUPLICATE commands/x.md whose body matches skills/x/SKILL.md
#   9  RULE_TEMPLATE           a path-scoped rule template with the wrong shape
#   10 MANIFEST_ORPHAN         asset declared in the manifest and never referenced
#   11 MARKETPLACE_SOURCE      marketplace.json entry with an inconsistent source or version
#   12 LEGACY_RUNTIME_RESIDUE  a reference to Cursor/Codex/Gemini in the artefacts
#   13 WORKFLOW_CONTRACT       a workflow script the harness would refuse or misgroup
#   14 DOC_REFERENCE           the docs cite a command, script, path or rule that does not exist
#   15 DOC_COMMAND_COVERAGE    a public command the user guide never documents
#
# Checks 11 to 15 are not in the original list: they are regression guards on
# defects the chain removed (the broken `pm-setup` entry, DE-16471; the
# Cursor/Codex/Gemini support, DE-16489), on the one artefact whose mistakes
# only surface at run time (the workflow scripts, DE-16479), and on the one
# artefact nothing else validates at all (the documentation, DE-16488).
# ---8<--- end of the --help message
#
# Scoping notes:
#   - Check 2 applies the reduced budget (200) only to skills force-loaded with
#     `@path` from AGENTS/rules/profiles: they are the only ones always in context.
#   - Check 10 applies only to the assets the prose has to pull in (profiles,
#     rules, boilerplate, required_files). Skills and agents declared in the manifest are
#     entry points the runtime registers: not being cited by other prose is not a
#     defect. The legacy `agent` field is no longer read: the domain agent was
#     replaced by the setup skill (PR 2).
#   - Check 12 greps for the bare string: the same grep as the DE-16489 acceptance
#     criterion. If some legitimate rule ever has to use one of those words (say,
#     cursor-based pagination), narrow the check's pattern — do not baseline the
#     finding.
#   - Checks 14 and 15 read the two root documents and the top level of `docs/`.
#     `docs/legacy/` is archived material, outside the product and outside the
#     check. One live page is excluded too — the v2→v3 migration page, whose
#     subject is precisely the things that were removed. Nothing else belongs on
#     that list: a document that has to name a dead reference belongs in the
#     migration page.
#   - Check 13 reads the `export const meta` block the harness itself parses. A
#     wrong extension, a missing meta, a name that does not match the file or a
#     `phase()` with no entry in `meta.phases` are all silent at load time: the
#     loader skips the file, or the progress tree grows a stray group. The
#     forbidden globals (`Date.now`, `Math.random`, `new Date`, `require`, and
#     the `process.*` API) throw inside the workflow VM, and only once the run is
#     under way.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/builders/common.sh
source "${SCRIPT_DIR}/builders/common.sh"

MAX_SKILL_LINES=500
MAX_SKILL_WORDS=500
MAX_SKILL_WORDS_FORCE_LOADED=200
MAX_DESCRIPTION_CHARS=1024
MAX_REFERENCE_LINES=100

# Clauses accepted as a trigger in the description (check 3).
TRIGGER_PATTERN='use when|use this when'

OPT_JSON=false
OPT_STRICT=false
OPT_FAIL_ON_STALE=false
OPT_UPDATE_BASELINE=false
BASELINE_FILE="${SCRIPT_DIR}/validate-baseline.txt"

# The file header up to the sentinel: the list of checks grows, the line numbers
# do not.
usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

die() { echo "validate-plugin: $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --json)            OPT_JSON=true ;;
    --strict)          OPT_STRICT=true ;;
    --fail-on-stale)   OPT_FAIL_ON_STALE=true ;;
    --update-baseline) OPT_UPDATE_BASELINE=true ;;
    --baseline)        shift; [ $# -gt 0 ] || die "--baseline needs a path"; BASELINE_FILE="$1" ;;
    -h|--help)         usage; exit 0 ;;
    *)                 die "unrecognised option: $1 (see --help)" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq not found. Install it with: brew install jq"

# In --json mode the builders' human output (ok/warn/step) has to be suppressed:
# stdout must hold nothing but the JSON.
if [ "$OPT_JSON" = true ]; then
  ok()   { :; }
  warn() { :; }
  step() { :; }
fi

# The explicit template is needed under the sandbox: on macOS a bare `mktemp -d`
# uses the system temp dir (_CS_DARWIN_USER_TEMP_DIR) and ignores $TMPDIR, which
# the sandbox denies. With a template, mktemp honours $TMPDIR.
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/validate-plugin.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

FINDINGS="$TMP_DIR/findings.tsv"   # CHECK_ID \t SCOPE \t FILE \t LINE \t KEY \t MESSAGE
SKILLS="$TMP_DIR/skills.tsv"       # SCOPE \t NAME \t SKILL_MD \t SKILL_DIR (empty when not applicable)
: > "$FINDINGS"
: > "$SKILLS"

# ── Helper ───────────────────────────────────────────────────────────────────

# Path relative to the repo root (findings are always repo-relative).
rel() { echo "${1#"${REPO_ROOT}"/}"; }

# add_finding CHECK_ID SCOPE FILE LINE KEY MESSAGE
add_finding() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$FINDINGS"
}

# The YAML frontmatter block (between the first and second `---` line).
frontmatter() {
  awk 'NR==1 && $0!="---" { exit } NR==1 { next } /^---[[:space:]]*$/ { exit } { print }' "$1"
}

# The value of a scalar frontmatter key, including indented continuation lines
# (for multi-line description: > and description: |).
fm_value() {
  frontmatter "$1" | awk -v key="$2" '
    $0 ~ "^" key ":" {
      sub("^" key ":[[:space:]]*", "")
      # Folded/literal scalars: the real value lives on the following lines.
      if ($0 == ">" || $0 == "|" || $0 == ">-" || $0 == "|-") { $0 = "" }
      val = $0
      while ((getline line) > 0) {
        if (line ~ /^[[:space:]]+[^[:space:]]/) {
          sub(/^[[:space:]]+/, "", line)
          val = (val == "" ? line : val " " line)
        } else { break }
      }
      print val
      exit
    }'
}

# The file body after the frontmatter (the whole file when there is none).
body_after_frontmatter() {
  if [ "$(head -1 "$1")" = "---" ]; then
    awk 'NR==1 { next } !seen && /^---[[:space:]]*$/ { seen=1; next } seen' "$1"
  else
    cat "$1"
  fi
}

# Body normalised for check 8's comparison: blank lines and trailing whitespace
# stripped, so a difference is one of content and not of formatting.
norm_body() {
  body_after_frontmatter "$1" | sed 's/[[:space:]]*$//' | grep -v '^$' || true
}

# Tokens that look like .md paths inside a file.
md_links() {
  grep -o -E '[A-Za-z0-9_][A-Za-z0-9_./-]*\.md' "$1" 2>/dev/null | sed 's|^\./||' | sort -u || true
}

# ── Skill inventory ──────────────────────────────────────────────────────────
# Distributed surface: templates/<t>/.claude/skills/, shared/skills/ and the setup
# skill (which the build mounts as skills/setup/SKILL.md).
# Meta surface: the meta-repo's .claude/skills/, not distributed but held to the
# same hygiene.
collect_skills() {
  local d f name
  for d in "$REPO_ROOT"/templates/*/.claude/skills/*/; do
    f="${d}SKILL.md"; [ -f "$f" ] || continue
    printf 'DISTRIBUTED\t%s\t%s\t%s\n' "$(basename "$d")" "$(rel "$f")" "$(rel "${d%/}")" >> "$SKILLS"
  done
  for d in "$REPO_ROOT"/shared/skills/*/; do
    f="${d}SKILL.md"; [ -f "$f" ] || continue
    printf 'DISTRIBUTED\t%s\t%s\t%s\n' "$(basename "$d")" "$(rel "$f")" "$(rel "${d%/}")" >> "$SKILLS"
  done
  # The setup skill lives outside .claude/skills/ — the build mounts it at
  # skills/setup/. Its path comes from the manifest, and since DE-16478 it is a
  # directory with a reference/ of its own, so it is checked like any other skill.
  local manifest setup_rel
  for manifest in "$REPO_ROOT"/templates/*/manifest.json; do
    [ -f "$manifest" ] || continue
    setup_rel="$(jq -r '.setup_skill // empty' "$manifest")"
    [ -n "$setup_rel" ] || continue
    f="$(dirname "$manifest")/$setup_rel"
    [ -f "$f" ] || continue
    printf 'DISTRIBUTED\tsetup\t%s\t%s\n' "$(rel "$f")" "$(rel "$(dirname "$f")")" >> "$SKILLS"
  done
  for d in "$REPO_ROOT"/.claude/skills/*/; do
    f="${d}SKILL.md"; [ -f "$f" ] || continue
    printf 'META\t%s\t%s\t%s\n' "$(basename "$d")" "$(rel "$f")" "$(rel "${d%/}")" >> "$SKILLS"
  done
}

# A skill is "always loaded" when something force-loads it with @path from
# AGENTS/rules/profiles: only then does its body enter every session.
is_force_loaded() {
  local skill_md="$1"
  grep -r -q -E "@[A-Za-z0-9_./-]*$(basename "$(dirname "$skill_md")")/SKILL\.md" \
    "$REPO_ROOT"/templates/*/AGENTS*.md \
    "$REPO_ROOT"/templates/*/CLAUDE*.md \
    "$REPO_ROOT"/templates/*/profiles/*.md \
    "$REPO_ROOT"/templates/*/.claude/rules/*.md \
    2>/dev/null
}

# ── Checks 1-4: skill budgets and frontmatter ────────────────────────────────
check_skill_budget_and_frontmatter() {
  step "Checks 1-4 — line/word budgets and skill frontmatter"
  local scope name skill_md skill_dir abs lines words desc budget
  while IFS=$'\t' read -r scope name skill_md skill_dir; do
    [ -n "${skill_md:-}" ] || continue
    abs="$REPO_ROOT/$skill_md"

    lines=$(wc -l < "$abs" | tr -d ' ')
    if [ "$lines" -gt "$MAX_SKILL_LINES" ]; then
      add_finding SKILL_LINES "$scope" "$skill_md" 0 "$skill_md" \
        "$lines lines (max $MAX_SKILL_LINES): move the detail into reference/"
    fi

    words=$(wc -w < "$abs" | tr -d ' ')
    budget=$MAX_SKILL_WORDS
    if is_force_loaded "$skill_md"; then budget=$MAX_SKILL_WORDS_FORCE_LOADED; fi
    if [ "$words" -gt "$budget" ]; then
      add_finding SKILL_WORDS "$scope" "$skill_md" 0 "$skill_md" \
        "$words words (max $budget): move the detail into reference/"
    fi

    desc=$(fm_value "$abs" description)
    if [ -z "$desc" ]; then
      add_finding DESCRIPTION_TRIGGER "$scope" "$skill_md" 0 "$skill_md" \
        "frontmatter senza description"
    else
      if ! printf '%s' "$desc" | grep -q -i -E "$TRIGGER_PATTERN"; then
        add_finding DESCRIPTION_TRIGGER "$scope" "$skill_md" 0 "$skill_md" \
          "description with no trigger clause (expected: Use when / Use this when)"
      fi
      if [ "${#desc}" -gt "$MAX_DESCRIPTION_CHARS" ]; then
        add_finding DESCRIPTION_LENGTH "$scope" "$skill_md" 0 "$skill_md" \
          "description di ${#desc} caratteri (max $MAX_DESCRIPTION_CHARS)"
      fi
    fi
  done < "$SKILLS"
}

# ── Checks 5-6: structure of the reference files ─────────────────────────────
check_references() {
  step "Checks 5-6 — depth and index of the reference files"
  local scope name skill_md skill_dir abs_dir refs ref rel_ref direct linked_from other
  while IFS=$'\t' read -r scope name skill_md skill_dir; do
    [ -n "${skill_dir:-}" ] || continue
    abs_dir="$REPO_ROOT/$skill_dir"
    [ -d "$abs_dir" ] || continue

    refs=$(find "$abs_dir" -type f -name '*.md' ! -name 'SKILL.md' 2>/dev/null | sort || true)
    [ -n "$refs" ] || continue

    direct="$TMP_DIR/direct.txt"
    md_links "$abs_dir/SKILL.md" > "$direct"

    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      rel_ref="${ref#"${abs_dir}"/}"

      # Linked directly from SKILL.md? (relative path or bare basename)
      if grep -q -x -F "$rel_ref" "$direct" || grep -q -x -F "$(basename "$ref")" "$direct"; then
        : # depth 1, ok
      else
        linked_from=""
        while IFS= read -r other; do
          [ "$other" = "$ref" ] && continue
          if md_links "$other" | grep -q -x -F -e "$rel_ref" -e "$(basename "$ref")"; then
            linked_from="$(rel "$other")"; break
          fi
        done <<< "$refs"
        if [ -n "$linked_from" ]; then
          add_finding REFERENCE_DEPTH "$scope" "$(rel "$ref")" 0 "$(rel "$ref")" \
            "reachable only through $linked_from (depth >= 2 from SKILL.md)"
        else
          add_finding REFERENCE_DEPTH "$scope" "$(rel "$ref")" 0 "$(rel "$ref")" \
            "unreachable: no link from SKILL.md nor from any other reference"
        fi
      fi

      if [ "$(wc -l < "$ref" | tr -d ' ')" -gt "$MAX_REFERENCE_LINES" ] && ! has_index "$ref"; then
        add_finding REFERENCE_INDEX "$scope" "$(rel "$ref")" 0 "$(rel "$ref")" \
          "$(wc -l < "$ref" | tr -d ' ') lines (> $MAX_REFERENCE_LINES) with no index in the first 40"
      fi
    done <<< "$refs"
  done < "$SKILLS"
}

# An index at the top: an Index/Indice/Contents/Sommario heading, or at least two
# list entries linking to anchors or other .md files, within the first 40 lines.
has_index() {
  local head40
  head40=$(head -40 "$1")
  if printf '%s\n' "$head40" | grep -q -i -E '^#+[[:space:]]+(index|indice|contents|table of contents|sommario)'; then
    return 0
  fi
  if [ "$(printf '%s\n' "$head40" | grep -c -E '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+.*\]\((#|[A-Za-z0-9_./-]+\.md)')" -ge 2 ]; then
    return 0
  fi
  return 1
}

# ── Check 7: force-loading a reference file ──────────────────────────────────
check_force_load() {
  step "Check 7 — @path force-loads pointing at reference files"
  local f line no token target
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      no="${line%%:*}"
      token=$(printf '%s' "${line#*:}" | grep -o -E '@[A-Za-z0-9_./-]+\.md' | head -1)
      [ -n "$token" ] || continue
      target="${token#@}"
      # A force-load counts as a defect only when it points inside a skill and is
      # not the SKILL.md itself: that is content meant to stay on-demand.
      case "$target" in
        */SKILL.md) continue ;;
        */skills/*|reference/*|references/*)
          add_finding FORCE_LOAD_REFERENCE DISTRIBUTED "$(rel "$f")" "$no" "$(rel "$f"):$target" \
            "force-load '$token': reference files are meant to be linked, not injected"
          ;;
      esac
    done < <(grep -n -E '(^|[[:space:]])@[A-Za-z0-9_./-]+\.md' "$f" 2>/dev/null || true)
  done < <(find "$REPO_ROOT/templates" "$REPO_ROOT/shared" -type f -name '*.md' 2>/dev/null | sort)
}

# ── Check 8: commands duplicating a skill ────────────────────────────────────
check_command_duplicates() {
  step "Check 8 — commands/ whose body matches the skill of the same name"
  local cmd name skill_md
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    name="$(basename "$cmd" .md)"
    skill_md=$(awk -F'\t' -v n="$name" '$2==n { print $3; exit }' "$SKILLS")
    [ -n "$skill_md" ] || continue
    if diff -q <(norm_body "$cmd") <(norm_body "$REPO_ROOT/$skill_md") >/dev/null 2>&1; then
      add_finding COMMAND_SKILL_DUPLICATE DISTRIBUTED "$(rel "$cmd")" 0 "$(rel "$cmd")" \
        "body identical to $skill_md: it duplicates the public surface"
    fi
  done < <(find "$REPO_ROOT/dist" "$REPO_ROOT/templates" -type d -name commands -exec find {} -type f -name '*.md' \; 2>/dev/null | sort)
}

# ── Check 9: the path-scoped rule templates ──────────────────────────────────
# The rules replaced the CONSTITUTION the setup used to copy whole (DE-16477).
# What made that document a defect was that nothing checked its shape, so this
# check holds the replacement to the three properties the design depends on:
#   - exactly one rule loads unconditionally, and it is `core.md`. A second one
#     without `paths:` silently doubles what every session pays for.
#   - `core.md` stays within the budget the audit set (150 lines).
#   - every other rule declares at least one glob under `paths:`.
# A placeholder in a `paths:` value is fine — render-template.sh resolves it and
# fails loudly when it cannot.
CORE_RULE_MAX_LINES=150

check_rule_templates() {
  step "Check 9 — shape of the path-scoped rule templates"
  local manifest tdir tname rule abs fm unscoped count lines
  for manifest in "$REPO_ROOT"/templates/*/manifest.json; do
    [ -f "$manifest" ] || continue
    tdir="$(dirname "$manifest")"; tname="$(basename "$tdir")"

    unscoped=""
    count=0
    while IFS= read -r rule; do
      [ -n "$rule" ] || continue
      count=$((count + 1))
      abs="$tdir/rules/$rule"
      if [ ! -f "$abs" ]; then
        add_finding RULE_TEMPLATE DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):$rule" \
          "declares 'rules/$rule', which does not exist"
        continue
      fi

      fm="$(frontmatter "$abs")"
      if printf '%s' "$fm" | grep -q '^paths:'; then
        # `paths:` must carry at least one entry, as a list item or inline.
        if ! printf '%s' "$fm" | grep -qE '^[[:space:]]*-[[:space:]]*["'"'"']?[^"'"'"'[:space:]]' \
          && ! printf '%s' "$fm" | grep -qE '^paths:[[:space:]]*\[.*[^][:space:]].*\]'; then
          add_finding RULE_TEMPLATE DISTRIBUTED "$(rel "$abs")" 1 "$(rel "$abs"):paths" \
            "declares 'paths:' with no glob under it"
        fi
      else
        unscoped="$unscoped $rule"
      fi

      if [ "$rule" = "core.md" ]; then
        lines=$(wc -l < "$abs" | tr -d ' ')
        if [ "$lines" -gt "$CORE_RULE_MAX_LINES" ]; then
          add_finding RULE_TEMPLATE DISTRIBUTED "$(rel "$abs")" 1 "$(rel "$abs"):lines" \
            "core rule is $lines lines, over the $CORE_RULE_MAX_LINES-line budget"
        fi
      fi
    done < <(jq -r '.rules[]? // empty' "$manifest")

    [ "$count" -gt 0 ] || continue

    case "$(printf '%s' "$unscoped" | tr -s ' ')" in
      " core.md"|"core.md") ;;
      "")
        add_finding RULE_TEMPLATE DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):unscoped" \
          "no rule loads unconditionally: core.md must have no 'paths:' frontmatter" ;;
      *)
        add_finding RULE_TEMPLATE DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):unscoped" \
          "more than one rule loads unconditionally (${unscoped# }): only core.md may omit 'paths:'" ;;
    esac
  done
}

# ── Check 10: manifest assets that nothing references ────────────────────────
check_manifest_orphans() {
  step "Check 10 — manifest assets no skill references"
  local manifest tdir tname corpus declared decl abs base cf referenced
  # Corpus = the prose the runtime actually loads: skills and agents. CHANGELOGs
  # and documentation templates stay out, because they cite assets without loading
  # them (and would keep dead manifest entries alive).
  corpus="$TMP_DIR/corpus.txt"
  {
    awk -F'\t' '{ print $3 }' "$SKILLS"
    # A skill's reference files are prose the runtime loads on demand: an asset
    # cited only from one of them is cited (DE-16478).
    awk -F'\t' '$4 != "" { print $4 }' "$SKILLS" \
      | while IFS= read -r d; do
          [ -d "$REPO_ROOT/$d" ] || continue
          find "$REPO_ROOT/$d" -type f -name '*.md' ! -name 'SKILL.md' 2>/dev/null \
            | sed "s|^${REPO_ROOT}/||"
        done
    find "$REPO_ROOT"/templates/*/.claude/reference -type f -name '*.md' 2>/dev/null \
      | sed "s|^${REPO_ROOT}/||"
    find "$REPO_ROOT"/shared/agents "$REPO_ROOT"/templates/*/.claude/agents \
      -type f -name '*.md' 2>/dev/null | sed "s|^${REPO_ROOT}/||"
  } | sort -u > "$corpus"

  for manifest in "$REPO_ROOT"/templates/*/manifest.json; do
    [ -f "$manifest" ] || continue
    tdir="$(dirname "$manifest")"; tname="$(basename "$tdir")"

    declared="$TMP_DIR/declared-$tname.txt"
    {
      jq -r '.profiles[]? | "profiles/" + .' "$manifest"
      jq -r '.rules[]? | "rules/" + .' "$manifest"
      jq -r '.boilerplate_files[]? | "boilerplate/" + .' "$manifest"
      jq -r '.required_files[]?' "$manifest"
    } | sort -u > "$declared"

    while IFS= read -r decl; do
      [ -n "$decl" ] || continue
      abs="$tdir/$decl"
      if [ ! -e "$abs" ]; then
        add_finding MANIFEST_ORPHAN DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):$decl" \
          "declares 'templates/$tname/$decl', which does not exist"
        continue
      fi
      base="$(basename "$decl")"
      # Referenced when a skill's or agent's prose names it (even by basename alone).
      referenced=false
      while IFS= read -r cf; do
        [ -n "$cf" ] || continue
        [ "$REPO_ROOT/$cf" = "$abs" ] && continue
        if grep -q -F -- "$base" "$REPO_ROOT/$cf" 2>/dev/null; then referenced=true; break; fi
      done < "$corpus"
      if [ "$referenced" = false ]; then
        add_finding MANIFEST_ORPHAN DISTRIBUTED "$(rel "$manifest")" 0 "$(rel "$manifest"):$decl" \
          "'$decl' is declared in the manifest but no skill cites it: remove it or reference it"
      fi
    done < "$declared"
  done
}

# ── Check 11: marketplace catalogue integrity ────────────────────────────────
# Claude Code is the only build target (DE-16489): one catalogue to check,
# `.claude-plugin/marketplace.json`.
CATALOG_DIR=".claude-plugin"

check_marketplace() {
  step "Check 11 — source and version of the marketplace.json entries"
  local catalog mp name source version src_dir plugin_json plugin_version
  catalog="$REPO_ROOT/$CATALOG_DIR/marketplace.json"
  [ -f "$catalog" ] || return 0
  mp="$(rel "$catalog")"

  while IFS=$'\t' read -r name source version; do
    [ -n "$name" ] || continue
    case "$source" in
      ./*) src_dir="$REPO_ROOT/${source#./}" ;;
      *)   continue ;;  # remote sources: not verifiable offline
    esac

    if [ ! -d "$src_dir" ]; then
      add_finding MARKETPLACE_SOURCE DISTRIBUTED "$mp" 0 "$mp:$name" \
        "entry '$name' points at '$source', which does not exist"
      continue
    fi

    plugin_json="$src_dir/$CATALOG_DIR/plugin.json"
    if [ ! -f "$plugin_json" ]; then
      add_finding MARKETPLACE_SOURCE DISTRIBUTED "$mp" 0 "$mp:$name" \
        "entry '$name': manca $CATALOG_DIR/plugin.json in '$source'"
      continue
    fi

    plugin_version="$(jq -r '.version // empty' "$plugin_json")"
    if [ -n "$version" ] && [ -n "$plugin_version" ] && [ "$version" != "$plugin_version" ]; then
      add_finding MARKETPLACE_SOURCE DISTRIBUTED "$mp" 0 "$mp:$name" \
        "entry '$name' dichiara v$version, plugin.json dice v$plugin_version"
    fi
  done < <(jq -r '.plugins[]? | [.name, .source // "", .version // ""] | @tsv' "$catalog")
}

# ── Check 12: residue of the runtimes no longer supported ────────────────────
# Cursor, Codex and Gemini were removed by DE-16489: builders, dist/ artefacts and
# the dedicated catalogue. This check is the acceptance criterion's grep, made
# permanent so the support cannot creep back in through a PR.
# Excluded: the CHANGELOGs (release history, not plugin surface) and this check's
# own two files, which hold the patterns by definition.
LEGACY_RUNTIME_PATTERN='cursor|codex|gemini'

check_legacy_runtime_residue() {
  step "Check 12 — Cursor/Codex/Gemini residue in the artefacts"
  local f line no text
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      */CHANGELOG.md) continue ;;
      "$SCRIPT_DIR"/validate-plugin.sh|"$BASELINE_FILE") continue ;;
    esac
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      no="${line%%:*}"
      text="$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//')"
      add_finding LEGACY_RUNTIME_RESIDUE DISTRIBUTED "$(rel "$f")" "$no" "$(rel "$f"):$no" \
        "reference to a removed runtime (DE-16489): $text"
    done < <(grep -n -i -E "$LEGACY_RUNTIME_PATTERN" "$f" 2>/dev/null || true)
  done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$REPO_ROOT/dist" \
             "$REPO_ROOT/.claude-plugin" -type f 2>/dev/null | sort)
}

# ── Check 13: the workflow scripts contract ──────────────────────────────────
# The autonomous orchestration is code (DE-16479), so its defects are code
# defects: the harness loads `<plugin>/workflows/*.js`, parses the `meta` literal
# and registers the script as `<plugin>:<meta.name>` — the exact string the
# launcher skill calls. Everything this check looks at is invisible until a run
# starts, and by then the failure is a workflow that does not exist.
# `process` is matched only on its real API surfaces: a bare `process\.` would
# also flag a prompt line that happens to end with the word "process".
WORKFLOW_FORBIDDEN_PATTERN='Date\.now\(|Math\.random\(|new Date\(|require\(|process\.(env|exit|argv|cwd|platform)\b'

check_workflows() {
  step "Check 13 — the workflow scripts contract"
  local manifest tdir decl abs key meta_block name titles used missing_title stray_title line no text
  for manifest in "$REPO_ROOT"/templates/*/manifest.json; do
    [ -f "$manifest" ] || continue
    tdir="$(dirname "$manifest")"

    while IFS= read -r decl; do
      [ -n "$decl" ] || continue
      abs="$tdir/.claude/workflows/$decl"
      key="$(rel "$abs")"

      # The loader reads *.js and nothing else: a .mjs/.cjs/.ts file is counted
      # as a near miss and skipped, which looks exactly like a workflow that was
      # never declared.
      case "$decl" in
        *.js) ;;
        *)
          add_finding WORKFLOW_CONTRACT DISTRIBUTED "$(rel "$manifest")" 0 "$key" \
            "'$decl' is not a .js file: the plugin loader skips every other extension"
          continue ;;
      esac

      if [ ! -f "$abs" ]; then
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$(rel "$manifest")" 0 "$key" \
          "declares the workflow '$decl', which does not exist"
        continue
      fi

      # The meta literal: from line 1 to the line that closes it. The harness
      # refuses the file when it does not open with this exact declaration.
      if ! head -1 "$abs" | grep -q '^export const meta = {'; then
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$key" 1 "$key:meta" \
          "does not start with 'export const meta = {': the loader rejects it"
        continue
      fi
      meta_block="$(awk '/^\}/ { print; exit } { print }' "$abs")"

      name="$(printf '%s\n' "$meta_block" \
        | sed -n "s/^[[:space:]]*name:[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" | head -1)"
      if [ "$name" != "$(basename "$decl" .js)" ]; then
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$key" 1 "$key:name" \
          "meta.name is '${name:-(missing)}' but the file is '$decl': the launcher calls <plugin>:$(basename "$decl" .js)"
      fi

      if ! printf '%s\n' "$meta_block" | grep -q "^[[:space:]]*description:"; then
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$key" 1 "$key:description" \
          "meta has no description: the loader rejects a workflow without one"
      fi

      # Every phase the body opens has to be declared, and every declared phase
      # has to be used: an undeclared title grows a stray group in the progress
      # tree, a declared-and-unused one promises a step that never runs.
      titles="$(printf '%s\n' "$meta_block" \
        | sed -n "s/.*title:[[:space:]]*['\"]\([^'\"]*\)['\"].*/\1/p" | LC_ALL=C sort -u)"
      used="$( { grep -o "phase('[^']*')" "$abs" | sed "s/phase('\(.*\)')/\1/"
                 grep -o "phase:[[:space:]]*'[^']*'" "$abs" | sed "s/.*'\(.*\)'/\1/"
               } 2>/dev/null | LC_ALL=C sort -u)"

      missing_title="$(comm -13 <(printf '%s\n' "$titles") <(printf '%s\n' "$used") | tr '\n' ' ')"
      stray_title="$(comm -23 <(printf '%s\n' "$titles") <(printf '%s\n' "$used") | tr '\n' ' ')"
      if [ -n "${missing_title// /}" ]; then
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$key" 1 "$key:phases-undeclared" \
          "uses the phase(s) ${missing_title% } with no entry in meta.phases"
      fi
      if [ -n "${stray_title// /}" ]; then
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$key" 1 "$key:phases-unused" \
          "declares the phase(s) ${stray_title% } that the script never opens"
      fi

      # The globals that throw inside the workflow VM.
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        no="${line%%:*}"
        text="$(printf '%s' "${line#*:}" | sed 's/^[[:space:]]*//')"
        add_finding WORKFLOW_CONTRACT DISTRIBUTED "$key" "$no" "$key:$no" \
          "forbidden in a workflow script (it throws in the VM): $text"
      done < <(grep -n -E "$WORKFLOW_FORBIDDEN_PATTERN" "$abs" 2>/dev/null || true)
    done < <(jq -r '.workflows[]? // empty' "$manifest")
  done
}

# ── Checks 14-15: the documentation's references ─────────────────────────────
# The documentation is the one artefact nothing else validates. A renamed script,
# a retired command or a moved reference leaves the prose describing a plugin
# that no longer exists, and the failure mode is a developer following
# instructions that cannot work — which is how the pre-plugin `onboarding.md`
# survived three architectures (DE-16488).
#
# Check 14 resolves what the docs cite; check 15 is its mirror — a command the
# plugin exposes and the user guide never mentions.
DOC_DRIFT_EXCLUDE="docs/migration-v2-to-v3.md"
DOC_USER_GUIDE="docs/developer-guide.md"

# The files under review: the two root documents and the top level of docs/.
doc_files() {
  local f
  for f in "$REPO_ROOT/README.md" "$REPO_ROOT/AGENTS.md"; do
    [ -f "$f" ] && rel "$f"
  done
  find "$REPO_ROOT/docs" -maxdepth 1 -name '*.md' 2>/dev/null | LC_ALL=C sort \
    | while IFS= read -r f; do rel "$f"; done
}

# doc_tokens FILE ERE -> LINE \t TOKEN. grep -on prefixes the line number with the
# first colon, which is the only one sed touches: a token holding colons of its
# own (`/dev-setup:sdd`) comes through whole.
doc_tokens() {
  grep -on -E "$2" "$1" 2>/dev/null | sed 's/:/\t/' || true
}

# add_doc_finding FILE LINE TOKEN MESSAGE. The key is file+token rather than
# file+line: the same dangling reference repeated is one defect, and moving it
# down the page is not a new one.
add_doc_finding() {
  add_finding DOC_REFERENCE DOCS "$1" "$2" "$1:$3" "$4"
}

check_doc_references() {
  step "Check 14 — the commands, scripts and paths the documentation cites"

  # Docs name a hook or a plugin script by its basename far more often than by a
  # full path, and the same script legitimately exists under templates/ and
  # dist/. So .sh tokens resolve against an index of basenames.
  local sh_index="$TMP_DIR/sh-basenames.txt"
  : > "$sh_index"
  find "$REPO_ROOT/scripts" "$REPO_ROOT/templates" "$REPO_ROOT/dist" \
       -type f -name '*.sh' 2>/dev/null \
    | while IFS= read -r f; do basename "$f"; done | LC_ALL=C sort -u > "$sh_index"

  local doc abs line token plugin name target dir
  while IFS= read -r doc; do
    [ -n "$doc" ] || continue
    [ "$doc" = "$DOC_DRIFT_EXCLUDE" ] && continue
    abs="$REPO_ROOT/$doc"
    dir="$(dirname "$abs")"

    # ── Slash commands ────────────────────────────────────────────────────────
    # `/project:x` is the meta-repo's own namespace; `/<plugin>:x` is a built
    # plugin's. A `<name>` placeholder never matches: the class holds no `<`.
    while IFS=$'\t' read -r line token; do
      [ -n "${token:-}" ] || continue
      plugin="${token%%:*}"; plugin="${plugin#/}"
      name="${token#*:}"
      if [ "$plugin" = "project" ]; then
        if [ ! -f "$REPO_ROOT/.claude/skills/$name/SKILL.md" ] \
           && [ ! -f "$REPO_ROOT/.claude/commands/$name.md" ]; then
          add_doc_finding "$doc" "$line" "$token" \
            "cites '$token', which is neither a meta-repo skill nor a command"
        fi
        continue
      fi
      target="$REPO_ROOT/dist/$plugin/skills/$name/SKILL.md"
      if [ ! -f "$target" ]; then
        add_doc_finding "$doc" "$line" "$token" \
          "cites '$token', which the built plugin does not ship"
      elif [ "$(fm_value "$target" 'user-invocable')" != "true" ]; then
        add_doc_finding "$doc" "$line" "$token" \
          "cites '$token' as a command, but the skill is not user-invocable"
      fi
    done < <(doc_tokens "$abs" '/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*')

    # ── ${CLAUDE_PLUGIN_ROOT}/… and ${CLAUDE_SKILL_DIR}/templates/… ───────────
    # The two roots the skills address at run time. A trailing sentence period
    # is trimmed; `.md` and `.sh` end in a letter, so nothing real is lost.
    while IFS=$'\t' read -r line token; do
      [ -n "${token:-}" ] || continue
      target="${token#*\}/}"
      target="${target%%[.,;:)]}"
      case "$token" in
        *CLAUDE_PLUGIN_ROOT*) target="$REPO_ROOT/dist/dev-setup/$target" ;;
        *) target="$REPO_ROOT/dist/dev-setup/skills/setup/$target" ;;
      esac
      [ -e "$target" ] || add_doc_finding "$doc" "$line" "$token" \
        "cites '$token', which the built plugin does not hold"
    done < <(doc_tokens "$abs" '\$\{CLAUDE_(PLUGIN_ROOT|SKILL_DIR)\}/[A-Za-z0-9._/-]+')

    # ── Shell scripts, by basename ───────────────────────────────────────────
    while IFS=$'\t' read -r line token; do
      [ -n "${token:-}" ] || continue
      name="$(basename "$(printf '%s' "$token" | tr -d '`')")"
      grep -qxF "$name" "$sh_index" || add_doc_finding "$doc" "$line" "$name" \
        "cites the script '$name', which no longer exists in the repo"
    done < <(doc_tokens "$abs" '`[A-Za-z0-9._/-]+\.sh`')

    # ── Repo-relative paths ──────────────────────────────────────────────────
    # Only fully backticked ones, so the closing backtick — not a guess — is
    # where the path ends. A token holding a glob or a placeholder is skipped:
    # `templates/<domain>/rules/` is a shape, not a path.
    while IFS=$'\t' read -r line token; do
      [ -n "${token:-}" ] || continue
      target="$(printf '%s' "$token" | tr -d '`')"
      [ -e "$REPO_ROOT/$target" ] || add_doc_finding "$doc" "$line" "$target" \
        "cites the path '$target', which does not exist"
    done < <(doc_tokens "$abs" '`(scripts|templates|shared|dist|docs)/[A-Za-z0-9._/-]+`')

    # ── Generated rule files ─────────────────────────────────────────────────
    # `dev-setup-react.md` in a project is `rules/react.md` in the template: the
    # prefix is the contract that makes UPDATE safe, and a doc naming a rule
    # nothing generates describes governance the project will never receive.
    while IFS=$'\t' read -r line token; do
      [ -n "${token:-}" ] || continue
      name="${token#dev-setup-}"
      [ -f "$REPO_ROOT/templates/dev-setup/rules/$name" ] \
        || add_doc_finding "$doc" "$line" "$token" \
             "cites the rule '$token', which no template generates"
    done < <(doc_tokens "$abs" 'dev-setup-[a-z][a-z-]*\.md')

    # ── Relative markdown links ──────────────────────────────────────────────
    while IFS=$'\t' read -r line token; do
      [ -n "${token:-}" ] || continue
      target="${token#](}"; target="${target%)}"
      case "$target" in
        http*|mailto:*|\#*|"") continue ;;
      esac
      target="${target%%\#*}"
      [ -n "$target" ] || continue
      [ -e "$dir/$target" ] || add_doc_finding "$doc" "$line" "$target" \
        "links to '$target', which does not exist"
    done < <(doc_tokens "$abs" '\]\([^)]+\)')
  done < <(doc_files)
}

# ── Check 15: every public command is documented ─────────────────────────────
check_doc_command_coverage() {
  step "Check 15 — the user guide covers every public command"
  local guide plugin_dir plugin skill_md name
  guide="$REPO_ROOT/$DOC_USER_GUIDE"
  [ -f "$guide" ] || {
    add_finding DOC_COMMAND_COVERAGE DOCS "$DOC_USER_GUIDE" 0 "$DOC_USER_GUIDE" \
      "the user guide the commands are documented in does not exist"
    return 0
  }

  for plugin_dir in "$REPO_ROOT"/dist/*/; do
    [ -d "${plugin_dir}skills" ] || continue
    plugin="$(basename "$plugin_dir")"
    for skill_md in "${plugin_dir}skills"/*/SKILL.md; do
      [ -f "$skill_md" ] || continue
      [ "$(fm_value "$skill_md" 'user-invocable')" = "true" ] || continue
      name="$(basename "$(dirname "$skill_md")")"
      grep -qF "/$plugin:$name" "$guide" || add_finding DOC_COMMAND_COVERAGE DOCS \
        "$DOC_USER_GUIDE" 0 "$DOC_USER_GUIDE:$plugin:$name" \
        "'/$plugin:$name' is user-invocable and the user guide never mentions it"
    done
  done
}

# ── Run ──────────────────────────────────────────────────────────────────────
collect_skills
[ -s "$SKILLS" ] || die "no skill found: run this from the repo root"

check_skill_budget_and_frontmatter
check_references
check_force_load
check_command_duplicates
check_rule_templates
check_manifest_orphans
check_marketplace
check_legacy_runtime_residue
check_workflows
check_doc_references
check_doc_command_coverage

sort -o "$FINDINGS" "$FINDINGS"

# ── Baseline ─────────────────────────────────────────────────────────────────
BASELINE_KEYS="$TMP_DIR/baseline-keys.txt"
CURRENT_KEYS="$TMP_DIR/current-keys.txt"
: > "$BASELINE_KEYS"
if [ "$OPT_STRICT" = false ] && [ -f "$BASELINE_FILE" ]; then
  grep -v -E '^[[:space:]]*(#|$)' "$BASELINE_FILE" | sort -u > "$BASELINE_KEYS" || true
fi
awk -F'\t' '{ printf "%s\t%s\n", $1, $5 }' "$FINDINGS" | sort -u > "$CURRENT_KEYS"

STALE_KEYS="$TMP_DIR/stale-keys.txt"
comm -23 "$BASELINE_KEYS" "$CURRENT_KEYS" > "$STALE_KEYS"

if [ "$OPT_UPDATE_BASELINE" = true ]; then
  {
    echo "# validate-baseline.txt — known failures of scripts/validate-plugin.sh."
    echo "#"
    echo "# One line per finding: CHECK_ID <TAB> KEY. The entries listed here are"
    echo "# reported but do not fail CI. Every PR that fixes a defect removes the"
    echo "# matching line: the baseline shrinks, it does not grow."
    echo "# Regenerate with: bash scripts/validate-plugin.sh --update-baseline"
    echo "#"
    echo "# The repo's real state: bash scripts/validate-plugin.sh --strict"
    echo ""
    cat "$CURRENT_KEYS"
  } > "$BASELINE_FILE"
  ok "Baseline rewritten: $(rel "$BASELINE_FILE") ($(wc -l < "$CURRENT_KEYS" | tr -d ' ') entries)"
  exit 0
fi

TOTAL=$(wc -l < "$FINDINGS" | tr -d ' ')
NEW=0
BASELINED=0
NEW_FINDINGS="$TMP_DIR/new.tsv"
: > "$NEW_FINDINGS"
while IFS=$'\t' read -r cid scope file line key msg; do
  [ -n "${cid:-}" ] || continue
  if grep -q -F -x "$(printf '%s\t%s' "$cid" "$key")" "$BASELINE_KEYS" 2>/dev/null; then
    BASELINED=$((BASELINED + 1))
  else
    NEW=$((NEW + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$cid" "$scope" "$file" "$line" "$key" "$msg" >> "$NEW_FINDINGS"
  fi
done < "$FINDINGS"

STALE=$(wc -l < "$STALE_KEYS" | tr -d ' ')

EXIT_CODE=0
[ "$NEW" -gt 0 ] && EXIT_CODE=1
if [ "$OPT_FAIL_ON_STALE" = true ] && [ "$STALE" -gt 0 ]; then EXIT_CODE=1; fi

# ── Report ───────────────────────────────────────────────────────────────────
if [ "$OPT_JSON" = true ]; then
  jq -n \
    --arg status "$([ "$EXIT_CODE" -eq 0 ] && echo PASS || echo FAIL)" \
    --argjson total "$TOTAL" \
    --argjson new_failures "$NEW" \
    --argjson baselined "$BASELINED" \
    --argjson stale_baseline "$STALE" \
    --rawfile findings "$FINDINGS" \
    --rawfile stale "$STALE_KEYS" \
    '{
      STATUS: $status,
      TOTAL_FINDINGS: $total,
      NEW_FAILURES: $new_failures,
      BASELINED: $baselined,
      STALE_BASELINE: $stale_baseline,
      FINDINGS: ($findings | split("\n") | map(select(length > 0)) | map(split("\t")) | map({
        CHECK_ID: .[0], SCOPE: .[1], FILE: .[2], LINE: (.[3] | tonumber), KEY: .[4], MESSAGE: .[5]
      })),
      STALE_BASELINE_KEYS: ($stale | split("\n") | map(select(length > 0)) | map(split("\t")) | map({
        CHECK_ID: .[0], KEY: .[1]
      }))
    }'
  exit "$EXIT_CODE"
fi

echo ""
if [ "$NEW" -gt 0 ]; then
  step "New findings ($NEW) — not in the baseline"
  while IFS=$'\t' read -r cid scope file line key msg; do
    [ -n "${cid:-}" ] || continue
    if [ "$line" != "0" ]; then
      echo -e "${RED}✗${NC} [$cid] $file:$line — $msg"
    else
      echo -e "${RED}✗${NC} [$cid] $file — $msg"
    fi
  done < "$NEW_FINDINGS"
fi

if [ "$STALE" -gt 0 ]; then
  step "Stale baseline ($STALE) — defects fixed, remove the lines from $(rel "$BASELINE_FILE")"
  while IFS=$'\t' read -r cid key; do
    [ -n "${cid:-}" ] || continue
    echo -e "${YELLOW}⚠${NC}  $cid\t$key"
  done < "$STALE_KEYS"
fi

echo ""
echo "Findings: $TOTAL total · $BASELINED baselined · $NEW new · $STALE stale baseline"
if [ "$EXIT_CODE" -eq 0 ]; then
  ok "No new finding. Validation passed."
else
  echo -e "${RED}✗${NC} Validation failed. Fix the new findings (or update the baseline if they are accepted debt)."
fi
exit "$EXIT_CODE"
