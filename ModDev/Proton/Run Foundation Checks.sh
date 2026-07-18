#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
if ! command -v ruby >/dev/null 2>&1; then
  echo "[ERROR] Ruby is required to run foundation checks."
  exit 1
fi
ruby "$SCRIPT_DIR/FoundationChecks.rb"
