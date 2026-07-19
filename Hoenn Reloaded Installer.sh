#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENGINE="$SCRIPT_DIR/Hoenn Reloaded Installer.py"

if [ ! -f "$ENGINE" ]; then
  printf '\nHoenn Reloaded Installer.py was not found beside this file.\n'
  printf 'Extract the installer package before running it.\n\n'
  exit 1
fi

exec python3 "$ENGINE" --game-root "$SCRIPT_DIR" "$@"
