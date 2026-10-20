#!/usr/bin/env bash
# Checks what wt needs on the host, one line per check. Exits 1 when a required one fails;
# warnings are things that will bite later but don't block a first `wt up`.
set -uo pipefail

failed=0
ok()   { echo "ok    $*"; }
warn() { echo "warn  $*"; }
fail() { echo "FAIL  $*"; failed=1; }

if v=$(git --version 2>/dev/null); then
  # wt mounts each worktree's git dir by the path `git rev-parse --path-format=absolute` gives (2.31+).
  read -r maj min <<<"$(echo "$v" | sed -n 's/^git version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')"
  if [ "${maj:-0}" -gt 2 ] || { [ "${maj:-0}" -eq 2 ] && [ "${min:-0}" -ge 31 ]; }; then
    ok "$v"
  else
    fail "$v is too old: wt needs git 2.31 or later"
  fi
else
  fail "git is not installed"
fi

if ! command -v docker >/dev/null; then
  fail "docker is not installed (Docker Desktop on macOS and Windows, Docker Engine on Linux)"
elif ! docker info >/dev/null 2>&1; then
  fail "Docker is installed but not running, or this user cannot reach it"
else
  ok "docker $(docker version -f '{{.Server.Version}}' 2>/dev/null)"
  if docker compose version >/dev/null 2>&1; then ok "docker compose"; else fail "the docker compose plugin is missing"; fi
fi

if command -v devcontainer >/dev/null; then
  ok "devcontainer CLI $(devcontainer --version 2>/dev/null)"
else
  fail "devcontainer CLI missing: npm i -g @devcontainers/cli"
fi

# One Traefik per machine serves every desktop on loopback WT_HTTP_PORT (default 80).
port=${WT_HTTP_PORT:-80}
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx wt-traefik; then
  ok "wt's Traefik is already running"
elif (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
  warn "port $port is taken by something else: export WT_HTTP_PORT=8080 (desktops then at http://wt-<name>.localhost:8080)"
else
  ok "port $port is free for wt's Traefik"
fi

# Under WSL, folders on the Windows drive are slow to mount and not valid inside the container.
if [ -n "${1:-}" ] && grep -qi microsoft /proc/version 2>/dev/null; then
  case $(cd "$1" 2>/dev/null && pwd) in
    /mnt/*) fail "$1 is on the Windows drive; keep the workspace in the WSL file system (~/...)" ;;
  esac
fi

exit "$failed"
