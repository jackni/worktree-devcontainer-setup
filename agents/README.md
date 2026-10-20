# Agents

List the agents a profile wants in its `wt.conf`: `WT_AGENTS="claude codex"`. Each name is a file
here, or in the profile's own `agents/` folder, which wins. An agent file is bash, sourced by `wt`
with the profile's settings in scope (`$WT_USER_HOME` and the rest), and sets four things:

| Variable | Meaning |
| --- | --- |
| `AGENT_INSTALL` | Shell run as root at image build. `npm`, `pip`, `curl \| sh`: anything the base image can run. Pin a version, and end with `&& <agent> --version`: npm skips a platform binary that fails to download without an error, and the check turns that into a failed build. |
| `AGENT_HOME` | Its state folder, relative to the user's home (`.claude`). Kept on the volume `<prefix><agent>` (`wt-claude`), which every worktree shares, so one login serves all of them. |
| `AGENT_ENV` | Array of `KEY=VALUE` set in the container, e.g. pointing the agent's config at `AGENT_HOME`. |
| `AGENT_FILES` | Workspace files or folders (`$WT_HOME/<file>`) linked into every worktree folder and mounted where the link resolves, e.g. `CLAUDE.md`. Missing ones are skipped. |

Adding one, e.g. aider:

```bash
# agents/aider.sh
AGENT_INSTALL="apt-get update && apt-get install -y python3-pip && pip install --break-system-packages aider-chat"   # pin a version
AGENT_HOME=.aider
AGENT_ENV=()
AGENT_FILES="CONVENTIONS.md"
```

then add `aider` to `WT_AGENTS` and run `wt start <name>`; the image rebuilds only its last layers.
Run any agent with `wt exec <name> <command>`. Keep API keys out of the image and out of files: put
`'OPENAI_API_KEY=${localEnv:OPENAI_API_KEY}'` (single quotes) in the profile's `WT_ENV`, and the key
is read from your shell's environment each time the container is created.

Every agent can drive the worktree's Chromium through MCP: `wt mcp <name>` prints the stdio command.
