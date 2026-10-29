#!/usr/bin/env bash
# devcontainer-check.sh — can the job runner use this repository's
# devcontainer: does it build, does it keep the runner's contract, and does
# every declared quality command start inside it?
#
# The runner of the headless `auto-dev` runs clones the repository, runs
# `devcontainer up` at its root with no `--config`, and starts the run inside.
# A devcontainer that does not build, runs as root, or lacks the program a
# quality command starts is found out there, on every run, after the build was
# paid for. This script finds it out once, on the developer's machine: it
# builds the configuration fresh, as the runner does, probes the contract, and
# runs the preflight and the three commands with `devcontainer exec`, from the
# repository root.
#
# The contract it holds the configuration to:
#   - one configuration at the root (`.devcontainer/devcontainer.json` or
#     `.devcontainer.json`): the runner never passes `--config`;
#   - a remote user with UID 1000, the runner's (on a Linux host the CLI maps
#     it to the host's UID, so there the expected UID is the host's);
#   - bash, git and curl in the image (claude and jq come from the runner);
#   - the workspace folder is the repository root, where the commands run, at
#     the CLI's default: no workspaceMount, no workspaceFolder of its own
#     outside compose (the runner also mounts the repository at its host path);
#   - no mount of /var/autodev (the runner adds it, a second one fails `up`),
#     and no bind of any other host path (it does not exist on the VM);
#   - no Docker socket, privileged mode, host network or Docker Feature (the
#     runner blocks the metadata server, and each one is a way around it);
#   - no `${localEnv:…}` of a credential (the agent's environment has none).
#
# The check runs isolated from the developer's own devcontainer: an id label
# of its own and, for a compose configuration, a compose project of its own
# (COMPOSE_PROJECT_NAME), so `--remove-existing-container` and the clean-up
# only ever touch what the check built. The images stay, as build cache.
#
# A red command is the project's state, not the devcontainer's: it is reported,
# the verdict stays ready. A command that does not start (exit 126/127) or a
# red declared preflight is the devcontainer's.
#
# Needs the Docker socket and the registries: from Claude Code, run it outside
# the Bash sandbox, and in the background — a build plus a test suite outlasts
# a Bash call.
#
# Usage:
#   devcontainer-check.sh [--json] [--keep] [--ssh-agent]
#
#   --keep       leave the container running (CONTAINER), for a look inside
#   --ssh-agent  forward this machine's SSH agent into the container for the
#                check, as VS Code does: for a private dependency declared
#                with an SSH URL, which the runner fetches over HTTPS with its
#                own credentials during `up`. Nothing is copied — the agent's
#                socket is mounted while the check's container lives (Docker
#                Desktop's on macOS, $SSH_AUTH_SOCK on Linux)
#   --json   emit a flat JSON object
#
# Keys:
#   STATUS            ready | not-ready | unverified
#   REASON            why not ready, or why not verified
#   CONFIG            the configuration checked, from the root
#   COMPOSE           true when it is a compose configuration
#   ISSUES            one line per broken clause of the contract
#   DOCKER            running | not-running | missing
#   CLI               available | missing (the devcontainer CLI)
#   UP                passed | failed | "" (not reached)
#   UP_SECONDS        how long the build and start took
#   CONTAINER         the container id, when one was started
#   REMOTE_USER       the user the commands run as
#   REMOTE_UID        its UID inside the container
#   EXPECTED_UID      1000, or the host's UID on a Linux host
#   PREFLIGHT         passed | failed | not-found | "" (none declared)
#   LINT_STATUS       passed | failed | not-found | absent | "" (not run)
#   TYPECHECK_STATUS
#   TEST_STATUS
#   OUTPUT            the tail of what failed: `up`, a command, the preflight
#   LOG_DIR           the full logs, one file per step
#   KEPT              true when the container was left running
#   SSH_AGENT         forwarded | "" (not asked)
#
# Exit: 0 ready · 4 not ready · 3 unverified (no Docker, no CLI, or no
#       declared commands — the static clauses are still checked) · 1 usage
#       error or no jq
# ---8<--- end of the --help message

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

AS_JSON=false
KEEP=false
SSH_AGENT_ASKED=false

