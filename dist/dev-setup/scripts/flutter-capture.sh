#!/usr/bin/env bash
# flutter-capture.sh — a Flutter screen rendered to a PNG, for the visual check.
#
# A Flutter UI is no web page: Playwright cannot capture it. A widget test can,
# headless, with no device and no emulator, so in CI and in auto-dev too: the
# test pumps the screen at the frame's size, device pixel ratio 1, and writes
# it with matchesGoldenFile. This script runs that one test with
# --update-goldens, so the golden is written instead of compared, and hands
# the PNG to visual-check.sh, which compares it with the frame. The capture
# test itself is written by whoever builds the screen, as
# reference/visual-check.md says: it reads the three values below, and it is
# skipped when they are not there, so the project's own `flutter test` never
# runs it.
#
#   --dart-define=VISUAL_CAPTURE_OUT=<absolute png path>
#   --dart-define=VISUAL_CAPTURE_WIDTH=<px>
#   --dart-define=VISUAL_CAPTURE_HEIGHT=<px>
#
# Usage:
#   flutter-capture.sh --target <test file> --test <name> --out <png>
#                      --width <px> --height <px> [--project-dir <dir>] [--json]
#
#   --target       the capture test, relative to --project-dir, ending _test.dart
#   --test         the test's name, run alone with --plain-name
#   --out          where the PNG goes
#   --width/--height  the frame's size, cropped: the test pumps the screen at it
#   --project-dir  default the repository root; the Flutter package is the
#                  nearest pubspec.yaml above the target
#
# Output (--json): ACTUAL, CAUSE, REASON, FLUTTER, PACKAGE_DIR.
#
# Exit code: 0 captured · 3 not captured: CAUSE=environment (no Flutter SDK,
# the sandbox refusing what the SDK writes) or CAUSE=page (no such test, the
# test failed, or it wrote no image) · other = error.
#
# It installs nothing and never edits the test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

TARGET=""
TEST_NAME=""
OUT=""
WIDTH=""
HEIGHT=""
PROJECT_DIR=""
AS_JSON=false

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2-}"; shift 2 ;;
    --test) TEST_NAME="${2-}"; shift 2 ;;
    --out) OUT="${2-}"; shift 2 ;;
    --width) WIDTH="${2-}"; shift 2 ;;
    --height) HEIGHT="${2-}"; shift 2 ;;
    --project-dir) PROJECT_DIR="${2-}"; shift 2 ;;
    --json) AS_JSON=true; shift ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

require_jq
[ -n "$TARGET" ] && [ -n "$TEST_NAME" ] && [ -n "$OUT" ] || die "--target, --test and --out are required (see --help)"
printf '%s' "$TARGET" | grep -qE '^[A-Za-z0-9_][A-Za-z0-9_./-]*_test\.dart$' \
  || die "--target is a relative path to a *_test.dart file: $TARGET"
