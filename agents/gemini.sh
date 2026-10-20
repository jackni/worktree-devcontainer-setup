# Google Gemini CLI. Log in once in any worktree, or pass a key from your shell:
# add 'GEMINI_API_KEY=${localEnv:GEMINI_API_KEY}' to the profile's WT_ENV.
# Pin GEMINI_CLI_VERSION (wt.conf or the environment) for reproducible images.
AGENT_INSTALL="npm install -g @google/gemini-cli@${GEMINI_CLI_VERSION:-latest} && gemini --version"
AGENT_HOME=.gemini
AGENT_ENV=()
AGENT_FILES="GEMINI.md"
