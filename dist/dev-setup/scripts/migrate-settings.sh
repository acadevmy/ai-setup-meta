#!/usr/bin/env bash
# migrate-settings.sh — brings a pre-sandbox .claude/settings.json up to the
# current template without discarding what the project's team added.
#
# The setup used to write a settings.json holding nothing but `permissions`: a
# wide allowlist (`npx`, `node`, `claude`), a deny list missing the force-push
# and `.env` entries, no `ask` block and no `sandbox` block at all. Conflict
# detection then treated that file as the team's and left it alone on every
# UPDATE, so the sandbox never reached a project that had already been set up —
# while `core.md` went on telling every session that "the sandbox denies reading
# the .env family". This script closes that gap.
#
# Usage:
#   migrate-settings.sh --in <file> --template <file> [--out <file>] [--json]
#
#   --in <file>        the project's .claude/settings.json (required)
#   --template <file>  the plugin's settings.json (required)
#   --out <file>       write the merged settings here instead of stdout
#   --json             print the report instead of the merged settings
#
# What the merge does, per key:
#   sandbox            taken from the template wholesale — the project has none,
#                      and a half-configured sandbox is worse than none
#   permissions.ask    taken from the template wholesale, same reason
#   permissions.deny   union: every template entry, plus anything the project
#                      added. A deny is never dropped
#   permissions.allow  the template's list, plus the project's own additions,
#                      minus the entries the refactor deliberately removed
#                      (see RETIRED_ALLOW below)
#   anything else      the project's value wins — these are keys the template
#                      does not manage
#
# Report keys (--json):
#   MIGRATED        true | false
#   REASON          migrated | already-sandboxed | no-template-sandbox
#   ADDED_SANDBOX   true | false
#   ADDED_ASK       number of `ask` entries the project did not have
#   ADDED_DENY      number of `deny` entries the project did not have
#   RETIRED_ALLOW   comma-separated allow entries dropped, or ""
#   KEPT_ALLOW      comma-separated allow entries kept that the template lacks
#
# Exit code: 0 = merged · 3 = nothing to migrate · other = error.
# The merged output is written; it is never applied in place. The caller shows
# it to the developer and asks before replacing anything.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# Allow entries the refactor removed on purpose. Each of them executes code
# chosen at call time, so allowing it allows everything — including
# `claude --dangerously-skip-permissions`, which the deny list forbids by name.
# `mcp__context7__*` goes too: the setup no longer registers that server (the
# `ctx7` CLI replaced it), and the rule never matched the plugin's own prefix.
RETIRED_ALLOW=(
  'Bash(npx *)'
  'Bash(pnpx *)'
  'Bash(node *)'
  'Bash(claude *)'
  'mcp__context7__*'
)

# ── Arguments ─────────────────────────────────────────────────────────────────

IN_FILE=""
TEMPLATE_FILE=""
OUT_FILE=""
AS_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --in)
      [ $# -ge 2 ] || die "--in requires a path"
      IN_FILE="$2"; shift 2 ;;
    --template)
      [ $# -ge 2 ] || die "--template requires a path"
      TEMPLATE_FILE="$2"; shift 2 ;;
    --out)
      [ $# -ge 2 ] || die "--out requires a path"
      OUT_FILE="$2"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help)
      sed -n '2,45p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$IN_FILE" ] || die "--in is required (see --help)"
[ -n "$TEMPLATE_FILE" ] || die "--template is required (see --help)"
[ -f "$IN_FILE" ] || die "settings file not found: $IN_FILE"
[ -f "$TEMPLATE_FILE" ] || die "template not found: $TEMPLATE_FILE"
jq -e . "$IN_FILE" >/dev/null 2>&1 || die "not valid JSON: $IN_FILE"
jq -e . "$TEMPLATE_FILE" >/dev/null 2>&1 || die "not valid JSON: $TEMPLATE_FILE"

# ── Nothing to do? ────────────────────────────────────────────────────────────

report_and_exit() {
  local reason="$1" code="$2"
  if [ "$AS_JSON" = true ]; then
    json_set MIGRATED false
    json_set REASON "$reason"
    json_set ADDED_SANDBOX false
    json_set ADDED_ASK 0
    json_set ADDED_DENY 0
    json_set RETIRED_ALLOW ""
    json_set KEPT_ALLOW ""
    json_emit
  else
    warn "nothing to migrate: $reason"
  fi
  exit "$code"
}

