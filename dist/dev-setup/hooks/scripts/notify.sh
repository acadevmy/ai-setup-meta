#!/usr/bin/env bash
# notify.sh — Notification hook on `permission_prompt` (DE-17077).
#
# A flow of this plugin that needs the developer reaches them through an `ask`
# rule: `gh pr create` / `glab mr create` when an autonomous run is
# ready-for-mr, the BLOCKED move when it failed. Claude Code's own notification
# says "Claude needs your permission" and not for which task — with five runs
# in flight, that tells the developer nothing. This hook sends one desktop
# notification titled `dev-setup · <TASK_IDS>`, with the prompt's message as
# the body.
#
# The clocks are the noise filter, the branch only narrows. A candidate is a
# task whose work clock is open in this repository, or was stopped less than
# five minutes ago (a failed run stops its clock, then asks for the BLOCKED
# move): `task-clock.sh --status`, the reader that consumes nothing, reports
# both. No candidate, nothing to say — whatever the branch is called, since
# every tracked branch carries an id and a branch alone is not a task in play.
# The built-in notification stays the only one there. When the branch of the
# payload's cwd names one of the candidates, the title carries that one;
# otherwise it carries them all — the payload does not say which run is asking,
# and guessing would be worse than naming the set.
#
# Only `permission_prompt`. `agent_needs_input` and `agent_completed` come from
# the agent view, already named after the session (session-title.sh sets that
# name), and run in the agent view's cwd, where a branch or a clock could only
# name the wrong task. `idle_prompt` and the rest carry no decision.
#
# Delivery is the OS notifier, chosen by `uname -s`. On Darwin, `terminal-notifier`
# when installed and allowed: it plays `$DEV_SETUP_NOTIFY_SOUND` (Submarine when
# unset) and a click activates the app
# that launched Claude Code (`$__CFBundleIdentifier`). Otherwise `osascript`,
# with the same sound — its notifications belong to Script Editor, so a click opens
# that — with the title and the body passed as argv, never interpolated into
# the script, so a message with quotes cannot break or inject into the
# AppleScript. `notify-send` on Linux. No terminal bell: a hook's stdio is piped
# to the harness, and ringing the terminal is what
# `preferredNotifChannel: "terminal_bell"` does.
#
# It fails open and prints nothing on stdout: a Notification hook has no
# decision control, so its whole effect is the side effect. No `jq`, no plugin
# scripts, a cwd outside a repository, an unsupported OS, a notifier missing or
# failing — exit 0, at most one diagnostic line on stderr.

set -uo pipefail

# ── Locate the plugin scripts ─────────────────────────────────────────────────
#
# Same three candidates as the other hooks: the plugin root when the harness
# exports it, then the source template layout, then the built one.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR=""

for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-/nonexistent}/scripts" \
  "$HOOK_DIR/../../scripts" \
  "$HOOK_DIR/../scripts"; do
  if [ -f "$CANDIDATE/task-clock.sh" ] && [ -f "$CANDIDATE/common.sh" ]; then
    SCRIPTS_DIR="$(cd "$CANDIDATE" && pwd)"
    break
  fi
done

# ── Read the hook payload ─────────────────────────────────────────────────────

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "notify: jq not found, notification skipped" >&2
  exit 0
fi

NOTIFICATION_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty' 2>/dev/null)
[ "$NOTIFICATION_TYPE" = "permission_prompt" ] || exit 0

MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null)
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# ── Is a task of this plugin in play here? ────────────────────────────────────

[ -n "$SCRIPTS_DIR" ] || exit 0
# shellcheck source=../scripts/common.sh
source "$SCRIPTS_DIR/common.sh"

if [ -n "$HOOK_CWD" ]; then
  cd "$HOOK_CWD" 2>/dev/null || exit 0
fi

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

STATUS=$(bash "$SCRIPTS_DIR/task-clock.sh" --status --json 2>/dev/null || true)
[ -n "$STATUS" ] || exit 0

CANDIDATES=$(printf '%s' "$STATUS" \
  | jq -r '[(.OPEN_TASKS // ""), (.RECENT_TASKS // "")] | map(select(. != "")) | join(" ")' \
  2>/dev/null || true)
[ -n "$CANDIDATES" ] || exit 0

# ── Which task is asking? ─────────────────────────────────────────────────────
#
# The id the branch carries, compared whole with each candidate: with DE-81 and
# DE-811 both in play, a branch named after the second never names the first.

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
BRANCH_TASK=$(branch_task_id "$BRANCH")

TASK_IDS="$CANDIDATES"
if [ -n "$BRANCH_TASK" ]; then
  for CANDIDATE in $CANDIDATES; do
    if [ "$CANDIDATE" = "$BRANCH_TASK" ]; then
      TASK_IDS="$CANDIDATE"
      break
    fi
  done
