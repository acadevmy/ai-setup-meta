#!/bin/bash
# scripts/auto-maintain-runner.sh — invocato da launchd alle 04:00
# Esegue auto-maintain in un sandbox git worktree separato per non
# interferire con il working tree principale durante il lavoro quotidiano.
set -u

PRIMARY_REPO=/Users/andreao/Works/ai-base-setup
SANDBOX=/Users/andreao/Works/.automaint/ai-base-setup

mkdir -p "$PRIMARY_REPO/logs"
LOG="$PRIMARY_REPO/logs/auto-maintain.log"

echo "================================================================" >> "$LOG"
echo "[$(date -Iseconds)] auto-maintain run start" >> "$LOG"

# Verifica sandbox
if [[ ! -d "$SANDBOX" ]] || ([[ ! -d "$SANDBOX/.git" ]] && [[ ! -f "$SANDBOX/.git" ]]); then
  echo "[$(date -Iseconds)] ERROR: sandbox worktree not found at $SANDBOX" >> "$LOG"
  echo "[$(date -Iseconds)] Setup: git -C $PRIMARY_REPO worktree add $SANDBOX main" >> "$LOG"
  exit 1
fi

cd "$SANDBOX"

# Verifica .env.local (può essere symlink al repo primario)
if [[ ! -f .env.local ]]; then
  echo "[$(date -Iseconds)] ERROR: .env.local not found in sandbox (symlink missing?)" >> "$LOG"
  echo "[$(date -Iseconds)] Setup: ln -s $PRIMARY_REPO/.env.local $SANDBOX/.env.local" >> "$LOG"
  exit 1
fi

set -a; source .env.local; set +a

export PATH="/Users/andreao/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
claude -p "/auto-maintain" --dangerously-skip-permissions >> "$LOG" 2>&1
RC=$?

echo "[$(date -Iseconds)] auto-maintain run end (exit=$RC)" >> "$LOG"
exit $RC
