# Getting started

From a fresh copy of this repo to coding in a worktree's dev container from VS Code or Cursor. Your
project's languages, packages and tools are installed only in the containers, never on your machine.

The examples use a project repo called `myapp`. Replace it with yours.

## 1. Install the prerequisites

| | macOS | Linux | Windows |
| --- | --- | --- | --- |
| Shell | Terminal | Terminal | A WSL 2 distro (e.g. Ubuntu). Run every command in this guide inside it. |
| Docker | Docker Desktop | Docker Engine (your user in the `docker` group) or Docker Desktop | Docker Desktop, with WSL integration on for your distro |
| Node.js, for the devcontainer CLI | any recent version | any recent version | any recent version, installed inside the distro |
| Editor | VS Code or Cursor | VS Code or Cursor | VS Code with the WSL extension; Cursor (see [Cursor](#cursor)) |

Then, in that shell:

```bash
npm i -g @devcontainers/cli
```

And in your editor, the dev containers extension:

- **VS Code:** Dev Containers (`ms-vscode-remote.remote-containers`).
- **Cursor:** Anysphere's Dev Containers (`anysphere.remote-containers`). Microsoft's does not run in Cursor.

**Windows:** keep every folder in this guide in the WSL file system (`~/...`), never under `/mnt/c`.
Paths under `/mnt/c` are slow to mount and are not valid inside the container.

## 2. Lay out a workspace

`wt` expects this repo and your project's main checkout side by side in one workspace folder. It
creates `worktrees/` there.

```text
~/work/myapp-ws/                 workspace (WT_HOME)
  worktree-devcontainers/        this repo
  myapp/                         your project's main checkout
  worktrees/                     made by wt: one folder per worktree
```

```bash
mkdir -p ~/work/myapp-ws && cd ~/work/myapp-ws
git clone <this repo's URL> worktree-devcontainers
git clone <myapp's URL> myapp        # or keep an existing checkout; see WT_REPOS below
```

A checkout that already lives elsewhere, e.g. `~/code/myapp`, can stay there: set `WT_REPOS=~/code`
in the profile (step 4).

## 3. Put `wt` on your PATH

Add the engine folder to `PATH` in your shell's startup file (`~/.zshrc`, `~/.bashrc`):

```bash
export PATH="$HOME/work/myapp-ws/worktree-devcontainers:$PATH"
```

An alias works too. A symlink to `wt` in another folder does not: `wt` finds the rest of the engine
next to itself.

## 4. Make a profile for your project

```bash
cd ~/work/myapp-ws/worktree-devcontainers
cp -r profiles/example profiles/myapp
ln -sfn profiles/myapp profile
```

Edit `profiles/myapp/wt.conf`. Every setting is documented there; these are the usual ones:

| Setting | What to put |
| --- | --- |
| `WT_REPO_LIST` | `"myapp"`: the checkout's folder name. Several repos: `"web api"`. |
| `WT_REPOS` | Only when the checkouts are not in the workspace folder, e.g. `~/code`. |
| `WT_IMAGE_SETUP` | Your stack's tools. The image has Node.js 24; Python, .NET, Go and the rest go here, e.g. `'apt-get update && apt-get install -y python3-venv'`. |
| `WT_CACHE_DIRS` | Package folders, e.g. `"myapp/node_modules"`: kept on a fast Docker volume instead of the shared folder, which is slow on macOS and Windows. Only the container sees them, so run agents and the editor there (steps 6 and 7). |
| `WT_AGENTS` | AI agents to install in the image, e.g. `"claude"`. See `agents/README.md`. |
| `WT_SHARED_PORTS` | Ports of services already running on your machine (e.g. `"5432 6379"`), reached as `localhost` in the container. |

## 5. Create your first worktree

```bash
wt up feat-login feature/login
```

- Creates `worktrees/feat-login/` with a git worktree of `myapp` on branch `feature/login` (new
  branches start at the remote's default branch).
- Builds the image and starts the container. The first build takes several minutes; later ones reuse it.
- Ends by printing the desktop's address and how to open the folder in your editor.

## 6. Open it in your editor

1. Open the folder `~/work/myapp-ws/worktrees/feat-login`: that folder, not the workspace folder
   and not `myapp/` inside it. On Windows, open it from the WSL shell with `code .` so VS Code
   connects through WSL.
2. Choose "Reopen in Container" from the prompt or the command palette. The editor joins the
   container `wt up` started.
3. In the editor's terminal, now inside the container, check that you are not root, then install
   your project's packages once:

   ```bash
   whoami                        # vscode
   cd myapp && npm install       # or pip, dotnet restore, ...
   ```

4. Open the app in the worktree's desktop at `http://wt-feat-login.localhost`. It has its own
   Chromium, the same one agents drive.

### Cursor

The same steps, with Anysphere's extension. Not tested with `wt`. If "Reopen in Container" fails with
"container name already in use", use "Attach to Running Container", pick `wt-feat-login`, and open
`worktrees/feat-login` in it. On Windows, Cursor needs Anysphere's own Remote WSL extension too.

## 7. Day to day

| To | Do |
| --- | --- |
| Start a parallel task | `wt up fix-bug fix/bug`, then open `worktrees/fix-bug` in a second editor window. Each task has its own container, packages and desktop. |
| Run an agent | `wt exec feat-login claude`, or the editor's terminal |
| Get a shell without the editor | `wt exec feat-login` |
| Resume after closing the editor | `wt start feat-login` (closing the editor stops the container) |
| Apply a profile change | `wt start feat-login` |
| See your worktrees | `wt ls` |
| Finish a task | commit and push, then `wt down feat-login` |

Keep the main checkout for reading code and pulling, and do new work in worktrees.

## If something goes wrong

| Symptom | Fix |
| --- | --- |
| `no profile at ...` | Step 4: link `profile` or set `WT_PROFILE=myapp`. |
| `devcontainer CLI missing` | `npm i -g @devcontainers/cli` in the same shell you run `wt` from. |
| Port 80 is already in use | `export WT_HTTP_PORT=8080`, then open `http://wt-<name>.localhost:8080`. |
| The browser cannot resolve `wt-<name>.localhost` | Use Chrome, Edge or Firefox, which resolve every `*.localhost` name to your machine. |
| A git hook fails when you commit outside the container | See "Git hooks from the host" in the README. |
| macOS, Windows: the app cannot reach a service running natively on your machine (not in Docker) | Put `WT_INFRA_HOST=host.docker.internal` in `worktrees/<name>/wt.env`, then `wt start <name>`. |
| Linux: the app cannot reach a service running natively on your machine | The container reaches the host at the Docker network's gateway, so the service must listen there too, not only on `127.0.0.1`. `host.docker.internal` does not exist on Docker Engine. |

The [README](README.md) covers every command, agents, infra modes, `wt down` and the tests.
