#!/usr/bin/env bash
# The plugin skill's install-engine.sh: a fresh install into a workspace, an upgrade that keeps the
# user's profile and agents, its refusals, and wt running from the installed copy. No Docker.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
INSTALL=$here/../skills/wt/scripts/install-engine.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ws=$tmp/ws
eng=$ws/worktree-devcontainers

check "installs into a new workspace"          bash "$INSTALL" "$ws"
check "  wt is executable"                     test -x "$eng/wt"
check "  wt-start is executable"               test -x "$eng/wt-start"
check "  the Dockerfile and compose file"      test -f "$eng/Dockerfile" -a -f "$eng/compose.yaml"
check "  the shipped agents"                   test -f "$eng/agents/claude.sh" -a -f "$eng/agents/codex.sh"
check "  the example profile"                  test -f "$eng/profiles/example/wt.conf"
check "  records the plugin version"           grep -qx "$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$here/../.claude-plugin/plugin.json")" "$eng/.engine-version"
check "  leaves the plugin's own files out"    test ! -e "$eng/.claude-plugin" -a ! -e "$eng/skills" -a ! -e "$eng/test"

# what the skill then sets up: a profile beside the engine, linked from it
mkdir -p "$ws/wt-profile" && echo 'WT_REPO_LIST=app' > "$ws/wt-profile/wt.conf"
ln -sfn ../wt-profile "$eng/profile"
echo 'AGENT_INSTALL=""' > "$eng/agents/mine.sh"
echo stale > "$eng/wt"
check "upgrades in place"                      bash "$INSTALL" "$ws"
check "  replaces engine files"                cmp -s "$eng/wt" "$here/../wt"
check "  keeps the profile link"               test "$(readlink "$eng/profile")" = ../wt-profile
check "  keeps the user's profile"             grep -qx 'WT_REPO_LIST=app' "$ws/wt-profile/wt.conf"
check "  keeps an agent the user added"        test -f "$eng/agents/mine.sh"
check "wt runs from the installed engine"      bash -c "XDG_CONFIG_HOME='$tmp/config' '$eng/wt' ls"

mkdir -p "$tmp/other/worktree-devcontainers" && echo mine > "$tmp/other/worktree-devcontainers/notes"
check_fails "refuses a folder that is not an engine" bash "$INSTALL" "$tmp/other"
check "  and leaves it alone"                  test "$(ls "$tmp/other/worktree-devcontainers")" = notes
git init -q "$tmp/clone/worktree-devcontainers" && cp "$here/../wt" "$tmp/clone/worktree-devcontainers/"
check_fails "refuses a git checkout of the engine" bash "$INSTALL" "$tmp/clone"
check "takes another folder name"              bash "$INSTALL" "$tmp/named" wt-engine
check "  installs there"                       test -x "$tmp/named/wt-engine/wt"
check_fails "refuses no workspace"             bash "$INSTALL"
finish
