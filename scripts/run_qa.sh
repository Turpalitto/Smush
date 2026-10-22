#!/usr/bin/env bash
# Fail on GDScript runtime/parse errors even if Godot exits with status 0.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
GODOT_BIN="${GODOT_BIN:-godot4}"
python3 tools/sync_godot_cache.py
QA_LOG="$(mktemp)"
trap 'rm -f "$QA_LOG"' EXIT
"$GODOT_BIN" --headless --quit-after 600 --path "$TASK_ROOT" res://tests/TestRunner.tscn 2>&1 | tee "$QA_LOG"
if rg -q 'SCRIPT ERROR:|^ERROR:|\[FAIL\]' "$QA_LOG"; then
  echo "Godot reported an error during QA." >&2
  exit 1
fi
if ! rg -q 'TOTAL ASSERTIONS: [1-9][0-9]* PASSED, 0 FAILED' "$QA_LOG"; then
  echo "Godot did not complete the test suite." >&2
  exit 1
fi