usage() {
  awk 'NR == 1 { next } /^# ---8<---/ { exit } /^#/ { sub(/^# ?/, ""); print }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --json) AS_JSON=true; shift ;;
    --keep) KEEP=true; shift ;;
    --ssh-agent) SSH_AGENT_ASKED=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq

ROOT="$(repo_root)"
cd "$ROOT" || die "cannot enter the repository root: $ROOT"

MAX_OUTPUT_LINES=40

STATUS=""
REASON=""
CONFIG=""
COMPOSE=false
ISSUES=""
DOCKER=""
CLI=""
UP=""
UP_SECONDS=""
CONTAINER=""
REMOTE_USER=""
REMOTE_UID=""
EXPECTED_UID=""
PREFLIGHT=""
LINT_STATUS=""
TYPECHECK_STATUS=""
TEST_STATUS=""
OUTPUT=""
LOG_DIR=""
KEPT=false
SSH_AGENT=""

finish() {
  if [ -z "$STATUS" ]; then
    if [ -n "$ISSUES" ]; then STATUS="not-ready"; else STATUS="ready"; fi
  fi
  if [ "$STATUS" = not-ready ] && [ -z "$REASON" ]; then
    REASON="the devcontainer breaks the runner's contract — see ISSUES"
  fi

  json_set STATUS "$STATUS"
  json_set REASON "$REASON"
  json_set CONFIG "$CONFIG"
  json_set COMPOSE "$COMPOSE"
  json_set ISSUES "$ISSUES"
  json_set DOCKER "$DOCKER"
  json_set CLI "$CLI"
  json_set UP "$UP"
  json_set UP_SECONDS "$UP_SECONDS"
  json_set CONTAINER "$CONTAINER"
  json_set REMOTE_USER "$REMOTE_USER"
  json_set REMOTE_UID "$REMOTE_UID"
  json_set EXPECTED_UID "$EXPECTED_UID"
  json_set PREFLIGHT "$PREFLIGHT"
  json_set LINT_STATUS "$LINT_STATUS"
  json_set TYPECHECK_STATUS "$TYPECHECK_STATUS"
  json_set TEST_STATUS "$TEST_STATUS"
  json_set OUTPUT "$OUTPUT"
  json_set LOG_DIR "$LOG_DIR"
  json_set KEPT "$KEPT"
  json_set SSH_AGENT "$SSH_AGENT"

  if [ "$AS_JSON" = true ]; then
    json_emit
  else
    json_emit_text
  fi
  case "$STATUS" in
    ready) exit 0 ;;
    unverified) exit 3 ;;
    *) exit 4 ;;
  esac
}

add_issue() { ISSUES="${ISSUES:+$ISSUES
}$1"; }

add_output() { OUTPUT="${OUTPUT:+$OUTPUT
}--- $1
$(tail -n "$MAX_OUTPUT_LINES" "$2" 2>/dev/null)"; }

# ── The configuration, read without Docker ────────────────────────────────────

if [ -f .devcontainer/devcontainer.json ]; then
  CONFIG=".devcontainer/devcontainer.json"
elif [ -f .devcontainer.json ]; then
  CONFIG=".devcontainer.json"
else
  STATUS="not-ready"
  if find .devcontainer -mindepth 2 -maxdepth 2 -name devcontainer.json 2>/dev/null | grep -q .; then
    REASON="only .devcontainer/<name>/devcontainer.json: the runner runs \`devcontainer up\` with no --config, which reads .devcontainer/devcontainer.json or .devcontainer.json"
  else
    REASON="no devcontainer configuration at the repository root"
  fi
  finish
fi
CONFIG_DIR="$(dirname "$CONFIG")"

# devcontainer.json is JSON with comments and trailing commas: both go, outside
# the strings, before jq reads it.
strip_jsonc() {
  awk '
    {
      out = ""; n = length($0); i = 1
      while (i <= n) {
        c = substr($0, i, 1)
        if (blk) { if (substr($0, i, 2) == "*/") { blk = 0; i += 2 } else i++; continue }
        if (str) {
          out = out c
          if (c == "\\") { out = out substr($0, i + 1, 1); i += 2; continue }
          if (c == "\"") str = 0
          i++; continue
        }
        if (substr($0, i, 2) == "//") break
        if (substr($0, i, 2) == "/*") { blk = 1; i += 2; continue }
        if (c == "\"") str = 1
        out = out c; i++
      }
      print out
    }
  ' "$1" | tr '\n' ' ' | sed -E 's/,[[:space:]]*([]}])/\1/g'
}

