#!/usr/bin/env bash
# The engine with varied setups: one repo, three repos, a made-up agent, custom
# naming. Throwaway repos and profiles; needs Docker running only for `wt down`.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
WT=$here/../wt

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME=$tmp/config
# Each repo is a clone, so origin/HEAD exists and new branches start there without WT_BASE.
repo() { # home name
  git init -q --bare -b trunk "$tmp/origin-$2.git"
  git clone -q "$tmp/origin-$2.git" "$1/$2" 2>/dev/null
  git -C "$1/$2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$1/$2" push -q origin HEAD:trunk
  git -C "$1/$2" fetch -q
}
# devcontainer.json is JSONC: drop the comment lines, then let node answer a question about it.
jq_dc() { # file js-expression
  node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8").replace(/^\s*\/\/.*$/mg,"");
    const c=JSON.parse(t); const r=eval(process.argv[2]); if(!r) process.exit(1)' "$1" "$2"
}

# --- one repo, no agents, defaults everywhere ---
one=$tmp/one
mkdir -p "$one/prof"
repo "$one" app
echo 'WT_REPO_LIST=app' > "$one/prof/wt.conf"
run1() { WT_PROFILE=$one/prof WT_HOME=$one "$WT" "$@"; }
dc1=$one/worktrees/s1/.devcontainer/devcontainer.json
check "one repo: new with one branch"        run1 new s1 feat/s1
check "  branch starts at origin/HEAD"        test "$(git -C "$one/worktrees/s1/app" rev-parse HEAD)" = "$(git -C "$one/app" rev-parse origin/trunk)"
check "  config is valid JSON"               jq_dc "$dc1" 'true'
check "  default prefix and network"         jq_dc "$dc1" 'c.name==="wt-s1" && c.runArgs.includes("wt")'
check "  default base image"                 jq_dc "$dc1" 'c.build.args.BASE_IMAGE==="mcr.microsoft.com/devcontainers/base:noble"'
check "  the repo's .git is mounted"         jq_dc "$dc1" "c.mounts.some(m=>m.includes('$(cd -P "$one" && pwd)/app/.git,'))"
check "  no agent volumes"                   jq_dc "$dc1" '!c.mounts.some(m=>m.includes("type=volume"))'
check "  no agent links"                     test -z "$(find "$one/worktrees/s1" -maxdepth 1 -type l)"
check "  no husky link without .husky"       test ! -e "$XDG_CONFIG_HOME/husky/init.sh"
check_fails "one repo: two branches refused" run1 new s2 a b
check_fails "  --infra isolated without isolated.sh" run1 new s3 b3 --infra isolated
check "  ls lists it"                        bash -c "WT_PROFILE='$one/prof' WT_HOME='$one' '$WT' ls | grep -q '^s1'"
check "  mcp prints a docker exec command"   bash -c "WT_PROFILE='$one/prof' WT_HOME='$one' '$WT' mcp s1 | grep -q '^docker exec -i -u vscode .* wt-s1 chrome-devtools-mcp '"
check "  env overrides the profile"          bash -c "WT_PREFIX=zz- WT_PROFILE='$one/prof' WT_HOME='$one' '$WT' sync s1 && grep -q '\"name\": \"zz-s1\"' '$dc1'"
run1 sync s1 >/dev/null

# an older worktree whose .devcontainer linked the engine is converted
rm -r "$one/worktrees/s1/.devcontainer" && ln -s "$here/.." "$one/worktrees/s1/.devcontainer"
check "  sync replaces the old engine link"  bash -c "WT_PROFILE='$one/prof' WT_HOME='$one' '$WT' sync s1 && test ! -L '$one/worktrees/s1/.devcontainer' && test -s '$dc1'"
check "  the engine is untouched"            test ! -e "$here/../devcontainer.json"
check "one repo: down"                       run1 down s1
check "  leaves nothing"                     test ! -e "$one/worktrees/s1"

