# Worktree Devcontainers

A dev container per git worktree, each with its own desktop and Chromium at
`http://wt-<name>.localhost`, so several coding agents (Claude Code, Codex, Gemini) or people can
work on the same repos in parallel without sharing packages, ports or a browser.

This plugin is one skill, `wt`. Ask Claude something like "set up wt so I can run two agents on web
and api in parallel", and the skill:

1. Agrees with you on a workspace folder for the engine and your worktrees.
2. Installs the wt engine there as a git clone of this plugin's GitHub repository, at the tag that
   matches the plugin's version.
3. Checks the host: git, Docker, the devcontainer CLI, and a free port for the desktops.
4. Drafts a profile from your repos and shows it to you before the first build.
5. Runs `wt up`, `wt start`, `wt exec` and `wt down` for you.

## Install

In Claude Code:

```bash
/plugin install worktree-devcontainers --marketplace jackni/worktree-devcontainer-setup
```

## Requirements

Claude Code or Cursor on macOS, Linux, or Windows through WSL 2, with Docker, the devcontainer CLI
and git 2.31 or later. The plugin does nothing on claude.ai or in Cowork, which have no Docker.

## What it downloads and runs

Claude Code and Cursor ask before each command unless you let them run commands on their own.

- **The skill** downloads the engine from github.com/jackni/worktree-devcontainer-setup with git,
  and runs its host check, which only reads versions, Docker's status and whether a port is free.
- **The engine** runs git in your repos, writes `worktrees/<name>/` in the workspace, and creates
  Docker networks, volumes and containers, including one Traefik container on `127.0.0.1`.
- **Building the image** downloads the base image's OS packages, then KasmVNC, Node.js 24,
  Playwright's Chromium, chrome-devtools-mcp and the coding agents you choose, each of those at a
  pinned version. Traefik's image is pulled at a pinned version too.
- **Nothing is sent anywhere** by the plugin or the engine, and there is no telemetry. The agents
  you start talk to their own providers.

The container isolates each task's environment, not your machine: it is not a sandbox for code you
wouldn't run on the host. The engine's README explains what code in a container can reach.

## More

- How it works, with an architecture diagram: [docs/overview.md](https://github.com/jackni/worktree-devcontainer-setup/blob/main/docs/overview.md)
- Every command and setting: [README](https://github.com/jackni/worktree-devcontainer-setup#readme)
- License: GPL-3.0-only
