#!/usr/bin/env bash
# Copies the wt engine this plugin carries into a workspace, where wt expects to live: WT_HOME is the
# folder holding the engine, and the plugin's own folder moves on every update. Re-running it
# upgrades the engine in place and leaves the 'profile' link, other profiles and worktrees alone.
set -euo pipefail

usage() { echo "usage: install-engine.sh <workspace> [engine folder name, default: worktree-devcontainers]" >&2; exit 2; }
die() { echo "install-engine.sh: $*" >&2; exit 1; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage

src=$(cd "$(dirname "$0")/../../.." && pwd)
# -f, not -x: an archive install of the plugin may not keep mode bits; they are set below.
[ -f "$src/wt" ] && [ -f "$src/Dockerfile" ] || die "no engine at $src"
mkdir -p "$1"
ws=$(cd "$1" && pwd)
dest=$ws/${2:-worktree-devcontainers}

if [ "$(cd "$dest" 2>/dev/null && pwd -P)" = "$(cd "$src" && pwd -P)" ]; then
  echo "$dest is the plugin's own engine; nothing to copy"
  exit 0
fi
if [ -e "$dest" ]; then
  [ -f "$dest/wt" ] && [ -f "$dest/Dockerfile" ] || die "$dest exists and is not a wt engine; pick another folder name"
  # A clone of the engine repo is upgraded with git, not by copying over its files.
  [ ! -e "$dest/.git" ] || die "$dest is a git checkout of the engine; update it with: git -C '$dest' pull"
fi

mkdir -p "$dest/agents" "$dest/profiles/example"
for f in wt wt-start Dockerfile compose.yaml husky-init.sh README.md GETTING-STARTED.md; do
  cp "$src/$f" "$dest/$f"
done
# Copied over, not replaced, so agents a user added beside the shipped ones survive an upgrade.
cp -R "$src/agents/." "$dest/agents/"
cp -R "$src/profiles/example/." "$dest/profiles/example/"
chmod +x "$dest/wt" "$dest/wt-start"

version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$src/.claude-plugin/plugin.json" 2>/dev/null | head -1)
echo "${version:-unknown}" > "$dest/.engine-version"

echo "engine ${version:-(unknown version)} installed at $dest"
echo "workspace (WT_HOME): $ws"
echo "put wt on your PATH (a symlink to wt does not work): export PATH=\"$dest:\$PATH\""