case "/$TARGET/" in */../*) die "--target leaves the project: $TARGET" ;; esac
printf '%s' "$TEST_NAME" | grep -qE '^[^"`$\\]{1,200}$' || die "--test is a test name of at most 200 characters, with no quote, backtick, \$ or backslash"
for DIM in "$WIDTH" "$HEIGHT"; do
  printf '%s' "$DIM" | grep -qE '^[1-9][0-9]{0,4}$' || die "--width and --height are sizes in pixels: ${WIDTH}x${HEIGHT}"
done

[ -n "$PROJECT_DIR" ] || PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "no such directory: $PROJECT_DIR"
mkdir -p "$(dirname "$OUT")" || die "cannot create the folder of $OUT"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

json_set ACTUAL ""
json_set CAUSE ""
json_set REASON ""
json_set FLUTTER ""
json_set PACKAGE_DIR ""

finish() {
  if [ "$AS_JSON" = true ]; then json_emit; else json_emit_text; fi
  exit "$1"
}
unverified() {
  json_set CAUSE "$1"
  json_set REASON "$2"
  finish 3
}

[ -f "$PROJECT_DIR/$TARGET" ] || unverified page "no capture test at $TARGET: the spec names it, the development step writes it"

# The package is the nearest pubspec.yaml above the test: in a monorepo the
# app is not at the root, and `flutter test` runs from the package.
PACKAGE_DIR="$(dirname "$PROJECT_DIR/$TARGET")"
while [ ! -f "$PACKAGE_DIR/pubspec.yaml" ]; do
  [ "$PACKAGE_DIR" = "$PROJECT_DIR" ] || [ "$PACKAGE_DIR" = "/" ] && unverified page "no pubspec.yaml above $TARGET: it is not in a Flutter package"
  PACKAGE_DIR="$(dirname "$PACKAGE_DIR")"
done
json_set PACKAGE_DIR "$PACKAGE_DIR"
RELATIVE="${PROJECT_DIR}/${TARGET}"
RELATIVE="${RELATIVE#"$PACKAGE_DIR"/}"

# The SDK the project pins wins: fvm when the package or the repository
# declares a version and fvm is installed, the flutter on the PATH otherwise.
FLUTTER=()
if command -v fvm >/dev/null 2>&1 && { [ -f "$PACKAGE_DIR/.fvmrc" ] || [ -f "$PACKAGE_DIR/.fvm/fvm_config.json" ] \
  || [ -f "$PROJECT_DIR/.fvmrc" ] || [ -f "$PROJECT_DIR/.fvm/fvm_config.json" ]; }; then
  FLUTTER=(fvm flutter)
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER=(flutter)
else
  unverified environment "the Flutter SDK is not installed here: the capture test needs it to render the screen"
fi
json_set FLUTTER "${FLUTTER[*]}"

rm -f "$OUT"
LOG="$(mktemp "${TMPDIR:-/tmp}/flutter-capture.XXXXXX")" || die "cannot create a temporary file"
STAMP="$(mktemp "${TMPDIR:-/tmp}/flutter-capture-stamp.XXXXXX")" || die "cannot create a temporary file"
trap 'rm -f "$LOG" "$STAMP"' EXIT

(cd "$PACKAGE_DIR" && "${FLUTTER[@]}" test --update-goldens --plain-name "$TEST_NAME" \
  --dart-define=VISUAL_CAPTURE_OUT="$OUT" \
  --dart-define=VISUAL_CAPTURE_WIDTH="$WIDTH" \
  --dart-define=VISUAL_CAPTURE_HEIGHT="$HEIGHT" \
  "$RELATIVE") >"$LOG" 2>&1
STATUS=$?
TAIL="$(tail -n 15 "$LOG" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

if [ "$STATUS" -ne 0 ]; then
  if grep -qE 'Operation not permitted|Permission denied|lockfile' "$LOG"; then
    unverified environment "the Flutter SDK could not run here (the sandbox refuses what it writes?): $TAIL"
  fi
  if [ "$STATUS" -eq 79 ] || grep -qE 'No tests (ran|were found|match)' "$LOG"; then
    unverified page "no test named \"$TEST_NAME\" in $TARGET"
  fi
  unverified page "the capture test failed (exit $STATUS): $TAIL"
fi

# matchesGoldenFile resolves the key against the test's folder; an absolute
# path should land where it says, and an image written beside the test under
# the same name is taken and moved, so it is never committed by mistake.
if [ ! -f "$OUT" ]; then
  STRAY="$(find "$PACKAGE_DIR" -name "$(basename "$OUT")" -newer "$STAMP" -not -path '*/.dart_tool/*' -print -quit 2>/dev/null)"
  [ -n "$STRAY" ] && mv "$STRAY" "$OUT"
fi
[ -f "$OUT" ] || unverified page "the test passed but wrote no image: it must call matchesGoldenFile with VISUAL_CAPTURE_OUT, and run only when it is defined"

json_set ACTUAL "$OUT"
json_set REASON "captured at ${WIDTH}x${HEIGHT} by $TARGET › $TEST_NAME"
finish 0
