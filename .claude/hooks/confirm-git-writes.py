#!/usr/bin/env python3
"""PreToolUse hook: ask for confirmation before git commit / push / merge.

AGENTS.md forbids commit, push and merge without the owner's explicit permission.
This hook turns that rule into a confirmation prompt instead of relying on text alone.
It never blocks silently: it returns permissionDecision "ask" and the user decides.
"""
import json
import re
import sys

# Matches `git commit`, `git push`, `git merge` at the start of a command or after
# a shell separator (; & | ( ). The negative lookahead keeps `merge-base`,
# `commit-tree` and similar plumbing commands out of the match.
GIT_WRITE = re.compile(
    r"(?:^|[;&|(]\s*)git\s+(?:-C\s+\S+\s+)?(commit|push|merge)(?![\w-])"
)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0  # Malformed input must not break the session.

    command = (payload.get("tool_input") or {}).get("command", "") or ""
    match = GIT_WRITE.search(command)
    if not match:
        return 0

    verb = match.group(1)
    reason = (
        f"AGENTS.md: `git {verb}` требует явного разрешения владельца. "
        "Подтвердите, что владелец разрешил это действие."
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "ask",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