fi

TITLE="dev-setup · $TASK_IDS"

# ── Which session is asking? ──────────────────────────────────────────────────
#
# Il nome della scheda: quello nel payload se c'è, altrimenti l'ultimo titolo
# scritto nel transcript — scelto da chi sviluppa prima di quello generato.
# Con più sessioni sullo stesso task, è lui a dire quale scheda aprire.

session_name() {
  local name
  name=$(printf '%s' "$INPUT" | jq -r '.session_title // empty' 2>/dev/null)
  if [ -z "$name" ] && [ -f "$TRANSCRIPT" ]; then
    name=$(grep -h '"type":"custom-title"' "$TRANSCRIPT" 2>/dev/null | tail -1 \
      | jq -r '.customTitle // empty' 2>/dev/null)
  fi
  if [ -z "$name" ] && [ -f "$TRANSCRIPT" ]; then
    name=$(grep -h '"type":"ai-title"' "$TRANSCRIPT" 2>/dev/null | tail -1 \
      | jq -r '.aiTitle // empty' 2>/dev/null)
  fi
  printf '%s' "$name"
}
SESSION_NAME=$(session_name)

# ── What is it asking for? ────────────────────────────────────────────────────
#
# Il payload dice solo "permission_prompt": il tool nel messaggio distingue una
# domanda, un piano da approvare e un permesso vero. Un messaggio che non ha la
# forma attesa passa così com'è.

describe_prompt() {
  local tool="${MESSAGE#Claude needs your permission to use }"
  if [ "$tool" = "$MESSAGE" ] || [ -z "$tool" ]; then
    printf '%s' "$MESSAGE"
    return
  fi
  case "$tool" in
    AskUserQuestion) printf '❓ Claude has a question for you' ;;
    ExitPlanMode) printf '📋 Claude has a plan for you to approve' ;;
    *) printf '🔐 Claude wants to use %s' "$tool" ;;
  esac
}
MESSAGE=$(describe_prompt)

# ── Deliver it ────────────────────────────────────────────────────────────────

# L'icona dell'app che ha avviato Claude Code, come miniatura della notifica:
# PNG convertito una volta sola dal suo .icns e tenuto in $TMPDIR. Un'app senza
# .icns, o senza Spotlight, dà un percorso vuoto e la notifica parte senza.
app_icon() {
  local bundle_id="${__CFBundleIdentifier:-}" cache app icon
  [ -n "$bundle_id" ] || return 0
  cache="${TMPDIR:-/tmp}/dev-setup-icons/$bundle_id.png"
  if [ ! -s "$cache" ]; then
    app=$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null | head -1)
    [ -n "$app" ] || return 0
    icon=$(defaults read "$app/Contents/Info" CFBundleIconFile 2>/dev/null)
    [ -n "$icon" ] || return 0
    mkdir -p "$(dirname "$cache")" 2>/dev/null
    sips -s format png -Z 256 "$app/Contents/Resources/${icon%.icns}.icns" \
      --out "$cache" >/dev/null 2>&1 || return 0
  fi
  [ -s "$cache" ] && printf '%s' "$cache"
}

case "$(uname -s 2>/dev/null)" in
  Darwin)
    # Il clic riporta all'app che ha avviato Claude Code (VS Code, WebStorm,
    # Terminal…): il bundle id lo eredita il processo del hook. Il suono è un
    # nome di /System/Library/Sounds o ~/Library/Sounds, scelto da chi sviluppa.
    SOUND="${DEV_SETUP_NOTIFY_SOUND:-Submarine}"
    ICON=$(app_icon)
    if command -v terminal-notifier >/dev/null 2>&1 \
      && terminal-notifier -title "$TITLE" -subtitle "$SESSION_NAME" -message "$MESSAGE" -sound "$SOUND" \
        ${ICON:+-contentImage "$ICON"} \
        -group "dev-setup-$TASK_IDS" \
        -activate "${__CFBundleIdentifier:-com.apple.Terminal}" >/dev/null 2>&1; then
      exit 0
    fi
    command -v osascript >/dev/null 2>&1 || exit 0
    osascript \
      -e 'on run argv' \
      -e 'display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 4 of argv) sound name (item 3 of argv)' \
      -e 'end run' \
      "$TITLE" "$MESSAGE" "$SOUND" "$SESSION_NAME" >/dev/null 2>&1 \
      || echo "notify: osascript failed, notification skipped" >&2
    ;;
  Linux)
    command -v notify-send >/dev/null 2>&1 || exit 0
    notify-send "$TITLE" "$MESSAGE" >/dev/null 2>&1 \
      || echo "notify: notify-send failed, notification skipped" >&2
    ;;
esac

exit 0