# --- three repos, a made-up agent, custom naming and caches ---
three=$tmp/three
mkdir -p "$three/prof/agents" "$three/.fake-rules"
for r in api web docs; do repo "$three" $r; done
mkdir -p "$three/web/.husky"
echo rules > "$three/FAKE.md"
cat > "$three/prof/wt.conf" <<'CONF'
WT_REPO_LIST="api web docs"
WT_AGENTS="fake"
WT_PREFIX=dev-
WT_DOMAIN=test.localhost
WT_NETWORK=devnet
WT_USER=coder
WT_BASE_IMAGE=debian:bookworm
WT_CACHE_DIRS="web/node_modules nm:api/node_modules"
WT_ENV=(PLAIN=1 'SPACED=a b "quoted"' 'KEY=${localEnv:FAKE_KEY}')
WT_SHARED_PORTS="5432 6379"
WT_DISPOSABLE_DIRS='generated'
CONF
cat > "$three/prof/agents/fake.sh" <<'AGENT'
AGENT_INSTALL="echo installing fake"
AGENT_HOME=.fake
AGENT_ENV=("FAKE_HOME=$WT_USER_HOME/.fake")
AGENT_FILES="FAKE.md .fake-rules missing.md FAKE.md"
AGENT
run3() { WT_PROFILE=$three/prof WT_HOME=$three "$WT" "$@"; }
t1=$three/worktrees/t1
dc3=$t1/.devcontainer/devcontainer.json
check "three repos: one branch for all"      run3 new t1 feat/all
check "  every repo on that branch"          bash -c "for r in api web docs; do test \"\$(git -C '$t1'/\$r branch --show-current)\" = feat/all || exit 1; done"
check "  three .git mounts"                  jq_dc "$dc3" 'c.mounts.filter(m=>/\.git,target=/.test(m)).length===3'
check "  custom container name"              jq_dc "$dc3" 'c.name==="dev-t1" && c.runArgs.includes("--hostname") && c.runArgs.includes("devnet")'
check "  traefik told the network"          jq_dc "$dc3" 'c.runArgs.includes("traefik.docker.network=devnet")'
check "  user and home"                      jq_dc "$dc3" 'c.remoteUser==="coder" && c.build.args.USERNAME==="coder"'
id1=$(cd -P "$t1" 2>/dev/null && pwd | cksum | cut -d' ' -f1)
check "  labelled cache volume"              jq_dc "$dc3" "c.mounts.includes('source=dev-t1-$id1-nm,target=$t1/api/node_modules,type=volume')"
check "  derived cache volume name"          jq_dc "$dc3" "c.mounts.includes('source=dev-t1-$id1-web-node_modules,target=$t1/web/node_modules,type=volume')"
check "  container labelled with its folder" jq_dc "$dc3" "c.runArgs.includes('wt.dir=$t1')"
check "  agent home on a shared volume"      jq_dc "$dc3" 'c.mounts.includes("source=dev-fake,target=/home/coder/.fake,type=volume")'
check "  agent install as a build arg"       jq_dc "$dc3" 'c.build.args.AGENT_SETUP.includes("echo installing fake")'
check "  agent and profile env"              jq_dc "$dc3" 'c.containerEnv.FAKE_HOME==="/home/coder/.fake" && c.containerEnv.PLAIN==="1" && c.containerEnv.WT_NAME==="t1"'
check "  values keep spaces and quotes"      jq_dc "$dc3" 'c.containerEnv.SPACED==="a b \"quoted\""'
check "  localEnv passes through"            jq_dc "$dc3" 'c.containerEnv.KEY==="${localEnv:FAKE_KEY}"'
check "  traefik rule uses the domain"       jq_dc "$dc3" 'c.runArgs.some(a=>a.includes("Host(`dev-t1.test.localhost`)") && a.includes("dev-t1\\.test\\.localhost(:[0-9]+)?$"))'
check "  agent file linked"                  test "$(readlink "$t1/FAKE.md")" = ../../FAKE.md
check "  agent folder linked"                test "$(readlink "$t1/.fake-rules")" = ../../.fake-rules
check "  missing agent file skipped"         test ! -e "$t1/missing.md" -a ! -L "$t1/missing.md"
check "  agent file mounted once"            jq_dc "$dc3" "c.mounts.filter(m=>m.startsWith('source=$three/FAKE.md,')).length===1"
check "  meta names the container"           grep -qx 'WT_CONTAINER=dev-t1' "$t1/.devcontainer/wt.meta"
check "  meta names the user"                grep -qx 'WT_USER=coder' "$t1/.devcontainer/wt.meta"
check "  meta lists the owned dirs"          bash -c ". '$t1/.devcontainer/wt.meta' && test \"\$WT_OWNED_DIRS\" = '$t1/web/node_modules $t1/api/node_modules /home/coder/.fake'"
check "  meta carries the ports"             bash -c ". '$t1/.devcontainer/wt.meta' && test \"\$WT_SHARED_PORTS\" = '5432 6379'"
check "  husky linked when a repo uses it"   test "$(readlink "$XDG_CONFIG_HOME/husky/init.sh")" = "$(cd "$here/.." && pwd)/husky-init.sh"
check "  sync leaves an unchanged file alone" bash -c "before=\$(stat -f %m '$dc3' 2>/dev/null || stat -c %Y '$dc3'); sleep 1; WT_PROFILE='$three/prof' WT_HOME='$three' '$WT' sync t1 >/dev/null; test \"\$before\" = \"\$(stat -f %m '$dc3' 2>/dev/null || stat -c %Y '$dc3')\""
check "  devcontainer CLI reads the config"  bash -c "command -v devcontainer >/dev/null || exit 0; devcontainer read-configuration --workspace-folder '$t1' >/dev/null 2>&1"
check "three repos: one branch per repo"     run3 new t2 b-api b-web b-docs
check "  each on its own"                    test "$(git -C "$three/worktrees/t2/docs" branch --show-current)" = b-docs
check_fails "three repos: two branches refused" run3 new t3 x y
check "  and nothing left behind"            test ! -e "$three/worktrees/t3"

