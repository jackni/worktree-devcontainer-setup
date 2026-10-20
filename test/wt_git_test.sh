#!/usr/bin/env bash
# wt new/ls/down with a two-repo profile and two agents, against throwaway repos.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
WT=$here/../wt

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export WT_PROFILE=$tmp/profile WT_HOME=$tmp/poc WT_REPOS=$tmp/repos XDG_CONFIG_HOME=$tmp/config
mkdir -p "$WT_HOME/.claude" "$WT_REPOS" "$WT_PROFILE"
cat > "$WT_PROFILE/wt.conf" <<'CONF'
WT_REPO_LIST="backend frontend"
WT_BASE=origin/dev
WT_AGENTS="claude codex"
WT_CACHE_DIRS="be-nm:backend/node_modules fe-nm:frontend/node_modules"
WT_DISPOSABLE_DIRS='\.yarn/(cache|install-state\.gz)'
CONF
echo 'exit 0' > "$WT_PROFILE/isolated.sh"   # its presence enables --infra isolated
touch "$WT_HOME/CLAUDE.md" "$WT_HOME/AGENTS.md"
for r in backend frontend; do
  git init -q -b dev "$WT_REPOS/$r"
  mkdir -p "$WT_REPOS/$r/.husky"
  git -C "$WT_REPOS/$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git init -q --bare "$tmp/origin-$r.git"
  git -C "$WT_REPOS/$r" remote add origin "$tmp/origin-$r.git"
  git -C "$WT_REPOS/$r" push -q origin dev
done
worktree_listed() { git -C "$WT_REPOS/$1" worktree list | grep -q "/worktrees/$2/"; }

# naming
check_fails "rejects uppercase name"          "$WT" new Bad-Name b1 f1
check_fails "rejects underscore name"         "$WT" new bad_name b1 f1
check_fails "rejects slash name"              "$WT" new a/b b1 f1
check "rejected names create nothing"         test ! -e "$WT_HOME/worktrees"

# origin/dev moves ahead of local dev, as when a colleague merges and Jack has not pulled
be_repo=$WT_REPOS/backend
local_dev=$(git -C "$be_repo" rev-parse dev)
clone=$tmp/colleague
git clone -q -b dev "$tmp/origin-backend.git" "$clone"
git -C "$clone" -c user.email=t@t -c user.name=t commit -q --allow-empty -m merged
git -C "$clone" push -q origin dev

# happy path
check "new creates both worktrees"            "$WT" new a1 feat/be-a1 feat/fe-a1
check "new branch starts at origin/dev"       test "$(git -C "$WT_HOME/worktrees/a1/backend" rev-parse HEAD)" = "$(git -C "$clone" rev-parse HEAD)"
check "local dev is left where it was"        test "$(git -C "$be_repo" rev-parse dev)" = "$local_dev"
check_fails "new branch has no upstream"      git -C "$WT_HOME/worktrees/a1/backend" rev-parse --abbrev-ref '@{upstream}'
check "backend worktree on its branch"        test "$(git -C "$WT_HOME/worktrees/a1/backend" branch --show-current)" = feat/be-a1
check "frontend worktree on its branch"       test "$(git -C "$WT_HOME/worktrees/a1/frontend" branch --show-current)" = feat/fe-a1
check "wt.env defaults to shared"             grep -qx 'WT_INFRA=shared' "$WT_HOME/worktrees/a1/wt.env"
check "--infra isolated is recorded"          bash -c "'$WT' new a0 b0 f0 --infra isolated && grep -qx 'WT_INFRA=isolated' '$WT_HOME/worktrees/a0/wt.env'"
check_fails "--infra rejects another value"   "$WT" new a9 b9 f9 --infra maybe
check "devcontainer.json is generated"       test -s "$WT_HOME/worktrees/a1/.devcontainer/devcontainer.json"
check "  naming the container wt-a1"          grep -q '"name": "wt-a1"' "$WT_HOME/worktrees/a1/.devcontainer/devcontainer.json"
check "  with the be node_modules volume"     grep -q "source=wt-a1-$(cd -P "$WT_HOME/worktrees/a1" 2>/dev/null && pwd | cksum | cut -d' ' -f1)-be-nm,target=$WT_HOME/worktrees/a1/backend/node_modules,type=volume" "$WT_HOME/worktrees/a1/.devcontainer/devcontainer.json"
check "  and the shared claude login"         grep -q 'source=wt-claude,target=/home/vscode/.claude,type=volume' "$WT_HOME/worktrees/a1/.devcontainer/devcontainer.json"
check "CLAUDE.md links to the workspace one"  test "$(readlink "$WT_HOME/worktrees/a1/CLAUDE.md")" = ../../CLAUDE.md
check ".claude links to the workspace one"    test "$(readlink "$WT_HOME/worktrees/a1/.claude")" = ../../.claude
check "AGENTS.md links to the workspace one"  test "$(readlink "$WT_HOME/worktrees/a1/AGENTS.md")" = ../../AGENTS.md
check_fails "refuses an existing name"        "$WT" new a1 x y
check "links husky's init to husky-init.sh"   test "$(readlink "$XDG_CONFIG_HOME/husky/init.sh")" = "$(cd "$here/.." && pwd)/husky-init.sh"
rm "$XDG_CONFIG_HOME/husky/init.sh" && echo mine > "$XDG_CONFIG_HOME/husky/init.sh"
check "leaves your own husky init alone"      bash -c "'$WT' new h1 bh1 fh1 && grep -qx mine '$XDG_CONFIG_HOME/husky/init.sh'"

