#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GAME_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
if [ -n "${1:-}" ]; then
  python3 "$SCRIPT_DIR/RepositoryTool.py" --action publish --kind "$1" --game "$GAME_ROOT"
else
  python3 "$SCRIPT_DIR/RepositoryTool.py" --action publish --game "$GAME_ROOT"
fi
status=$?
printf '\n'
if [ "$status" -ne 0 ]; then printf 'Publisher failed with exit code %s.\n' "$status"; fi
printf 'Press Enter to close...'
read -r _unused
exit "$status"
