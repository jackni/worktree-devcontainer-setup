#!/usr/bin/env bash
# Builds a profile's image (WT_PROFILE, default: example) and checks the generic bundle.
# A profile's own checks can live beside it, e.g. profiles/<name>/test/.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
IMG=wt-poc:test
PROFILE=${WT_PROFILE:-example}
USER_=${WT_USER:-vscode}

build_image "$PROFILE" "$IMG" || { echo "FAIL docker build"; exit 1; }
echo "profile: $PROFILE"
run() { docker run --rm -u "$USER_" "$IMG" bash -c "$1"; }

check "node on PATH"                run 'node --version'
check "chromium renders a page"     run 'wt-chromium --headless --no-sandbox --disable-gpu --dump-dom "data:text/html,<p>hi</p>" | grep -q "<p>hi</p>"'
check "kasmvnc Xvnc installed"      run 'command -v Xvnc'
check "xfce installed"              run 'command -v xfce4-session && command -v dbus-launch'
check "socat, nc and ip installed"  run 'command -v socat && command -v nc && command -v ip'
check "chrome-devtools-mcp on PATH" run 'command -v chrome-devtools-mcp'
check "wt-start links the mount"    run 'test "$(readlink /usr/local/bin/wt-start)" = /opt/wt/engine/wt-start'
check "profile bin on PATH"         run 'echo "$PATH" | tr : "\n" | grep -qx /opt/wt/profile/bin'
check "user in ssl-cert group"      run 'id -nG | grep -qw ssl-cert'
check "user has sudo"               run 'sudo -n true'
check "localhost resolves IPv4 first"  run 'node -e "require(\"dns\").lookup(\"localhost\",(e,a)=>process.exit(a===\"127.0.0.1\"?0:1))"'
check "git trusts bind mounts"      run 'git config --system --get-all safe.directory | grep -qx "\*"'
finish
