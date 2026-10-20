# Minimal assertions for the PoC's bash tests.
fails=0

check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc"; fails=$((fails + 1)); fi
}

check_fails() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo "FAIL $desc (expected a failure)"; fails=$((fails + 1)); else echo "ok   $desc"; fi
}

finish() {
  if [ "$fails" -eq 0 ]; then echo "PASS"; else echo "$fails check(s) failed"; exit 1; fi
}

# Builds the image a profile's worktrees get, with the build args wt generates for it.
build_image() { # profile tag
  local wt home dc
  wt=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wt
  home=$(mktemp -d)
  mkdir -p "$home/worktrees/img"
  WT_PROFILE=$1 WT_HOME=$home "$wt" sync img >/dev/null || { rm -rf "$home"; return 1; }
  dc=$home/worktrees/img/.devcontainer/devcontainer.json
  local a=() kv
  while IFS= read -r -d '' kv; do a+=(--build-arg "$kv"); done < <(node -e '
    const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8").replace(/^\s*\/\/.*$/mg,""));
    for (const [k,v] of Object.entries(c.build.args)) process.stdout.write(k+"="+v+"\0")' "$dc")
  rm -rf "$home"
  docker build -t "$2" "${a[@]}" "$(dirname "$wt")"
}
