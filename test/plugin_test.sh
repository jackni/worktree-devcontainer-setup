#!/usr/bin/env bash
# The plugin folder against the rules Anthropic's directory applies to a publisher that isn't
# Verified: only Markdown, JSON and PNG files, nothing starting with #!, text in UTF-8 without NUL
# bytes, no package-manager configuration. Also checks that the manifests and the tag the skill
# clones name one version, and that the engine files the skill points at exist. No Docker.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
root=$(cd "$here/.." && pwd)
plugin=$root/plugin
skill=$plugin/skills/wt/SKILL.md

files=$(git -C "$root" ls-files plugin)
check "the plugin folder has files"            test -n "$files"

allowed_names() { printf '%s\n' "$files" | grep -vE '\.(md|json|png)$' | grep -q . && return 1; return 0; }
check "only .md, .json and .png files"         allowed_names
no_shebang() { local f; for f in $files; do [ "$(head -c2 "$root/$f")" != '#!' ] || return 1; done; }
check "nothing starts with #!"                 no_shebang
clean_text() {
  local f
  for f in $(printf '%s\n' "$files" | grep -E '\.(md|json)$'); do
    iconv -f UTF-8 -t UTF-8 "$root/$f" >/dev/null 2>&1 || return 1
    LC_ALL=C tr -d '\000' <"$root/$f" | cmp -s - "$root/$f" || return 1
  done
}
check "text is UTF-8 without NUL bytes"        clean_text
real_png() {
  local f
  for f in $(printf '%s\n' "$files" | grep -E '\.png$'); do
    [ "$(file -b --mime-type "$root/$f")" = image/png ] || return 1
  done
}
check "each .png is a PNG"                     real_png
check_fails "no package-manager configuration" bash -c "printf '%s\n' '$files' | grep -qE '(^|/)(package(-lock)?\.json|npm-shrinkwrap\.json|\.npmrc|\.yarnrc(\.yml)?|pnpm-workspace\.yaml|bunfig\.toml|uv\.toml|pip\.conf)$'"
check_fails "the skill has no !\` lines"        grep -q '!`' "$skill"

version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$plugin/.claude-plugin/plugin.json")
check "the Claude manifest has a version"      test -n "$version"
check "the Cursor manifest has the same one"   test "$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$plugin/.cursor-plugin/plugin.json")" = "$version"
check "the skill clones that version's tag"    grep -q "git clone --branch v$version " "$skill"
check_fails "  and names no other tag"         bash -c "grep -oE '\bv[0-9]+\.[0-9]+\.[0-9]+\b' '$skill' | grep -vx 'v$version' | grep -q ."
check "the marketplace lists ./plugin"         grep -q '"source": "./plugin"' "$root/.claude-plugin/marketplace.json"

readme_words() { [ "$(awk '/^```/{f=!f; next} !f' "$plugin/README.md" | wc -w)" -ge 40 ]; }
check "the plugin README has 40+ words"        readme_words

engine_files() { local f; for f in wt wt-start Dockerfile check-prereqs.sh README.md GETTING-STARTED.md profiles/example/wt.conf; do [ -f "$root/$f" ] || return 1; done; }
check "the engine files the skill names exist" engine_files
check "the profile link is ignored in a clone" git -C "$root" check-ignore -q profile

finish
