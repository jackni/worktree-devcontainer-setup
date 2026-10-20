# Google Gemini CLI. Log in once in any worktree (`wt exec <name> gemini`, then pick a sign-in
# method); the login lives on the shared volume.
# The version is pinned; set GEMINI_CLI_VERSION (wt.conf or the environment) to change it.
AGENT_INSTALL="npm install -g @google/gemini-cli@${GEMINI_CLI_VERSION:-0.64.0} && gemini --version"
AGENT_HOME=.gemini
AGENT_ENV=()
AGENT_FILES="GEMINI.md"