# rollback: the second repo's branch is checked out in its main checkout, so its worktree fails
git -C "$three/web" checkout -q -b busy
check_fails "a failed repo rolls back"       run3 new t4 ok busy ok
check "  no folder"                          test ! -e "$three/worktrees/t4"
check_fails "  no api worktree"              bash -c "git -C '$three/api' worktree list | grep -q /t4"

mkdir -p "$t1/web/generated" && echo x > "$t1/web/generated/out.js"
printf 'generated/\n.env.local\n' > "$t1/web/.gitignore"
git -C "$t1/web" -c user.email=t@t -c user.name=t add .gitignore && git -C "$t1/web" -c user.email=t@t -c user.name=t commit -q -m ignore
check "profile's disposable dirs don't block down" bash -c "WT_PROFILE='$three/prof' WT_HOME='$three' '$WT' down t1"
check "  links, config and folder gone"      test ! -e "$t1"
check "  the workspace file survives"        test -s "$three/FAKE.md"
check "down t2"                              run3 down t2

# --- two workspaces, one worktree name, default prefix: down touches only its own ---
for w in a b; do
  mkdir -p "$tmp/twin-$w/prof"
  repo "$tmp/twin-$w" "tw$w"
  printf 'WT_REPO_LIST=tw%s\nWT_CACHE_DIRS=nm:tw%s/node_modules\n' $w $w > "$tmp/twin-$w/prof/wt.conf"
done
runt() { local w=$1; shift; WT_PROFILE=$tmp/twin-$w/prof WT_HOME=$tmp/twin-$w "$WT" "$@"; }
twin_vol() { sed -n 's/^WT_VOLUMES=//p' "$tmp/twin-$1/worktrees/${2:-w}/.devcontainer/wt.meta"; }
runt a new w b1 >/dev/null 2>&1; runt b new w b1 >/dev/null 2>&1
va=$(twin_vol a) vb=$(twin_vol b)
check "same name in two workspaces: two cache volumes" test -n "$va" -a -n "$vb" -a "$va" != "$vb"
docker volume create "$va" >/dev/null 2>&1; docker volume create "$vb" >/dev/null 2>&1
check "  down removes its own volume"        bash -c "WT_PROFILE='$tmp/twin-b/prof' WT_HOME='$tmp/twin-b' '$WT' down w && ! docker volume inspect '$vb'"
check "  and leaves the other workspace's"   docker volume inspect "$va"
runt a down w >/dev/null 2>&1
docker volume rm -f "$va" "$vb" >/dev/null 2>&1

# --- the container can write wt.meta: down parses it, never runs it, and deletes only its own ---
runt a new m b2 >/dev/null 2>&1
vm=$(twin_vol a m) foreign=wt-review-foreign-$$
docker volume create "$vm" >/dev/null 2>&1; docker volume create "$foreign" >/dev/null 2>&1
printf 'touch %s\nWT_VOLUMES=%s\\ %s\n' "$tmp/pwned" "$vm" "$foreign" >> "$tmp/twin-a/worktrees/m/.devcontainer/wt.meta"
check "down with a tampered wt.meta"         runt a down m
check "  ran nothing from it"                test ! -e "$tmp/pwned"
check "  removed its own volume"             bash -c "! docker volume inspect '$vm'"
check "  ignored a volume it does not own"   docker volume inspect "$foreign"
docker volume rm -f "$vm" "$foreign" >/dev/null 2>&1

# --- bad profiles ---
mkdir -p "$tmp/bad"
echo 'WT_REPO_LIST=""' > "$tmp/bad/wt.conf"
check_fails "a profile without repos fails"  env WT_PROFILE=$tmp/bad WT_HOME=$one "$WT" ls
printf 'WT_REPO_LIST=app\nWT_AGENTS=nope\n' > "$tmp/bad/wt.conf"
check_fails "an unknown agent fails"         env WT_PROFILE=$tmp/bad WT_HOME=$one "$WT" ls
check_fails "a missing profile fails"        env WT_PROFILE=$tmp/none WT_HOME=$one "$WT" ls
check "every shipped agent loads"            bash -c "printf 'WT_REPO_LIST=app\nWT_AGENTS=\"%s\"\n' \"\$(cd '$here/../agents' && ls *.sh | sed 's/\.sh\$//' | tr '\n' ' ')\" > '$tmp/bad/wt.conf' && WT_PROFILE='$tmp/bad' WT_HOME='$one' '$WT' ls"
check "the example profile loads"            env WT_PROFILE=example WT_HOME=$one "$WT" ls
finish
