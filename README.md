# wt: a devcontainer per worktree

One container per worktree, each with its own desktop and Chromium at `http://wt-<name>.localhost`,
for any set of repos and any coding agent. A person clicks through the app in the worktree's
Chromium; an agent edits code in the worktree and drives the same Chromium over MCP.

## Why

Coding agents are fast enough that the limit is how many tasks run at once. Running several
agents on one codebase, or an agent beside you, breaks down quickly, and git worktrees alone fix
only the first problem:

| Problem | How wt solves it |
| --- | --- |
| Two agents in one checkout overwrite each other's edits | Each task gets a git worktree of every repo, on its own branch |
| Tasks fight over `node_modules` or `.venv`, and one branch's upgrade breaks another's install | Each task's packages live in its own container, on its own volume |
| Every dev server wants `:3000` | Each container has its own ports, so every task can use `:3000` |
| Agents need a browser to check their work, and sharing yours mixes logins and tabs | Each task has its own desktop and Chromium, which agents drive over MCP and you watch at `http://wt-<name>.localhost` |
| A dev container per task, across several repos, caches and agents, is slow to write by hand | `wt up <name> <branch>` generates and starts it from one profile |
| Every project's tools pile up on your machine | Languages, packages and tools live only in the containers |

Afterwards, `wt down <name>` removes it all. It refuses when that would lose work, such as
uncommitted changes or `.env` files that exist nowhere else.

The container isolates the environment, not your machine: it is not a sandbox for code you
wouldn't run on the host (see [What the container isolates](#what-the-container-isolates)).

How it works, with an architecture diagram and the design decisions: [docs/overview.md](docs/overview.md).

## Layout

```text
<workspace>/                  WT_HOME: the folder holding this one
  <this folder>/              the engine: wt, wt-start, Dockerfile, compose.yaml, husky-init.sh,
                              GETTING-STARTED.md (start here)
    agents/<agent>.sh         one file per coding agent (claude, codex, gemini, or yours)
    profiles/<name>/wt.conf   one per setup: repos, image, ports, caches, agents
    profile -> profiles/...   the default profile (or set WT_PROFILE)
  <repo>/ ...                 main checkouts, one per name in the profile's WT_REPO_LIST
  worktrees/<name>/           made by `wt new`
    .devcontainer/            generated: devcontainer.json + wt.meta
    <repo>/ ...               one git worktree per repo
    wt.env                    WT_INFRA=shared|isolated
    CLAUDE.md -> ../../...    links to the workspace's agent files
```

The engine knows no project and no agent. Everything that varies lives in a **profile**:

- `profiles/example/wt.conf` documents every setting.
- A fuller profile adds `post-start.d/` hooks, a `bin/` folder and an `isolated.sh` for per-worktree
  databases; the `example` profile lists those files.

## Setting up a new workspace

New here? [GETTING-STARTED.md](GETTING-STARTED.md) walks through it on macOS, Linux and Windows (WSL 2),
up to coding in VS Code or Cursor. In short:

1. Prerequisites on the host:
   - Docker running.
   - `npm i -g @devcontainers/cli`.
   - To work in an IDE: VS Code with the Dev Containers extension, or another editor that supports
     dev containers (see [Working in a worktree](#working-in-a-worktree)).
   - Nothing else: the repos' languages, packages and tools live only in the containers.
2. Copy `profiles/example` to `profiles/<yours>`.
3. Set `WT_REPO_LIST` to your checkouts' folder names, and `WT_AGENTS` to the agents you use. Change
   whatever else differs (base image, caches, ports).
4. Select the profile with `ln -sfn profiles/<yours> profile`, or `export WT_PROFILE=<yours>`. A
   profile may also live outside the engine: `WT_PROFILE=/path/to/folder`.
5. Run `wt up <name> <branch>`, then open the worktree in your IDE (below) and its desktop at
   `http://wt-<name>.localhost`.

### Or let Claude Code set it up

This repo is also a Claude Code plugin. Its `wt` skill checks the host, copies the engine into your
workspace, drafts a profile from your repos, and runs `wt` for you:

```bash
claude plugin install worktree-devcontainers --marketplace jackni/worktree-devcontainer-setup
```

Then ask Claude, for example, "set up wt so I can run two agents on web and api in parallel". The
skill keeps the profile at `<workspace>/wt-profile/`, outside the engine, so `claude plugin update`
and a re-install of the engine never touch it.

The plugin works in Claude Code on a machine with Docker. It does nothing on claude.ai or in Cowork,
which have no Docker.

### What the plugin and wt run, write and download

Claude shows each command before it runs it. Nothing is sent anywhere by the plugin or by `wt`
itself, and there is no telemetry.

- **The skill's scripts:**
  - `check-prereqs.sh` only reads: the git and Docker versions, `docker info`, and whether
    `127.0.0.1:80` is free.
  - `install-engine.sh` copies the engine's files into the workspace folder you choose.
- **`wt` on your machine:**
  - **Git:** runs git in your repos (`worktree add`, and `fetch` from their remote for a new
    branch).
  - **Files:** writes `worktrees/<name>/` in the workspace. When a repo uses husky, it also links
    `~/.config/husky/init.sh` to `husky-init.sh`; your own `init.sh` is never replaced.
  - **Docker:** creates Docker networks, volumes and containers.
  - **Traefik:** runs one `traefik:v3.7` container on `127.0.0.1:80`, which reads the Docker socket,
    read-only, to find the desktops.
- **The image build downloads:**
  - the base image (`mcr.microsoft.com/devcontainers/base:noble` unless the profile sets another);
  - the distribution's packages;
  - KasmVNC from its GitHub releases;
  - Node.js from NodeSource, only when the base image has none;
  - `chrome-devtools-mcp` and Playwright's Chromium, at pinned versions;
  - each agent CLI the profile lists, at a pinned version;
  - whatever the profile's `WT_IMAGE_SETUP` installs.
- **In the containers:**
  - `chrome-devtools-mcp` runs with `--no-usage-statistics`.
  - The agents you start talk to their own providers, as they do on your machine.
  - API keys you pass with `'KEY=${localEnv:KEY}'` in the profile's `WT_ENV` go into the
    container's environment and nowhere else.

## Commands

```bash
wt up    <name> <branch>... [--infra shared|isolated]   # new + start
wt new   <name> <branch>... [--infra shared|isolated]   # git worktrees and config only
wt start <name> [--fresh]      # (re)start the container; --fresh: wipe isolated infra data
wt sync  <name>                # regenerate .devcontainer/ after editing the profile
wt exec  <name> [cmd...]       # run cmd (default bash) in the worktree folder, in its container
wt mcp   <name>                # the stdio command for the browser MCP server
wt ls
wt down  <name> [--force]      # refuses if there is anything to lose
```

`<branch>...` takes one branch per repo, in `WT_REPO_LIST` order, or one branch for all of them.

- A branch that exists only on the remote is checked out tracking it.
- A new branch starts at `WT_BASE`, or by default at the remote's default branch.
- Names may hold lowercase letters, digits and `-`.

### Why the devcontainer.json is generated

The number of repos, cache folders and agents varies by profile, and devcontainer.json has no loops.
So `wt new`, `wt start` and `wt sync` write each worktree's `.devcontainer/devcontainer.json` from the
profile. Edit the profile, never that file.

- **What `wt start` does after a profile change:** it notices the change and recreates the container.
  Volumes survive: caches, agent logins, isolated data.
- **VS Code alone:** run `wt sync <name>`, then "Rebuild Container".
- **Migrating:** worktrees made by the earlier version have a `.devcontainer` symlink to the
  engine. The next `wt start` or `wt sync` replaces it, and `wt start` also recreates the container.

The engine and the profile are bind-mounted read-only at `/opt/wt/engine` and `/opt/wt/profile`. So
`wt-start`, the profile's hooks and its `bin/` take effect on the next start without a rebuild.
Only the base image, `WT_IMAGE_SETUP` and the agents' installs are baked into the image; changing
those rebuilds only the last layers.

## Working in a worktree

Each worktree is a dev container. Open `worktrees/<name>/` in the container, never the workspace
folder or a single repo: the container's workspace is the worktree folder, holding every repo.

`wt start` creates the container with the devcontainer CLI for that folder, so an IDE opening the same
folder joins the same container. The IDE, `wt exec`, the agents and the desktop all share one set of
files, packages and tools.

### VS Code

1. Install the Dev Containers extension (`ms-vscode-remote.remote-containers`).
2. Run `wt up <name> <branch>`, or `wt start <name>` for an existing worktree.
3. Open the folder in the container, either way:
   - `code worktrees/<name>`, then "Reopen in Container" from the prompt or the command palette;
   - in one step, from the workspace folder:

     ```bash
     code --folder-uri "vscode-remote://dev-container+$(printf %s "$PWD/worktrees/<name>" | od -An -tx1 | tr -d ' \n')$PWD/worktrees/<name>"
     ```

     macOS and Linux only; under WSL, use "Reopen in Container".

In the container window:

- **Terminal:** a shell in the container as `WT_USER`, with the agents on the `PATH`.
- **Extensions:** language extensions install into the container and use its packages, so
  IntelliSense, debugging and tests work with nothing on the host.
- **Source Control:** lists every repo in the worktree. Commits made here run their hooks in the
  container. For commits from the host, see [Git hooks from the host](#git-hooks-from-the-host).
- **Ports:** not forwarded to the host (see [Shared vs isolated infra](#shared-vs-isolated-infra)).
  Browse the app from the desktop's Chromium at `http://wt-<name>.localhost`.
- **After editing the profile:** `wt start <name>`, or `wt sync <name>` then "Rebuild Container".

### Closing the IDE stops the container

This is on purpose (`"shutdownAction": "stopContainer"`): a worktree you are not working in does not
hold memory and CPU. Stopping is not removing.

| Action | Container | Desktop and agents in it | Files, branches, volumes |
| --- | --- | --- | --- |
| Close the last VS Code window on the worktree | stopped | stopped | kept |
| `wt start <name>` | started again | started again (agents: rerun them) | kept |
| `wt down <name>` | removed | removed | worktree folder and its cache volumes removed; branches and agent logins kept (see [What `wt down` refuses](#what-wt-down-refuses)) |

- **An agent still working in the container:** leave the window open until it finishes. Closing it
  stops the agent too, even one started from a host terminal with `wt exec`.
- **The desktop tab:** goes blank once the container stops; `wt start <name>` brings it back.
- **Done with the worktree:** commit and push, then `wt down <name>`.

### Other editors

- **Cursor:** install Anysphere's Dev Containers extension (`anysphere.remote-containers`);
  Microsoft's does not run in Cursor. Then `wt start <name>`, open `worktrees/<name>` and choose
  "Reopen in Container". Not tested with `wt`. If it fails with "container name already in use", it
  did not recognise the container `wt start` made: use "Attach to Running Container" and pick
  `wt-<name>`, then open the worktree folder.
- **Windsurf and other VS Code forks:** the same steps with the fork's own dev containers extension.
  Not tested with `wt`.
- **JetBrains IDEs:** open `worktrees/<name>/.devcontainer/devcontainer.json` through the IDE's Dev
  Containers support. Not tested with `wt`.
- **Any editor without dev container support:** edit `worktrees/<name>/` on the host; the folder is
  bind-mounted, so the container sees every change. Run, test and commit with `wt exec <name>`.
  Language tooling on the host will not find packages that live only in the container.

## Agents

`WT_AGENTS="claude codex"` in the profile. Each agent is a small file in `agents/` (or the profile's
own `agents/`) giving four things:

- its install command;
- a home folder, kept on a volume (`wt-<agent>`) that every worktree shares, so you log in once;
- environment variables;
- workspace files to link into each worktree, e.g. `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`. Missing
  files are skipped.

See `agents/README.md` to add one.

```bash
wt exec <name> claude
wt exec <name> codex --sandbox danger-full-access   # see agents/codex.sh for why
wt exec <name> gemini
```

### Letting an agent drive the browser

Every worktree's Chromium listens on CDP `:9222` inside its container, and the image ships
`chrome-devtools-mcp`. `wt mcp <name>` prints the stdio command, which goes into any MCP client:

```bash
claude mcp add wt-<name>-browser -- $(wt mcp <name>)            # Claude Code
codex mcp add wt-<name>-browser -- $(wt mcp <name>)             # Codex
# others: { "command": "docker", "args": [ ...the words wt mcp prints, after "docker"... ] }
```

Watch it in the desktop tab, and don't click while the agent is driving. To recover a stuck browser:

```bash
wt exec <name> bash -c 'pkill -f -- "[-]-remote-debugging-port=9222"; rm -rf ~/.wt-chromium/Default/Sessions; wt-start'
```

## What the container isolates

A worktree's container keeps its packages, tools, ports and processes apart from the host's and from
the other worktrees'. It sees only the worktree folder, the main checkouts' `.git`, the workspace's
agent files and its volumes, not the rest of your home folder or your SSH keys.

It is not a security boundary. Run in it only agents and code you would run on the host. Whatever
runs in it, an agent or a package's install script, can get code run on the host by writing to:

- **The main checkouts' `.git`:** its `config` (e.g. `core.fsmonitor`, `core.sshCommand`, aliases)
  and `hooks/` run with the next git command on the host, in the main checkout or any worktree,
  including the ones `wt new` and `wt down` run.
- **The worktree folder:** husky's generated `.husky/_/` files run on every host commit, and
  `.devcontainer/devcontainer.json`'s `initializeCommand` runs on the host when VS Code opens or
  rebuilds the container.
- **The workspace's agent files:** e.g. hooks added to `.claude/settings.json` run in Claude Code on
  the host.

Worktrees are not isolated from each other either:

- **Agent logins:** every container can read every agent login on the shared `wt-<agent>` volumes.
- **Desktops:** every desktop on the profile's network is reachable from the other containers.
- **The network:** a container reaches the internet and services on the host.

## Routing

One Traefik container per machine (`wt-traefik`, on its own `wt-gateway` network) serves every
profile:

- **Networks:** `wt start` attaches Traefik to the profile's `WT_NETWORK`, and each worktree's
  labels tell Traefik which network to reach it on.
- **Host port:** loopback `:80`. Set `WT_HTTP_PORT` in your environment to use another one; it is
  machine-wide, not per profile.
- **Origin check:** KasmVNC has no login and only checks that an Origin header exists. The router
  rule therefore refuses websocket upgrades from any page but the desktop's own.

## Shared vs isolated infra

| Mode | What `localhost` reaches in the container |
| --- | --- |
| `shared` (the default) | Every `WT_SHARED_PORTS` and `WT_ISOLATABLE_PORTS` port is forwarded to the host, so every worktree shares one set of services. |
| `isolated` | The profile's `isolated.sh` starts this worktree's own services on `WT_ISOLATABLE_PORTS`. `WT_SHARED_PORTS` stay forwarded. |

- **Choosing a mode:** pass `--infra isolated` to `wt new`, or edit `WT_INFRA` in
  `worktrees/<name>/wt.env` and run `wt start <name>`. That start tears down whichever side is
  going away.
- **Infra on the host itself:** if it runs natively on the host rather than in Docker, put
  `WT_INFRA_HOST=host.docker.internal` in `wt.env`.

VS Code auto-forwarding is off. Auto-forwarding a socat infra port binds it on the host's loopback,
where `host.docker.internal` lands first, so every connection loops back into the container until it
runs out of memory. Forward a port by hand only for a quick API call, never an infra port.

## What `wt down` refuses

- **Uncommitted changes** in any repo.
- **Ignored files written by hand.** `git status` never shows these, but `git worktree remove`
  deletes them anyway: local settings and `.env` files with credentials.
  - Build output does not block a removal: `node_modules`, `bin`, `obj`, `dist`, `target`, `.venv`,
    and the profile's `WT_DISPOSABLE_DIRS` and `WT_DISPOSABLE_FILES`.
  - `--force` deletes the listed files with the worktree.

## Git hooks from the host

[Husky](https://typicode.github.io/husky/) keeps a repo's git hooks in a committed `.husky/` folder:
`pre-commit` runs the linter, `commit-msg` checks the message, `pre-push` runs tests. The tools those
hooks call live in `node_modules`, which may exist only in the container. Git, though, also runs on
the host: in your terminal, in VS Code's Source Control, or in an agent running outside the container.

When a repo has a `.husky/` folder, `wt` links `~/.config/husky/init.sh` to `husky-init.sh`, so a hook
started on the host runs in the worktree's container instead.

- **How it works:** husky sources that file before every hook, and it runs the hook in the worktree's
  container, from the same folder, where `node_modules` lives.
- **Commit and push from the host:** plain `git commit` and `git push` work, and the push itself
  stays on the host with your SSH key.
- **When it steps aside:** in the container itself, in a checkout with its own `node_modules`, and
  in any checkout `wt` did not make. Husky then runs the hook as usual.
- **First run:** run `npm install` once in the container:
  `wt exec <name> bash -c 'cd <repo> && npm install'`. Husky's `prepare` script creates `.husky/_`;
  until it exists, git skips the hooks without a word.
- **Container stopped:** the hook fails and prints the `wt start` command to run.
- **Your own `init.sh`:** it is left alone, with a warning.

### Keeping hooks fast

Every commit and push waits for its hooks, and an agent pays for that wait on each one. Suggested
split for a repo's hooks:

| Hook | Keep it to | Example |
| --- | --- | --- |
| `pre-commit` | seconds: lint and format the staged files only | `npx lint-staged` |
| `commit-msg` | the message check | `npx --no -- commitlint --edit "$1"` |
| `pre-push` | at most a quick check, e.g. type-checking | `npx tsc --noEmit` |
| CI | the full test suite and builds | |

`wt` adds well under a second per hook, so a slow hook is slow because of what it runs.

### Skipping hooks

| Scope | How |
| --- | --- |
| One command | `git commit --no-verify`, `git push --no-verify`, or `HUSKY=0 git push` |
| Your shell on the host | `export HUSKY=0` in your shell profile |
| Every worktree of a profile | `HUSKY=0` in the profile's `WT_ENV`, then `wt start <name>`. Hooks run in the container even when git starts on the host, so this skips both. |

Skipped hooks are no longer a guardrail, so leave the checks to CI. An agent blocked by a failing
hook sees the error and can fix the code. That only works when the hook can run.

### Other hook tools

Only husky is covered. Hooks from Python's `pre-commit` framework, lefthook, simple-git-hooks or
plain `.git/hooks` scripts run wherever git runs. Started on the host, they need their tools on the
host. For those repos, commit from the container: `wt exec <name> git -C <repo> commit ...`. Their
`pre-push` hooks still run on the host when you push from there, since the SSH key stays there.

## Tests

| Test | Needs |
| --- | --- |
| `test/generic_test.sh` | No Docker except for `down`. Covers one repo, three repos, a made-up agent, custom naming, migration and bad profiles. |
| `test/wt_git_test.sh` | Throwaway repos with a two-repo, two-agent profile: branches, rollback, what `down` refuses. |
| `test/husky_init_test.sh` | A fake `docker`. |
| `test/install_engine_test.sh` | Nothing. The plugin skill's engine install: fresh, upgrade, refusals. |
| `test/image_test.sh` | Builds `WT_PROFILE`'s image (default: `example`). |
| `test/container_test.sh` | Runs `wt-start` with a throwaway profile. |
| `test/e2e_test.sh` | A real `wt up`/`start`/`down` through the devcontainer CLI and Traefik, with a one-repo profile and a made-up agent. Uses host port 80. |
| `profiles/<name>/test/` | Each profile's own end-to-end checks. |

## License

GPL-3.0. See [LICENSE](LICENSE).