if jq -e 'has("sandbox")' "$IN_FILE" >/dev/null 2>&1; then
  report_and_exit already-sandboxed 3
fi

if ! jq -e 'has("sandbox")' "$TEMPLATE_FILE" >/dev/null 2>&1; then
  # Refuse to "migrate" towards a template that carries no sandbox: that would
  # rewrite the project's file for nothing and report a protection it did not add.
  report_and_exit no-template-sandbox 3
fi

# ── The merge ─────────────────────────────────────────────────────────────────

RETIRED_JSON=$(printf '%s\n' "${RETIRED_ALLOW[@]}" | jq -R . | jq -s .)

MERGED=$(jq -n \
  --slurpfile proj "$IN_FILE" \
  --slurpfile tpl "$TEMPLATE_FILE" \
  --argjson retired "$RETIRED_JSON" '
  ($proj[0]) as $p | ($tpl[0]) as $t |
  ($p.permissions // {}) as $pp | ($t.permissions // {}) as $tp |
  # allow: the template first (it is the intended baseline and its order is
  # deliberate), then whatever the project added and the refactor did not retire.
  (($tp.allow // []) + (($pp.allow // []) | map(select(. as $e | ($tp.allow // []) | index($e) | not))
                                          | map(select(. as $e | $retired | index($e) | not)))) as $allow |
  (($tp.deny // []) + (($pp.deny // []) | map(select(. as $e | ($tp.deny // []) | index($e) | not)))) as $deny |
  $p
  + { sandbox: $t.sandbox }
  + { permissions: ($pp + {
        allow: $allow,
        deny: $deny,
        ask: ($tp.ask // $pp.ask // [])
      }) }
')

[ -n "$MERGED" ] || die "the merge produced nothing — is $TEMPLATE_FILE the plugin settings.json?"

# ── What changed ──────────────────────────────────────────────────────────────

count_added() {
  local key="$1"
  jq -n --slurpfile proj "$IN_FILE" --slurpfile tpl "$TEMPLATE_FILE" --arg k "$key" '
    (($tpl[0].permissions // {})[$k] // []) as $t |
    (($proj[0].permissions // {})[$k] // []) as $p |
    ($t | map(select(. as $e | $p | index($e) | not)) | length)'
}

csv_of() { jq -r 'if length == 0 then "" else join(",") end'; }

ADDED_ASK=$(count_added ask)
ADDED_DENY=$(count_added deny)

RETIRED_FOUND=$(jq -n --slurpfile proj "$IN_FILE" --argjson retired "$RETIRED_JSON" '
  (($proj[0].permissions // {}).allow // []) as $p |
  ($retired | map(select(. as $e | $p | index($e))))' | csv_of)

KEPT_ALLOW=$(jq -n --slurpfile proj "$IN_FILE" --slurpfile tpl "$TEMPLATE_FILE" --argjson retired "$RETIRED_JSON" '
  (($proj[0].permissions // {}).allow // []) as $p |
  (($tpl[0].permissions // {}).allow // []) as $t |
  ($p | map(select(. as $e | $t | index($e) | not))
     | map(select(. as $e | $retired | index($e) | not)))' | csv_of)

# ── Output ────────────────────────────────────────────────────────────────────

if [ -n "$OUT_FILE" ]; then
  mkdir -p "$(dirname "$OUT_FILE")" 2>/dev/null || true
  printf '%s\n' "$MERGED" > "$OUT_FILE" || die "cannot write: $OUT_FILE"
fi

if [ "$AS_JSON" = true ]; then
  json_set MIGRATED true
  json_set REASON migrated
  json_set ADDED_SANDBOX true
  json_set ADDED_ASK "$ADDED_ASK"
  json_set ADDED_DENY "$ADDED_DENY"
  json_set RETIRED_ALLOW "$RETIRED_FOUND"
  json_set KEPT_ALLOW "$KEPT_ALLOW"
  json_emit
elif [ -z "$OUT_FILE" ]; then
  printf '%s\n' "$MERGED"
fi

exit 0
