#!/usr/bin/env bash
# render-template.sh — substitutes {{PLACEHOLDER}} variables in a template.
#
# Used by the setup skill to instantiate the AGENTS/governance templates, and by
# the path-scoped rules templates. Deterministic: the same input and the same
# variables always produce the same output, and an unresolved placeholder is an
# error rather than a `{{TODO}}` committed into the project (the defect the
# audit found in the generated AGENTS.md).
#
# Usage:
#   render-template.sh --in <file> [--out <file>] [--var KEY=VALUE ...]
#   render-template.sh --in <file> --vars-json <file|-> [--allow-missing]
#
#   --in <file>          the template to render (required)
#   --out <file>         write here instead of stdout
#   --var KEY=VALUE      one substitution; repeatable
#   --vars-json <file>   read the substitutions from a flat JSON object
#                        ("-" reads stdin) — this is detect-stack.sh's output
#   --allow-missing      leave unresolved placeholders in place instead of failing
#   --list               list the placeholders the template uses, then exit
#
# Placeholders are `{{UPPER_SNAKE}}`. Values are substituted literally: no shell
# expansion, no command substitution, and a value holding `&` or `\` is safe.
#
# Exits non-zero on a missing template, a malformed --var, or — unless
# --allow-missing — any placeholder left unresolved.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

IN_FILE=""
OUT_FILE=""
VARS_JSON=""
ALLOW_MISSING=false
LIST_ONLY=false
VAR_KEYS=()
VAR_VALUES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --in)
      [ $# -ge 2 ] || die "--in requires a path"
      IN_FILE="$2"; shift 2 ;;
    --out)
      [ $# -ge 2 ] || die "--out requires a path"
      OUT_FILE="$2"; shift 2 ;;
    --var)
      [ $# -ge 2 ] || die "--var requires KEY=VALUE"
      case "$2" in
        *=*) ;;
        *) die "malformed --var '$2': expected KEY=VALUE" ;;
      esac
      VAR_KEYS+=("${2%%=*}")
      VAR_VALUES+=("${2#*=}")
      shift 2 ;;
    --vars-json)
      [ $# -ge 2 ] || die "--vars-json requires a path or -"
      VARS_JSON="$2"; shift 2 ;;
    --allow-missing) ALLOW_MISSING=true; shift ;;
    --list) LIST_ONLY=true; shift ;;
    -h|--help)
      sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$IN_FILE" ] || die "--in is required"
[ -f "$IN_FILE" ] || die "template not found: $IN_FILE"

# ── Placeholder listing ───────────────────────────────────────────────────────

list_placeholders() {
  grep -o '{{[A-Z0-9_]\{1,\}}}' "$IN_FILE" 2>/dev/null \
    | sed -e 's/^{{//' -e 's/}}$//' | sort -u
}

if [ "$LIST_ONLY" = true ]; then
  list_placeholders
  exit 0
fi

# ── Variables from JSON ───────────────────────────────────────────────────────

if [ -n "$VARS_JSON" ]; then
  require_jq
  if [ "$VARS_JSON" = "-" ]; then
    JSON_BODY=$(cat)
  else
    [ -f "$VARS_JSON" ] || die "vars file not found: $VARS_JSON"
    JSON_BODY=$(cat "$VARS_JSON")
  fi
  printf '%s' "$JSON_BODY" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || die "--vars-json must hold a JSON object"

  # NUL-separated so a value containing a newline survives the round trip.
  while IFS= read -r -d '' key && IFS= read -r -d '' value; do
    VAR_KEYS+=("$key")
    VAR_VALUES+=("$value")
  done < <(printf '%s' "$JSON_BODY" | jq -j 'to_entries[] | (.key, "\u0000", (.value | tostring), "\u0000")')
fi

# ── Substitution ──────────────────────────────────────────────────────────────
#
# Bash parameter expansion with a quoted needle: the match is literal (no glob)
# and the replacement is literal too. sed would reinterpret `&`, `\\` and any
# slash inside a value; awk would need one -v pair per variable.

CONTENT=$(cat "$IN_FILE")

for i in "${!VAR_KEYS[@]}"; do
  NEEDLE="{{${VAR_KEYS[$i]}}}"
  CONTENT=${CONTENT//"$NEEDLE"/"${VAR_VALUES[$i]}"}
done

# ── Unresolved placeholders ───────────────────────────────────────────────────

MISSING=$(printf '%s' "$CONTENT" | grep -o '{{[A-Z0-9_]\{1,\}}}' 2>/dev/null \
  | sed -e 's/^{{//' -e 's/}}$//' | sort -u)

if [ -n "$MISSING" ] && [ "$ALLOW_MISSING" != true ]; then
  {
    printf 'error: unresolved placeholders in %s:\n' "$IN_FILE"
    printf '%s\n' "$MISSING" | sed 's/^/  /'
    printf 'pass them with --var KEY=VALUE, or accept them with --allow-missing.\n'
  } >&2
  exit 1
fi

[ -n "$MISSING" ] && warn "unresolved placeholders left in place: $(printf '%s' "$MISSING" | tr '\n' ' ')"

# ── Output ────────────────────────────────────────────────────────────────────

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")" || die "cannot create the directory for $OUT_FILE"
  printf '%s\n' "$CONTENT" > "$OUT_FILE" || die "cannot write $OUT_FILE"
else
  printf '%s\n' "$CONTENT"
fi
