---
name: wt
description: Set up and run wt, which gives every git worktree its own dev container with a desktop and Chromium at http://wt-<name>.localhost, so several coding agents (Claude Code, Codex, Gemini) or people can work on the same repos in parallel without sharing packages, ports or a browser. Use this whenever the user wants parallel or isolated workspaces per branch or task, a devcontainer per worktree, to run more than one agent on one codebase at once, to let an agent drive a browser against their app in a container, or mentions wt, `wt up`, `wt new`, `wt start`, `wt down`, wt.conf, a wt profile, or a wt error, even if they don't name wt.
---

# wt: a dev container per git worktree

`wt` is a bash engine that makes `worktrees/<name>/` in a workspace, with one git worktree per repo,
and runs one dev container for it. Each container has its own packages, desktop, and Chromium that
an agent drives over MCP. Docker, the devcontainer CLI and git are all it needs on the host; the
project's languages and tools live only in the containers.

This plugin carries the engine at its root, written `<plugin>` below. In Claude Code that is
`${CLAUDE_PLUGIN_ROOT}`; in Cursor and other agents it is `../..` from this skill's folder (the
folder containing this `SKILL.md`), the folder holding both `wt` and `Dockerfile`. Use its absolute
path in commands. Its docs are the reference for anything this file doesn't cover; read the
relevant part when you need it rather than guessing:

- `<plugin>/profiles/example/wt.conf`: every profile setting, with its default
- `<plugin>/README.md`: commands, agents, infra modes, what `wt down` refuses, git hooks
- `<plugin>/GETTING-STARTED.md`: per-OS setup, and an "If something goes wrong" table

## The layout wt expects

```text
<workspace>/                    WT_HOME
  worktree-devcontainers/       the engine (installed by this skill)
    profile -> ../wt-profile    which profile wt uses
  wt-profile/wt.conf            the user's profile: repos, image, caches, ports, agents
  <repo>/ ...                   main checkouts (or elsewhere, via WT_REPOS)
  worktrees/<name>/             made by wt
```

`wt` finds everything relative to its own folder, which is why the engine is copied into the
workspace rather than run from this plugin: the plugin's folder changes on every update, and the
containers and the husky hook link point at the engine's path.

## Setting up a workspace

Work through these in order, and tell the user what you found at each step. Ask before creating
folders outside the current project.

1. **Find or agree on the workspace.** It is the folder that will hold the engine and
   `worktrees/`. If the user's repos sit together in a folder that holds nothing else, that folder
   works. Otherwise suggest a new one such as `~/work/<project>-ws` and point `WT_REPOS` at the
   folder holding the checkouts. If a workspace already has an engine (a folder holding both `wt`
   and `Dockerfile`), reuse it.

2. **Check the host:**

   ```bash
   bash "<plugin>/skills/wt/scripts/check-prereqs.sh" <workspace>
   ```

   Every `FAIL` blocks wt; tell the user how to fix each one (the script says how) and stop until
   they have. A `warn` about port 80 means exporting `WT_HTTP_PORT` before every `wt` command.

3. **Install the engine:**

   ```bash
   bash "<plugin>/skills/wt/scripts/install-engine.sh" <workspace>
   ```

   Re-running it later upgrades the engine and leaves profiles and worktrees alone. Pass on the
   `PATH` line it prints, so the user can run `wt` in their own terminal.

4. **Write the profile** at `<workspace>/wt-profile/wt.conf`, then link it:
   `ln -sfn ../wt-profile <workspace>/worktree-devcontainers/profile`. Keeping it outside the engine
   means engine upgrades never touch it. Start from the example's settings and fill in what the
   repos tell you:

   | In the repos | Setting |
   | --- | --- |
   | The checkout folder names | `WT_REPO_LIST="web api"`, in the order the user will give branches |
   | `package.json` | `WT_CACHE_DIRS="web/node_modules"`: installs stay on a fast volume instead of the slow host mount on macOS and Windows. The image has Node 24 and corepack. |
   | `pyproject.toml`, `requirements*.txt` | `WT_IMAGE_SETUP='apt-get update && apt-get install -y python3-venv python3-pip'`, and `<repo>/.venv` in `WT_CACHE_DIRS` |
   | `*.csproj`, `go.mod`, other stacks | A matching `mcr.microsoft.com/devcontainers/<stack>:<version>-noble` as `WT_BASE_IMAGE`, or an install in `WT_IMAGE_SETUP`. The base must be a Debian/Ubuntu release KasmVNC and Playwright ship for. |
   | A compose file or `.env.example` naming local services | Their ports in `WT_SHARED_PORTS="5432 6379"`, so `localhost` in the container reaches them on the host |
   | Which agents the user runs | `WT_AGENTS="claude codex"`; files from `agents/` |
   | A `CLAUDE.md` or `AGENTS.md` the user keeps in the workspace | Nothing: each agent links its workspace files into every worktree |

   Only list folders a tool regenerates in `WT_CACHE_DIRS`. Their contents live in a volume that
   only the container sees, and `wt down` deletes it without checking. Show the user the finished
   `wt.conf` before the first build, because changing the image afterwards means another build.

