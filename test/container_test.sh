#!/usr/bin/env bash
# wt-start in a bare container with the engine and a throwaway profile mounted as wt mounts them:
# desktop, CDP, forwards from wt.meta, volume ownership, profile hooks, re-run and restart safety.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
IMG=wt-poc:test
C=wt-smoke

tmp=$(mktemp -d)
mkdir -p "$tmp/profile/post-start.d" "$tmp/profile/bin"
cat > "$tmp/profile/post-start.d/10-mark.sh" <<'HOOK'
echo "$WT_NAME $WT_INFRA" >> "$HOME/hook-ran"
HOOK
printf '#!/bin/sh\necho from-profile-bin\n' > "$tmp/profile/bin/wt-hello" && chmod 755 "$tmp/profile/bin/wt-hello"

build_image example "$IMG" >/dev/null || { echo "FAIL docker build"; exit 1; }
docker rm -f "$C" >/dev/null 2>&1 || true
docker run -d --name "$C" --hostname "$C" -e WT_DIR=/tmp/wt \
  -v "$here/..:/opt/wt/engine:ro" -v "$tmp/profile:/opt/wt/profile:ro" "$IMG" sleep infinity >/dev/null
trap 'docker rm -f "$C" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
inside() { docker exec -u vscode "$C" bash -c "$1"; }
wait_for() { for _ in $(seq 1 30); do inside "$1" >/dev/null 2>&1 && return 0; sleep 1; done; return 1; }

# what wt generates: the worktree's meta, and root-owned mount points as Docker makes for volumes
docker exec "$C" bash -c 'mkdir -p /tmp/wt/.devcontainer /tmp/wt/app/node_modules /home/vscode/.agent \
  && chown root:root /tmp/wt/app/node_modules /home/vscode/.agent \
  && printf "WT_NAME=smoke\nWT_CONTAINER=wt-smoke\nWT_SHARED_PORTS=\"6379\"\nWT_ISOLATABLE_PORTS=\"6432\"\nWT_OWNED_DIRS=\"/tmp/wt/app/node_modules /home/vscode/.agent\"\n" > /tmp/wt/.devcontainer/wt.meta \
  && chown vscode /tmp/wt && chown -R vscode /tmp/wt/.devcontainer'

check "wt-start succeeds"                    inside 'wt-start'
check "desktop ready when wt-start returns"  inside 'curl -fs -o /dev/null http://127.0.0.1:6901/'
check "CDP ready when wt-start returns"      inside 'curl -fs http://127.0.0.1:9222/json/version | grep -q Browser'
check "desktop listens beyond loopback"      inside 'curl -fs -o /dev/null "http://$(hostname -i | cut -d" " -f1):6901/"'
check "shared port forwarded"                inside 'pgrep -f "[T]CP-LISTEN:6379,"'
check "isolatable port forwarded in shared"  inside 'pgrep -f "[T]CP-LISTEN:6432,"'
check "cache dir handed to the user"         inside 'test "$(stat -c %U /tmp/wt/app/node_modules)" = vscode'
check "agent home handed to the user"        inside 'test "$(stat -c %U /home/vscode/.agent)" = vscode'
check "profile hook ran with its env"        inside 'grep -qx "smoke shared" ~/hook-ran'
check "profile bin on PATH"                  inside 'test "$(wt-hello)" = from-profile-bin'

check "second wt-start succeeds"             inside 'wt-start'
check "one Xvnc after re-run"                inside 'test "$(pgrep -cx Xvnc)" = 1'
check "one forward on 6379 after re-run"     inside 'test "$(pgrep -cf "[T]CP-LISTEN:6379,")" = 1'
check "one chromium browser after re-run"    inside 'test "$(pgrep -af "[-]-remote-debugging-port=9222" | grep -vc -- "--type=")" = 1'

inside 'echo WT_INFRA=isolated > /tmp/wt/wt.env'
check "isolated wt-start succeeds"           inside 'wt-start'
check "isolatable port released"             inside '! pgrep -f "[T]CP-LISTEN:6432,"'
check "shared port still forwarded"          inside 'pgrep -f "[T]CP-LISTEN:6379,"'
inside 'rm /tmp/wt/wt.env'

docker restart "$C" >/dev/null
check "wt-start after restart succeeds"      inside 'wt-start'
check "CDP ready after restart's wt-start"   inside 'curl -fs http://127.0.0.1:9222/json/version | grep -q Browser'
check "desktop back after restart"           wait_for 'curl -fs -o /dev/null http://127.0.0.1:6901/'

echo 'exit 3' > "$tmp/profile/post-start.d/20-broken.sh"
check_fails "a failing hook fails wt-start"  inside 'wt-start'
check "  but the desktop is still up"        inside 'curl -fs http://127.0.0.1:9222/json/version | grep -q Browser'
check "  and the hook is named"              bash -c "docker exec -u vscode '$C' wt-start 2>&1 | grep -q 20-broken.sh"
rm "$tmp/profile/post-start.d/20-broken.sh"

check_fails "unknown WT_INFRA is rejected"   docker exec -u vscode -e WT_DIR=/tmp/bad "$C" bash -c 'mkdir -p /tmp/bad && echo WT_INFRA=typo > /tmp/bad/wt.env && wt-start'
finish