if ! PARSED=$(strip_jsonc "$CONFIG" | jq -c . 2>/dev/null) || [ -z "$PARSED" ]; then
  STATUS="not-ready"
  REASON="$CONFIG does not parse as JSON with comments"
  finish
fi

cfg() { printf '%s' "$PARSED" | jq -r "$1" 2>/dev/null; }

[ -n "$(cfg '.dockerComposeFile // empty')" ] && COMPOSE=true

case "$(cfg '.remoteUser // .containerUser // empty')" in
  root|0) add_issue "remoteUser is root: the runner runs as UID 1000 — use the image's non-root user (vscode, node)" ;;
esac

[ "$(cfg '.updateRemoteUserUID // empty')" = false ] && \
  add_issue "updateRemoteUserUID is false: on the runner's Linux host the remote user must be mapped to UID 1000"

if cfg '[(.mounts // [])[] | if type == "string" then . else (.target // .destination // "") end] + (.runArgs // []) | .[]' \
   | grep -q '/var/autodev'; then
  add_issue "a mount of /var/autodev is declared: the runner adds it, and a second one fails \`up\` — remove it"
fi

# What a bind mount or a -v reads from the host, one per line, as written.
MOUNT_SOURCES=$( {
  cfg '(.mounts // [])[]
       | if type == "string"
         then (split(",") | map(capture("^(?<k>[^=]+)=(?<v>.*)$")) | map({(.k): .v}) | add // {})
         else . end
       | select((.type // "bind") == "bind") | (.source // .src // empty)'
  cfg '(.runArgs // []) | join(" ")' \
    | grep -oE '(^| )(-v|--volume)[= ][^ ]+|(source|src)=[^, ]+' \
    | sed -E 's/^ ?(-v|--volume)[= ]//; s/^(source|src)=//'
} )
RUN_ARGS=$(cfg '(.runArgs // []) | join(" ")')

# The runner blocks the metadata server for UID 1000 and for its containers;
# the socket, privileged mode or the host network hand the agent a way around
# it, to the service-account token that reads the git secrets.
SOCKET_ISSUE="the runner refuses it: through it the agent could start a root container on the host network and read the runner's service-account token — services go in docker compose, on a bridge network"
if printf '%s\n%s\n' "$MOUNT_SOURCES" "$RUN_ARGS" | grep -q 'docker\.sock'; then
  add_issue "the Docker socket is mounted: $SOCKET_ISSUE"
fi
if [ "$(cfg '.privileged // empty')" = true ] || printf '%s' "$RUN_ARGS" | grep -qE '(^| )--privileged'; then
  add_issue "privileged mode: $SOCKET_ISSUE"
fi
if printf '%s' "$RUN_ARGS" | grep -qE '(^| )--(network|net)[= ]host'; then
  add_issue "the host network: $SOCKET_ISSUE"
fi
while IFS= read -r FEATURE; do
  [ -n "$FEATURE" ] && add_issue "the Feature $FEATURE gives the container Docker: $SOCKET_ISSUE"
done < <(cfg '(.features // {}) | keys[]' | grep -E 'docker-(in|outside-of|from)-docker')

while IFS= read -r SOURCE; do
  [ -n "$SOURCE" ] || continue
  case "$SOURCE" in *docker.sock*|*/var/autodev*) continue ;; esac
  # shellcheck disable=SC2016  # the literal text of a devcontainer variable
  case "$SOURCE" in
    /*|~*|'${localEnv:'*)
      add_issue "a bind mount of a host path ($SOURCE): it does not exist on the runner's VM, and \`up\` fails — no key or git config needs mounting, the runner rewrites SSH git URLs to HTTPS" ;;
  esac
done <<<"$MOUNT_SOURCES"

# The runner mounts the repository twice — /workspaces/<repo>, the CLI's
# default, and its host path under /var/autodev, where the agent works — so a
# path of the configuration's own choosing is one more place for a script to
# assume.
[ -z "$(cfg '.workspaceMount // empty')" ] || \
  add_issue "a custom workspaceMount: the runner mounts the repository itself (/workspaces/<repo>, and its host path under /var/autodev) — remove it"
WORKSPACE_FOLDER=$(cfg '.workspaceFolder // empty')
# shellcheck disable=SC2016  # the literal default, as a configuration writes it
if [ "$COMPOSE" != true ] && [ -n "$WORKSPACE_FOLDER" ] \
   && [ "$WORKSPACE_FOLDER" != '/workspaces/${localWorkspaceFolderBasename}' ]; then
  add_issue "a custom workspaceFolder ($WORKSPACE_FOLDER): keep the CLI's default, /workspaces/<repo>, where the runner expects the repository"
fi

# The compose files, relative to the configuration's directory.
COMPOSE_PATHS=""
if [ "$COMPOSE" = true ]; then
  while IFS= read -r F; do
    [ -n "$F" ] || continue
    COMPOSE_PATHS="${COMPOSE_PATHS}${CONFIG_DIR}/${F}
"
  done < <(cfg '.dockerComposeFile | if type == "array" then .[] else . end')
  while IFS= read -r F; do
    [ -n "$F" ] && [ -f "$F" ] || continue
    grep -q '/var/autodev' "$F" && \
      add_issue "$F mounts /var/autodev: the runner adds it, and a second one fails \`up\` — remove it"
    grep -q 'docker\.sock' "$F" && add_issue "$F mounts the Docker socket: $SOCKET_ISSUE"
    grep -qE '^[[:space:]]*privileged:[[:space:]]*true' "$F" && add_issue "$F runs a service privileged: $SOCKET_ISSUE"
    grep -qE '^[[:space:]]*network_mode:[[:space:]]*["'"'"']?host' "$F" && \
      add_issue "$F puts a service on the host network: $SOCKET_ISSUE"
    # A host path a volume binds: `- /src:/dst`, `- ~/src:/dst`, `source: /src`.
    while IFS= read -r SOURCE; do
      [ -n "$SOURCE" ] || continue
      case "$SOURCE" in *docker.sock*|*/var/autodev*) continue ;; esac
      add_issue "$F binds a host path ($SOURCE): it does not exist on the runner's VM, and \`up\` fails"
    done < <(sed -nE \
      -e 's/^[[:space:]]*-[[:space:]]*["'"'"']?((\/|~|\$\{?HOME)[^:"'"'"']*):.*/\1/p' \
      -e 's/^[[:space:]]*source:[[:space:]]*["'"'"']?((\/|~|\$\{?HOME)[^"'"'"' ]*).*/\1/p' "$F")
  done <<<"$COMPOSE_PATHS"
fi

# shellcheck disable=SC2016  # the literal text of a devcontainer variable
while IFS= read -r NAME; do
  [ -n "$NAME" ] || continue
  add_issue "\${localEnv:$NAME} reads a credential from the host: the runner's agent environment has none — install private dependencies in onCreateCommand/postCreateCommand, which run while the runner's git credentials exist"
done < <(cfg '[.. | strings] | .[]' | grep -oE '\$\{localEnv:[A-Za-z_][A-Za-z0-9_]*' \
           | sed 's/^\${localEnv://' | LC_ALL=C sort -u \
           | grep -iE 'TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH|API_?KEY|PRIVATE_KEY')

# ── The declared commands ─────────────────────────────────────────────────────

DECLARED=true
NOT_DECLARED=""
LINT_CMD=""
TYPECHECK_CMD=""
TEST_CMD=""
PREFLIGHT_CMD=""
if ! STACK=$(bash "$SCRIPT_DIR/detect-stack.sh" --json 2>/dev/null); then
  DECLARED=false
  NOT_DECLARED="the quality-commands declaration is rejected: fix .claude/quality-commands.json, or re-run /dev-setup:setup (step 3b)"
else
  stack_get() { printf '%s' "$STACK" | jq -r --arg k "$1" '.[$k] // empty'; }
  LINT_CMD=$(stack_get LINT_CMD)
  TYPECHECK_CMD=$(stack_get TYPECHECK_CMD)
  TEST_CMD=$(stack_get TEST_CMD)
  PREFLIGHT_CMD=$(stack_get PREFLIGHT_CMD)
  if [ "$(stack_get COMMANDS_SOURCE)" != declared ]; then
    DECLARED=false
    NOT_DECLARED="the project declares no quality commands (.claude/quality-commands.json): run /dev-setup:setup (step 3b) first — the check runs the declared ones"
  else
    [ -n "$LINT_CMD" ] || LINT_STATUS="absent"
    [ -n "$TYPECHECK_CMD" ] || TYPECHECK_STATUS="absent"
    [ -n "$TEST_CMD" ] || TEST_STATUS="absent"
  fi
fi

# ── Docker and the CLI ────────────────────────────────────────────────────────

if ! command -v docker >/dev/null 2>&1; then
  DOCKER="missing"
elif docker info >/dev/null 2>&1; then
  DOCKER="running"
else
  DOCKER="not-running"
fi
if command -v devcontainer >/dev/null 2>&1; then CLI="available"; else CLI="missing"; fi

# A configuration that already breaks the contract is not worth a build.
[ -z "$ISSUES" ] || finish

if [ "$DOCKER" != running ] || [ "$CLI" != available ] || [ "$DECLARED" != true ]; then
  STATUS="unverified"
  if [ "$DECLARED" != true ]; then
    REASON="$NOT_DECLARED"
  elif [ "$DOCKER" = missing ]; then
    REASON="Docker is not installed here: the configuration was not built"
  elif [ "$DOCKER" = not-running ]; then
    REASON="the Docker daemon is not reachable (not started, or the call ran inside a sandbox): the configuration was not built"
  else
    REASON="the devcontainer CLI is not installed (npm install -g @devcontainers/cli): the configuration was not built"
  fi
  finish
fi

# ── Build and start it, the way the runner does ───────────────────────────────

LOG_DIR="$(state_dir devcontainer-check 2>/dev/null)" && mkdir -p "$LOG_DIR" 2>/dev/null \
  || LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devcontainer-check.XXXXXX")"

TAG="$(slugify "$(basename "$ROOT")" 30)-$(printf '%s' "$ROOT" | cksum | cut -d' ' -f1)"
ID_LABEL="dev-setup.check=$TAG"
PROJECT="devsetup-check-$TAG"

if [ "$COMPOSE" = true ]; then
  # The CLI takes the compose project from this variable before anything else:
  # the check's services never share a name with the developer's.
  export COMPOSE_PROJECT_NAME="$PROJECT"
  docker compose -p "$PROJECT" down --volumes --remove-orphans >/dev/null 2>&1 || true
fi

UP_ARGS=(--workspace-folder "$ROOT" --id-label "$ID_LABEL" --remove-existing-container)
AGENT_ENV=()
OPEN_SOCKET=false

# The agent the developer's own devcontainer gets from VS Code: Docker Desktop
# forwards the macOS one at a fixed path inside its VM, Linux has the socket
# itself. The lifecycle commands see it through SSH_AUTH_SOCK; github.com's key
# is accepted on first use, as a fresh container has no known_hosts. Only the
# keys loaded in the agent travel: one ~/.ssh/config names with IdentityFile
# does not.
if [ "$SSH_AGENT_ASKED" = true ]; then
  AGENT_TARGET="/tmp/dev-setup-ssh-agent.sock"
  if [ "$(uname -s)" = Linux ]; then
    AGENT_SOURCE="${SSH_AUTH_SOCK:-}"
    if [ -z "$AGENT_SOURCE" ] || [ ! -e "$AGENT_SOURCE" ]; then
      STATUS="unverified"
      REASON="--ssh-agent: no SSH agent here (SSH_AUTH_SOCK is unset or gone) — start one and add the key, or check without it"
      finish
    fi
  else
    AGENT_SOURCE="/run/host-services/ssh-auth.sock"
    # Docker Desktop's socket is root's (0660): the remote user reaches it only
    # once it is opened, which needs the container — so the lifecycle commands
    # run after `up`, and the socket's mode is put back when they end.
    OPEN_SOCKET=true
    UP_ARGS+=(--skip-post-create)
  fi
  if command -v ssh-add >/dev/null 2>&1 && ! ssh-add -l >/dev/null 2>&1; then
    STATUS="unverified"
    REASON="--ssh-agent: the SSH agent holds no key — load the one the git host accepts (ssh-add <key>), or check without it"
    finish
  fi
  AGENT_ENV=(--remote-env "SSH_AUTH_SOCK=$AGENT_TARGET"
             --remote-env "GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=accept-new")
  UP_ARGS+=(--mount "type=bind,source=$AGENT_SOURCE,target=$AGENT_TARGET" "${AGENT_ENV[@]}")
  SSH_AGENT="forwarded"
fi

# The last JSON line a CLI call printed, and one key of it.
result_of() { grep '^{' "$1" 2>/dev/null | tail -n 1; }
result_get() { printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty' 2>/dev/null; }

UP_START=$(date +%s)
devcontainer up "${UP_ARGS[@]}" >"$LOG_DIR/up.json" 2>"$LOG_DIR/up.log"
UP_RC=$?

UP_RESULT=$(result_of "$LOG_DIR/up.json")
CONTAINER=$(result_get "$UP_RESULT" containerId)
REMOTE_USER=$(result_get "$UP_RESULT" remoteUser)
FAILED_STEP=""
if [ "$UP_RC" -ne 0 ] || [ "$(result_get "$UP_RESULT" outcome)" != success ]; then
  FAILED_STEP="up"
  FAILED_RC=$UP_RC
  FAILED_RESULT=$UP_RESULT
elif [ "$OPEN_SOCKET" = true ]; then
  SOCKET_MODE=$(docker exec -u 0 "$CONTAINER" stat -c %a "$AGENT_TARGET" 2>/dev/null)
  docker exec -u 0 "$CONTAINER" chmod 0666 "$AGENT_TARGET" >/dev/null 2>&1
  devcontainer run-user-commands --workspace-folder "$ROOT" --container-id "$CONTAINER" "${AGENT_ENV[@]}" \
    >"$LOG_DIR/lifecycle.json" 2>"$LOG_DIR/lifecycle.log"
  LIFECYCLE_RC=$?
  [ -z "$SOCKET_MODE" ] || docker exec -u 0 "$CONTAINER" chmod "$SOCKET_MODE" "$AGENT_TARGET" >/dev/null 2>&1
  LIFECYCLE_RESULT=$(result_of "$LOG_DIR/lifecycle.json")
  if [ "$LIFECYCLE_RC" -ne 0 ] || [ "$(result_get "$LIFECYCLE_RESULT" outcome)" != success ]; then
    FAILED_STEP="lifecycle"
    FAILED_RC=$LIFECYCLE_RC
    FAILED_RESULT=$LIFECYCLE_RESULT
  fi
fi
UP_SECONDS=$(( $(date +%s) - UP_START ))

# Removes what the check built. A compose project is the check's own whatever
# `up` answered — a failed build names no project, and its database would
# outlive it otherwise.
cleanup() {
  if [ "$KEEP" = true ]; then
    [ -z "$CONTAINER" ] || KEPT=true
  elif [ "$COMPOSE" = true ]; then
    docker compose -p "$PROJECT" down --volumes --remove-orphans >/dev/null 2>&1 || true
  elif [ -n "$CONTAINER" ]; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  fi
}

if [ -n "$FAILED_STEP" ]; then
  UP="failed"
  REASON="\`devcontainer up\` failed: $(result_get "$FAILED_RESULT" description) $(result_get "$FAILED_RESULT" message)"
  REASON="${REASON% }"
  add_issue "the configuration does not build or start — see OUTPUT and $LOG_DIR/$FAILED_STEP.log"
  add_output "devcontainer $FAILED_STEP (exit $FAILED_RC)" "$LOG_DIR/$FAILED_STEP.log"
  cleanup
  finish
fi
UP="passed"

dc_exec() { devcontainer exec --workspace-folder "$ROOT" --container-id "$CONTAINER" "$@"; }

# ── The contract, probed inside ───────────────────────────────────────────────

# shellcheck disable=SC2016  # expanded by the shell inside the container
PROBE='printf "uid=%s\n" "$(id -u)"; printf "pwd=%s\n" "$(pwd)"
for t in bash git curl; do command -v "$t" >/dev/null 2>&1 || printf "missing=%s\n" "$t"; done
command -v git >/dev/null 2>&1 && printf "top=%s\n" "$(git -c safe.directory="*" rev-parse --show-toplevel 2>/dev/null)"
exit 0'
PROBE_OUT=$(dc_exec sh -c "$PROBE" 2>"$LOG_DIR/probe.log")
probe_get() { printf '%s\n' "$PROBE_OUT" | sed -n "s/^$1=//p"; }

REMOTE_UID=$(probe_get uid | head -n 1)
if [ "$(uname -s)" = Linux ]; then EXPECTED_UID=$(id -u); else EXPECTED_UID=1000; fi
if [ -z "$REMOTE_UID" ]; then
  add_issue "the container answers no shell command: \`devcontainer exec\` could not run sh — see $LOG_DIR/probe.log"
elif [ "$REMOTE_UID" = 0 ]; then
  add_issue "the commands run as root (${REMOTE_USER:-root}): the runner runs as UID 1000 — set remoteUser to the image's non-root user"
elif [ "$REMOTE_UID" != "$EXPECTED_UID" ]; then
  add_issue "the remote user ${REMOTE_USER:-?} has UID $REMOTE_UID, the runner's is $EXPECTED_UID — use an image user with UID 1000 (vscode, node)"
fi

MISSING_TOOLS=$(probe_get missing | tr '\n' ' ' | sed 's/ $//')
[ -z "$MISSING_TOOLS" ] || \
  add_issue "not in the image: $MISSING_TOOLS — auto-dev needs bash, git and curl inside the container"

WORKDIR=$(probe_get pwd | head -n 1)
TOPLEVEL=$(probe_get top | head -n 1)
if [ -n "$TOPLEVEL" ] && [ -n "$WORKDIR" ] && [ "$TOPLEVEL" != "$WORKDIR" ]; then
  add_issue "the commands start in $WORKDIR, the repository root is $TOPLEVEL — workspaceFolder must be the root, where every quality command runs"
fi

# ── The preflight and the commands ────────────────────────────────────────────

# Runs one command in the container, from the workspace folder, and leaves
# passed | failed | not-found in RUN_STATUS: not printed, because a command
# substitution would run it in a subshell and lose what add_output appends.
run_kind() {
  local name="$1" cmd="$2" status rc
  dc_exec bash -c "$cmd" >"$LOG_DIR/$name.log" 2>&1
  rc=$?
  case "$rc" in
    0) status="passed" ;;
    126|127) status="not-found" ;;
    *) status="failed" ;;
  esac
  [ "$rc" -eq 0 ] || add_output "$name: $cmd (exit $rc)" "$LOG_DIR/$name.log"
  RUN_STATUS="$status"
}

if [ -n "$PREFLIGHT_CMD" ]; then
  run_kind preflight "$PREFLIGHT_CMD"
  PREFLIGHT="$RUN_STATUS"
  [ "$PREFLIGHT" = passed ] || \
    add_issue "the declared preflight is red inside the container ($PREFLIGHT_CMD): the toolchain it checks is not there"
fi

for KIND in lint typecheck test; do
  case "$KIND" in
    lint) CMD="$LINT_CMD" ;;
    typecheck) CMD="$TYPECHECK_CMD" ;;
    test) CMD="$TEST_CMD" ;;
  esac
  [ -n "$CMD" ] || continue
  run_kind "$KIND" "$CMD"
  case "$KIND" in
    lint) LINT_STATUS="$RUN_STATUS" ;;
    typecheck) TYPECHECK_STATUS="$RUN_STATUS" ;;
    test) TEST_STATUS="$RUN_STATUS" ;;
  esac
  [ "$RUN_STATUS" != not-found ] || \
    add_issue "$KIND did not start inside the container (exit 126/127): $CMD — the image lacks its program"
done

cleanup
finish
