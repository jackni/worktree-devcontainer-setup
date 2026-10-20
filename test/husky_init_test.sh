#!/usr/bin/env bash
# husky-init.sh with a fake docker; never touches a real container or ~/.config.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
INIT=$here/../husky-init.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/worktrees/demo/web/.husky/_" "$tmp/worktrees/demo/.devcontainer" "$tmp/web" \
  "$tmp/worktrees/other/web/.husky/_"
wt_repo=$tmp/worktrees/demo/web
# wt marks a worktree folder with .devcontainer/wt.meta; the container and its user come from it.
printf 'WT_NAME=demo\nWT_CONTAINER=dev-demo\nWT_USER=coder\n' > "$tmp/worktrees/demo/.devcontainer/wt.meta"
# The fake records each call; FAKE_RUNNING=false stands for a stopped container.
cat > "$tmp/bin/docker" <<'FAKE'
#!/bin/sh
echo "$*" >> "$FAKE_LOG"
case "$1" in
  inspect) echo "${FAKE_RUNNING:-true}" ;;
  exec) cat > "$FAKE_LOG.stdin"; exit 7 ;;
esac
FAKE
chmod +x "$tmp/bin/docker"
export PATH="$tmp/bin:$PATH" FAKE_LOG=$tmp/docker.log

# Runs a hook the way husky's .husky/_/h does: $0 is the hook, init.sh is sourced, then the hook runs.
cat > "$tmp/bin/run-hook" <<'RUN'
#!/bin/sh
cd "$1" && shift
printf 'refs\n' | sh -c 'i=$1; shift; . "$i"; echo HOOK-RAN-HERE' .husky/_/pre-push "$INIT" "$@"
RUN
chmod +x "$tmp/bin/run-hook"
export INIT
ran_here() { run-hook "$@" | grep -q HOOK-RAN-HERE; }
exits_7() { run-hook "$@"; test $? -eq 7; }

: > "$FAKE_LOG"
check "a worktree hook runs in its container"  exits_7 "$wt_repo" origin url
check "  in its container, from the same folder" grep -q -- "exec -i .*-w $wt_repo dev-demo sh .husky/_/pre-push origin url\$" "$FAKE_LOG"
check "  as the container's user, not root"    grep -q -- "exec -i -u coder " "$FAKE_LOG"
check "  with the hook's stdin"                grep -qx refs "$FAKE_LOG.stdin"
: > "$FAKE_LOG"
GIT_INDEX_FILE=/x/index.lock run-hook "$wt_repo" >/dev/null 2>&1
check "  and git's own variables"              grep -q -- "-e GIT_INDEX_FILE" "$FAKE_LOG"
check_fails "a stopped container fails the hook" env FAKE_RUNNING=false bash -c "$(declare -f ran_here); ran_here '$wt_repo'"
check "  and says how to start it"             bash -c "FAKE_RUNNING=false run-hook '$wt_repo' 2>&1 | grep -q 'wt start demo'"
check "HUSKY=0 is left to husky"               env HUSKY=0 bash -c "$(declare -f ran_here); ran_here '$wt_repo'"
check "a main checkout runs its own hook"      ran_here "$tmp/web"
check "a folder without wt.meta runs its own"  ran_here "$tmp/worktrees/other/web"
mkdir -p "$wt_repo/node_modules" && touch "$wt_repo/node_modules/.yarn-state.yml"
check "installed packages run the hook here"   ran_here "$wt_repo"
finish
