# Sourced by husky (.husky/_/h) before every git hook; wt links ~/.config/husky/init.sh to this file.
# A wt worktree's packages exist only in its container, so a hook started on the host runs there.
# Other checkouts, the container itself, installed packages and HUSKY=0 fall through to husky as usual.
# Usage, keeping hooks fast and skipping them: "Git hooks from the host" in README.md.
wt_hook_in_container() {
  [ "${HUSKY-}" = 0 ] && return 0
  [ -f /.dockerenv ] && return 0
  [ -n "$(ls -A node_modules 2>/dev/null)" ] && return 0
  # wt marks each worktree folder with .devcontainer/wt.meta; look for one above this repo.
  wt_root=$PWD
  while [ ! -f "$wt_root/.devcontainer/wt.meta" ]; do
    [ "$wt_root" = / ] && return 0
    wt_root=$(dirname "$wt_root")
  done
  wt_name=$(sed -n 's/^WT_NAME=//p' "$wt_root/.devcontainer/wt.meta")
  wt_container=$(sed -n 's/^WT_CONTAINER=//p' "$wt_root/.devcontainer/wt.meta")
  # The image's default user is root; run as wt's user so files the hook writes stay theirs. A
  # wt.meta from before WT_USER was recorded leaves it out until the next wt start or sync.
  wt_user=$(sed -n 's/^WT_USER=//p' "$wt_root/.devcontainer/wt.meta")
  if [ "$(docker inspect -f '{{.State.Running}}' "$wt_container" 2>/dev/null)" != true ]; then
    echo "husky - $(basename "$0") needs $wt_container for its packages; start it: wt start $wt_name" >&2
    exit 1
  fi
  # git's own variables (GIT_INDEX_FILE during a commit) name paths the container mounts at the same place.
  wt_git_vars=$(env | sed -n 's/^\(GIT_[A-Za-z_]*\)=.*/-e \1/p' | tr '\n' ' ')
  echo "husky - running $(basename "$0") in $wt_container" >&2
  # shellcheck disable=SC2086
  docker exec -i ${wt_user:+-u "$wt_user"} $wt_git_vars -w "$PWD" "$wt_container" sh "$0" "$@"
  exit $?
}
wt_hook_in_container "$@"
