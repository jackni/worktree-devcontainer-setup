#!/usr/bin/env bash
# A whole worktree through wt + the devcontainer CLI with a throwaway one-repo profile and a made-up
# agent: build, routing by name, the browser over MCP, a profile change recreating the container,
# and down. Uses the prefix e2e- and its own network; removes Traefik afterwards if it started it.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
WT=$here/../wt

tmp=$(cd -P "$(mktemp -d)" && pwd)
had_traefik=$(docker ps -aq --filter name=^wt-traefik$)
export WT_PROFILE=$tmp/prof WT_HOME=$tmp/home XDG_CONFIG_HOME=$tmp/config
N=t C=e2e-t
cleanup() {
  "$WT" down "$N" --force >/dev/null 2>&1
  docker rm -f "$C" >/dev/null 2>&1
  docker rm -f e2e-decoy >/dev/null 2>&1
  docker volume rm -f e2e-fake ${VOL:-} >/dev/null 2>&1
  [ -n "$had_traefik" ] || docker rm -f wt-traefik >/dev/null 2>&1
  docker network rm e2e-net >/dev/null 2>&1
  [ -n "$had_traefik" ] || docker network rm wt-gateway >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/prof/agents" "$WT_HOME"
git init -q --bare -b main "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$WT_HOME/app" 2>/dev/null
git -C "$WT_HOME/app" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$WT_HOME/app" push -q origin HEAD:main && git -C "$WT_HOME/app" fetch -q
echo "fake rules" > "$WT_HOME/FAKE.md"
cat > "$tmp/prof/wt.conf" <<'CONF'
WT_REPO_LIST=app
WT_AGENTS=fake
WT_PREFIX=e2e-
WT_NETWORK=e2e-net
WT_CACHE_DIRS=app/node_modules
WT_SHARED_PORTS=6379
WT_ENV=(E2E_MARK=1)
CONF
cat > "$tmp/prof/agents/fake.sh" <<'AGENT'
AGENT_INSTALL="printf '#!/bin/sh\necho fake-agent\n' > /usr/local/bin/fake-agent && chmod 755 /usr/local/bin/fake-agent"
AGENT_HOME=.fake
AGENT_ENV=("FAKE_HOME=$WT_USER_HOME/.fake")
AGENT_FILES=FAKE.md
AGENT
DIR=$WT_HOME/worktrees/$N
inside() { docker exec -u vscode "$C" bash -c "$1"; }
http_code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: $1" http://127.0.0.1:${WT_HTTP_PORT:-80}/; }
wait_for_route() { for _ in $(seq 1 30); do [ "$(http_code "$1")" = 200 ] && return 0; sleep 1; done; return 1; }
ws_code() { # $1 = Origin value
  local k; k=$(head -c16 /dev/urandom | base64)
  curl -s -o /dev/null -w '%{http_code}' -N --max-time 3 -H "Host: $C.localhost" \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Protocol: binary' -H "Sec-WebSocket-Key: $k" -H "Origin: $1" \
    http://127.0.0.1:${WT_HTTP_PORT:-80}/websockify
}
mcp_initialize() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"e2e","version":"1"}}}' \
    | perl -e 'alarm 60; exec @ARGV' -- $("$WT" mcp "$N") 2>/dev/null | grep -q '"serverInfo"'
}

check "wt up builds and starts it"           "$WT" up "$N" feat/e2e
check "container is running"                 test "$(docker inspect -f '{{.State.Running}}' "$C")" = true
check "it publishes no host ports"           test -z "$(docker port "$C")"
check "traefik routes $C.localhost"          wait_for_route "$C.localhost"
check "unknown name gets 404"                test "$(http_code e2e-nope.localhost)" = 404
check "desktop ws accepts its own origin"    test "$(ws_code "http://$C.localhost")" = 101
check "desktop ws refuses a foreign origin"  test "$(ws_code http://evil.example)" = 404
check "CDP inside the container"             inside 'curl -fs http://127.0.0.1:9222/json/version | grep -q Browser'
check "git works in the worktree"            inside "test \"\$(git -C '$DIR/app' branch --show-current)\" = feat/e2e"
check "the agent is installed"               inside 'test "$(fake-agent)" = fake-agent'
check "the agent's env is set"               inside 'test "$FAKE_HOME" = /home/vscode/.fake'
check "its home is on a volume it owns"      inside 'test "$(stat -c %U ~/.fake)" = vscode'
check "the agent file is visible"            inside "test \"\$(cat '$DIR/FAKE.md')\" = 'fake rules'"
check "the cache dir is a volume it owns"    inside "test \"\$(stat -c %U '$DIR/app/node_modules')\" = vscode"
check "the profile is mounted read-only"     inside '! touch /opt/wt/profile/x 2>/dev/null'
check "a shared port reaches the host"       bash -c "nc -z 127.0.0.1 6379 || exit 0; docker exec -u vscode $C bash -c 'printf \"PING\r\n\" | nc -w1 127.0.0.1 6379 | grep -q PONG'"
check "wt exec runs in the worktree folder"  test "$("$WT" exec "$N" pwd)" = "$DIR"
check "wt mcp gives a working MCP server"    mcp_initialize
check "ls shows it up"                       bash -c "'$WT' ls | grep -q '^$N[[:space:]]Up'"

before=$(docker inspect -f '{{.Id}}' "$C")
check "an unchanged start keeps the container" bash -c "'$WT' start $N >/dev/null && test \"\$(docker inspect -f '{{.Id}}' $C)\" = $before"
sed -i.bak 's/E2E_MARK=1/E2E_MARK=2/' "$tmp/prof/wt.conf"
check "a profile change recreates it"        bash -c "'$WT' start $N | grep -q 'recreating $C'"
check "  with the new env"                   inside 'test "$E2E_MARK" = 2'
check "  and its volumes kept"               inside 'test -d ~/.fake'

VOL=$(sed -n 's/^WT_VOLUMES=//p' "$DIR/.devcontainer/wt.meta")
# another workspace's worktree of the same name: same wt=<name> label, its own folder
docker create --name e2e-decoy --label "wt=$N" --label "wt.dir=/elsewhere/worktrees/$N" \
  "$(docker inspect -f '{{.Config.Image}}' "$C")" true >/dev/null
check "down removes it"                      "$WT" down "$N"
check_fails "container is gone"              docker inspect "$C"
check "another workspace's namesake stays"   docker inspect e2e-decoy
check_fails "cache volume is gone"           docker volume inspect "${VOL:-none}"
check "the agent volume stays for the others" docker volume inspect e2e-fake
check "folder is gone"                       test ! -e "$DIR"
finish
