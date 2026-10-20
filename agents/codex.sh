# OpenAI Codex. Log in once: `wt exec <name> codex login --device-auth`.
# Run it as `wt exec <name> codex --sandbox danger-full-access`: its own Linux sandbox (bubblewrap)
# cannot create namespaces in an unprivileged container. The container then isolates the agent's
# environment, not your machine: see "What the container isolates" in README.md.
# Codex reads AGENTS.md only from a repo's root down to where it starts, so start it in the worktree folder.
# The trailing --version fails the build if npm silently skipped the linux binary (an optional
# dependency); that once shipped an image whose codex only printed "Missing optional dependency".
AGENT_INSTALL="npm install -g @openai/codex@${CODEX_VERSION:-0.160.0} && codex --version"
AGENT_HOME=.codex
AGENT_ENV=("CODEX_HOME=$WT_USER_HOME/.codex")
AGENT_FILES="AGENTS.md"
