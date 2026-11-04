#!/usr/bin/env bash
# Fail on GDScript runtime/parse errors even if Godot exits with status 0.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"
GODOT_BIN="${GODOT_BIN:-godot4}"
python3 tools/sync_godot_cache.py
QA_LOG="$(mktemp)"
trap 'rm -f "$QA_LOG"' EXIT

# A fresh clone has no .godot/imported cache: .godot/ is gitignored and the .ctex
# files are generated, so the test scene cannot load a single PNG and the run dies
# with "Failed loading resource: res://.godot/imported/root_cluster.png-....ctex".
# That is why CI was red for days while QA was green on a developer machine, where
# the cache already existed. Import first, then test.
"$GODOT_BIN" --headless --path "$TASK_ROOT" --import >/dev/null 2>&1 || true
if [ ! -d "$TASK_ROOT/.godot/imported" ]; then
  echo "Asset import produced no .godot/imported directory; textures would fail to load." >&2
  exit 1
fi

# Prefer ripgrep, fall back to grep: macOS/CI images often ship without rg.
if command -v rg >/dev/null 2>&1; then
  log_matches() { rg -q "$1" "$QA_LOG"; }
else
  log_matches() { grep -Eq "$1" "$QA_LOG"; }
fi

"$GODOT_BIN" --headless --quit-after 600 --path "$TASK_ROOT" res://tests/TestRunner.tscn 2>&1 | tee "$QA_LOG"
# Godot prints shutdown messages after the suite has finished ("N resources still in use at
# exit", "N RID allocations ... leaked at exit"). They are not test failures, so they are
# excluded here and counted for the record. Real script errors and [FAIL] lines still fail.
# No -q here: grep -q exits early and, with pipefail, would turn a match into a failure.
EXIT_NOISE="$(grep -c -E '(still in use|leaked) at exit' "$QA_LOG" || true)"
if [ "$EXIT_NOISE" -gt 0 ]; then
  echo "Ignored $EXIT_NOISE Godot shutdown message(s) about resources/leaks at exit." >&2
fi
REAL_ERRORS="$(grep -v -E '(still in use|leaked) at exit' "$QA_LOG" | grep -E 'SCRIPT ERROR:|^ERROR:|\[FAIL\]' || true)"
if [ -n "$REAL_ERRORS" ]; then
  echo "$REAL_ERRORS" >&2
  echo "Godot reported an error during QA." >&2
  exit 1
fi
if ! log_matches 'TOTAL ASSERTIONS: [1-9][0-9]* PASSED, 0 FAILED'; then
  echo "Godot did not complete the test suite." >&2
  exit 1
fi
