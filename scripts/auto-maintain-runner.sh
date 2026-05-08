#!/bin/bash
# scripts/auto-maintain-runner.sh — invocato da launchd alle 04:00
# Esegue auto-maintain in un sandbox git worktree separato per non
# interferire con il working tree principale durante il lavoro quotidiano.
set -u

PRIMARY_REPO=/Users/andreao/Works/ai-base-setup
SANDBOX=/Users/andreao/Works/.automaint/ai-base-setup
STATE_FILE="$SANDBOX/.automaint-state.json"
MAX_RETRIES=3
RETRY_DELAY=60

mkdir -p "$PRIMARY_REPO/logs"
LOG="$PRIMARY_REPO/logs/auto-maintain.log"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

echo "================================================================" >> "$LOG"
log "auto-maintain run start"

# Verifica sandbox
if [[ ! -d "$SANDBOX" ]] || ([[ ! -d "$SANDBOX/.git" ]] && [[ ! -f "$SANDBOX/.git" ]]); then
  log "ERROR: sandbox worktree not found at $SANDBOX"
  log "Setup: git -C $PRIMARY_REPO worktree add $SANDBOX main"
  exit 1
fi

cd "$SANDBOX"

# Aggiorna il riferimento a main senza checkout forzato (safe anche su branch work)
log "git fetch origin main"
git fetch origin main >> "$LOG" 2>&1
if [[ $? -ne 0 ]]; then
  log "ERROR: git fetch failed (network issue?)"
  exit 1
fi

# Verifica .env.local (può essere symlink al repo primario)
if [[ ! -f .env.local ]]; then
  log "ERROR: .env.local not found in sandbox (symlink missing?)"
  log "Setup: ln -s $PRIMARY_REPO/.env.local $SANDBOX/.env.local"
  exit 1
fi

set -a; source .env.local; set +a

export PATH="/Users/andreao/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Retry loop: ritenta la pipeline in caso di timeout o errore transitorio.
# Si ferma senza retry se il task è stato marcato BLOCKED dalla pipeline stessa.
attempt=0
RC=1

while [[ $attempt -lt $MAX_RETRIES ]]; do
  attempt=$((attempt + 1))
  log "claude attempt $attempt/$MAX_RETRIES"

  claude -p "/auto-maintain" --dangerously-skip-permissions >> "$LOG" 2>&1
  RC=$?

  if [[ $RC -eq 0 ]]; then
    log "claude succeeded on attempt $attempt"
    break
  fi

  # Se la pipeline ha segnalato BLOCKED, non ritentare
  if [[ -f "$STATE_FILE" ]]; then
    STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null)
    if [[ "$STATUS" == "blocked" ]]; then
      log "task is BLOCKED, skip retry"
      break
    fi
    NEXT_STEP=$(jq -r '.next_step // "?"' "$STATE_FILE" 2>/dev/null)
    log "claude failed (exit=$RC) at step $NEXT_STEP"
  else
    log "claude failed (exit=$RC)"
  fi

  if [[ $attempt -lt $MAX_RETRIES ]]; then
    log "retry in ${RETRY_DELAY}s (attempt $attempt/$MAX_RETRIES)"
    sleep "$RETRY_DELAY"
  fi
done

log "auto-maintain run end (exit=$RC)"
exit $RC