## Creating and using worktrees

Run wt by its full path (`<workspace>/worktree-devcontainers/wt`) unless it is on `PATH` in your
shell.

```bash
wt up <name> <branch>...     # git worktrees + config, then build and start the container
wt start <name>              # start again, after a reboot or after closing the IDE
wt exec <name> [cmd...]      # run a command in the worktree folder, in its container
wt ls
wt down <name>               # remove the container, its volumes and the worktree folder
```

- **Names** are lowercase letters, digits and `-`, at most 31 characters. Give one branch per repo
  in `WT_REPO_LIST` order, or one branch for all. A branch that exists only on the remote is
  checked out tracking it; a new one starts at the remote's default branch.
- **The first `wt up` builds the image** and takes several minutes. Run it in the background and
  tell the user it is building. Later builds reuse the cache.
- **After editing the profile,** `wt start <name>` notices and recreates the container. Volumes
  (caches, agent logins) survive.
- **Interactive agents** (`wt exec <name> claude`, `codex`, `gemini`) need a terminal, so give the
  user the command to run rather than running it yourself. Non-interactive commands such as tests
  or `npm install` you can run with `wt exec`.
- **The IDE:** open `worktrees/<name>`, not the workspace or a single repo, and choose "Reopen in
  Container". Closing the IDE stops the container; `wt start` brings it back.

### Letting an agent drive the browser

Every container runs its own Chromium with the DevTools protocol on `127.0.0.1:9222`, and the image
ships `chrome-devtools-mcp`. Where the agent runs decides how it connects:

- **Agents inside the containers** (the usual case): register the server once per agent, at user
  scope. The agent's config lives on the volume every worktree shares, and `127.0.0.1:9222` is
  always the container's own Chromium, so one registration serves every worktree:

  ```bash
  wt exec <name> claude mcp add --scope user wt-browser -- chrome-devtools-mcp --browserUrl http://127.0.0.1:9222 --no-usage-statistics
  wt exec <name> codex mcp add wt-browser -- chrome-devtools-mcp --browserUrl http://127.0.0.1:9222 --no-usage-statistics
  ```

- **An agent on the host** reaches one worktree's Chromium through `docker exec`; `wt mcp <name>`
  prints that command. In Claude Code:

  ```bash
  claude mcp add wt-<name>-browser -- $(wt mcp <name>)
  ```

  In Cursor, add a server to `~/.cursor/mcp.json` (or the project's `.cursor/mcp.json`), with
  `docker` as the command and the rest of what `wt mcp <name>` prints as the arguments:

  ```json
  { "mcpServers": { "wt-<name>-browser": {
      "command": "docker",
      "args": ["exec", "-i", "-u", "<user>", "-w", "<home>", "<container>", "chrome-devtools-mcp",
               "--browserUrl", "http://127.0.0.1:9222", "--no-usage-statistics"] } } }
  ```

The user watches either at `http://wt-<name>.localhost`, and shouldn't click while the agent drives.

## Removing a worktree

`wt down` refuses when a repo has uncommitted changes, or ignored files that look hand-written,
such as `.env` files and local settings. `git worktree remove` would delete those, and they often
exist nowhere else. When it refuses, show the user the list it printed and let them choose: commit,
copy the files out, or remove anyway. Only pass `--force` when they say so, because it deletes
those files for good. Branches survive `wt down`; agent logins on the shared volumes survive too.

## Safety: the container is not a sandbox

The container isolates packages, ports and processes, not the host. Code inside it can get code run
on the host through the main checkouts' `.git` (config and hooks), files in the worktree folder, and
the workspace's agent files. The README's "What the container isolates" section explains each.

So treat code running in a worktree as code running on the host. In particular, before starting an
agent with its own sandbox turned off (the README runs Codex as
`codex --sandbox danger-full-access`), tell the user that this gives the agent the same reach as
running it on their machine.

## When something fails

Read `GETTING-STARTED.md`'s "If something goes wrong" table first. The most common causes:

| Symptom | Cause and fix |
| --- | --- |
| `no profile at ...` | The `profile` link is missing, or `WT_PROFILE` names a folder without `wt.conf` |
| Port 80 in use | `export WT_HTTP_PORT=8080`; desktops move to `:8080` |
| `<repo> is not a git checkout` | `WT_REPOS` or `WT_REPO_LIST` doesn't match the folders on disk |
| A git hook fails on a host commit | The container is stopped (`wt start <name>`), or the repo needs a first `npm install` in the container |
| The app can't reach a database on the host | Its port is missing from `WT_SHARED_PORTS`, or the service runs natively: `WT_INFRA_HOST=host.docker.internal` in `worktrees/<name>/wt.env` (macOS, Windows) |

Container logs are in `~/.wt-logs/` inside the container: `wt exec <name> ls ~/.wt-logs`.
