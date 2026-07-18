#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_URL="https://github.com/Stonewallxx/Hoenn-Reloaded-Mods.git"
PYTHON_TOOL="$SCRIPT_DIR/PublishToGitHub.py"
TEMP_PARENT="${TMPDIR:-/tmp}"
CHECKOUT_DIR="$(mktemp -d "$TEMP_PARENT/hoenn-reloaded-publisher.XXXXXX")" || exit 1

finish() {
  status=$?
  rm -rf -- "$CHECKOUT_DIR"
  printf '\nPress Enter to close...'
  read -r _
  trap - EXIT
  exit "$status"
}
trap finish EXIT

printf '%s\n' '============================================'
printf '%s\n' '      Hoenn Reloaded GitHub Publisher'
printf '%s\n\n' '              Proton Edition'

command -v git >/dev/null 2>&1 || { echo '[ERROR] Git is required.'; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo '[ERROR] Python 3 is required.'; exit 1; }
test -f "$PYTHON_TOOL" || { echo '[ERROR] PublishToGitHub.py is missing.'; exit 1; }

echo 'Creating temporary sparse publisher checkout...'
git clone --depth 1 --filter=blob:none --no-checkout "$REPO_URL" "$CHECKOUT_DIR" || exit 1
git -C "$CHECKOUT_DIR" sparse-checkout init --no-cone || exit 1

git -C "$CHECKOUT_DIR" sparse-checkout set --no-cone '/index.json' || exit 1
git -C "$CHECKOUT_DIR" checkout main >/dev/null 2>&1 || git -C "$CHECKOUT_DIR" checkout master || exit 1
git -C "$CHECKOUT_DIR" pull --ff-only origin main || exit 1

python3 "$PYTHON_TOOL" --game "$GAME_DIR" --repo "$CHECKOUT_DIR" || exit 1

if test -z "$(git -C "$CHECKOUT_DIR" status --porcelain)"; then
  echo 'No changes detected.'
  exit 0
fi

COMMIT_MESSAGE="$(cat "$CHECKOUT_DIR/.reloaded_commit_message")"
rm -f "$CHECKOUT_DIR/.reloaded_commit_message"
git -C "$CHECKOUT_DIR" add . || exit 1
git -C "$CHECKOUT_DIR" commit -m "$COMMIT_MESSAGE" || exit 1
git -C "$CHECKOUT_DIR" push origin main || {
  echo '[ERROR] Push failed. The temporary checkout will be removed.'
  echo 'Confirm collaborator access or Git credentials, then try again.'
  exit 1
}

echo 'SUCCESS. Published to GitHub.'
