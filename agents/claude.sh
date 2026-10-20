# Claude Code. Log in once in any worktree (`/login`); the login lives on the shared volume.
# Run it from the worktree folder (`wt exec <name> claude`) so the linked CLAUDE.md and .claude apply.
# The trailing --version fails the build if npm silently skipped a platform binary (an optional dependency).
AGENT_INSTALL="npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION:-2.1.283} && claude --version"
AGENT_HOME=.claude
# CLAUDE_CONFIG_DIR also pulls .claude.json onto the volume. The version is pinned: no auto-update.
AGENT_ENV=("CLAUDE_CONFIG_DIR=$WT_USER_HOME/.claude" DISABLE_AUTOUPDATER=1)
AGENT_FILES="CLAUDE.md .claude"