# an existing branch is checked out, not recreated
git -C "$WT_REPOS/backend" branch existing-be
check "new reuses an existing branch"         "$WT" new a2 existing-be feat/fe-a2

# a branch that exists only on origin must be tracked, not recreated empty off origin/dev
git -C "$be_repo" branch remote-only
git -C "$be_repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "only on origin"
git -C "$be_repo" branch -f remote-only HEAD
git -C "$be_repo" push -q origin remote-only
git -C "$be_repo" reset -q --hard HEAD~1
git -C "$be_repo" branch -D remote-only >/dev/null
git -C "$be_repo" fetch -q origin
check "new tracks a remote-only branch"       "$WT" new a4 remote-only feat/fe-a4
check "remote-only branch has an upstream"    test "$(git -C "$WT_HOME/worktrees/a4/backend" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)" = origin/remote-only
check "remote-only branch is at origin's tip" test "$(git -C "$WT_HOME/worktrees/a4/backend" rev-parse HEAD 2>/dev/null)" = "$(git -C "$be_repo" rev-parse origin/remote-only)"

# rollback: dev is checked out in the main frontend repo, so the second add fails
check_fails "new fails when fe branch is busy" "$WT" new a3 feat/be-a3 dev
check "failed new leaves no folder"           test ! -e "$WT_HOME/worktrees/a3"
check_fails "failed new leaves no be worktree" worktree_listed backend a3

# ls
check "ls lists a worktree"                   bash -c "'$WT' ls | grep -q '^a1'"

# down
echo dirty > "$WT_HOME/worktrees/a1/frontend/dirty.txt"
check_fails "down refuses a dirty worktree"   "$WT" down a1
check "refused down keeps the be worktree"    test -d "$WT_HOME/worktrees/a1/backend"
check "refused down keeps the fe worktree"    test -f "$WT_HOME/worktrees/a1/frontend/dirty.txt"
rm "$WT_HOME/worktrees/a1/frontend/dirty.txt"

# git status never lists ignored files, but worktree remove deletes them
be=$WT_HOME/worktrees/a1/backend
printf 'appsettings.local.json\nbin/\nobj/\n.yarn/install-state.gz\nsecrets/token\n' > "$be/.gitignore"
git -C "$be" -c user.email=t@t -c user.name=t add .gitignore
git -C "$be" -c user.email=t@t -c user.name=t commit -q -m ignore
echo secret > "$be/appsettings.local.json"
mkdir -p "$be/obj" && echo junk > "$be/obj/build.tmp"
check_fails "down refuses ignored local files" "$WT" down a1
check "refused down keeps the local file"      test -f "$be/appsettings.local.json"
check "the refusal names the file"             bash -c "'$WT' down a1 2>&1 | grep -q appsettings.local.json"
mv "$be/appsettings.local.json" "$tmp/saved.json"
# a folder holding only ignored files is listed as 'dir/', so its contents must still be checked
mkdir -p "$be/secrets" && echo secret > "$be/secrets/token"
check_fails "down refuses a folded ignored folder" "$WT" down a1
check "the refusal names the file inside it"   bash -c "'$WT' down a1 2>&1 | grep -q secrets/token"
rm -r "$be/secrets"
mkdir -p "$be/.yarn" && echo state > "$be/.yarn/install-state.gz"
check "build output alone does not block down" "$WT" down a1
check "down removes a clean worktree"          test ! -d "$be"

# --force deletes them on request
be2=$WT_HOME/worktrees/a2/backend
printf 'appsettings.local.json\n' > "$be2/.gitignore"
git -C "$be2" -c user.email=t@t -c user.name=t add .gitignore
git -C "$be2" -c user.email=t@t -c user.name=t commit -q -m ignore
echo secret > "$be2/appsettings.local.json"
check_fails "down refuses a2's local file"     "$WT" down a2
check "--force removes it anyway"              "$WT" down a2 --force
check "forced down leaves no folder"           test ! -e "$WT_HOME/worktrees/a2"

# name validation applies to every command, not just new
check_fails "down rejects a traversing name"   "$WT" down ../..
check_fails "start rejects a traversing name"  "$WT" start ../..

check "down leaves no folder"                 test ! -e "$WT_HOME/worktrees/a1"
check_fails "down leaves no be worktree"      worktree_listed backend a1
check_fails "down leaves no fe worktree"      worktree_listed frontend a1
check "down keeps the branch"                 git -C "$WT_REPOS/backend" show-ref --verify --quiet refs/heads/feat/be-a1
check_fails "down of an unknown name fails"   "$WT" down nope

finish
