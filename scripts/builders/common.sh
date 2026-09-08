#!/usr/bin/env bash
# common.sh — Funzioni condivise di output (ok, warn, fail, step)
#
# Importato (source) da build-claude.sh e dagli script di validazione.
# Non eseguire direttamente.

# ── Colori e output ──────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }
