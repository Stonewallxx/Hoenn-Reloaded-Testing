#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GAME_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
args=(--action update --game "$GAME_ROOT")
if [ -n "${1:-}" ]; then args+=(--kind "$1"); fi
python3 "$SCRIPT_DIR/RepositoryTool.py" "${args[@]}"
status=$?
printf '\n'
if [ "$status" -ne 0 ]; then printf 'Update failed with exit code %s.\n' "$status"; fi
printf 'Press Enter to close...'
read -r _unused
exit "$status"
