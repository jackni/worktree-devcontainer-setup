# The image every worktree container is built from: a desktop, Chromium and the browser MCP bridge.
# Nothing project- or agent-specific lives here. wt passes the profile's base image, user and setup
# (WT_IMAGE_SETUP) and every agent's install command (agents/*.sh AGENT_INSTALL) as build args.
# The base must be a Debian/Ubuntu release that both KasmVNC and Playwright ship for (e.g. noble,
# jammy, bookworm); the KasmVNC package is picked by the release codename.
ARG BASE_IMAGE=mcr.microsoft.com/devcontainers/base:noble
FROM ${BASE_IMAGE}

ARG USERNAME=vscode
ARG NODE_MAJOR=24
ARG KASMVNC_VERSION=1.5.0
ARG PLAYWRIGHT_VERSION=1.63.0
ARG CHROME_DEVTOOLS_MCP_VERSION=1.10.1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      xfce4 xfce4-terminal dbus-x11 socat netcat-openbsd curl ca-certificates git sudo iproute2 procps \
 && rm -rf /var/lib/apt/lists/*

# devcontainers images ship the user; a plain distro image gets one, with the passwordless sudo that
# wt-start needs to hand Docker-created volume mount points to it.
RUN if ! id "$USERNAME" >/dev/null 2>&1; then \
      useradd -m -s /bin/bash "$USERNAME" \
      && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
      && chmod 440 "/etc/sudoers.d/$USERNAME"; \
    fi

RUN . /etc/os-release \
 && curl -fsSL -o /tmp/kasmvnc.deb \
      "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_${VERSION_CODENAME}_${KASMVNC_VERSION}_$(dpkg --print-architecture).deb" \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/kasmvnc.deb \
 && rm -rf /tmp/kasmvnc.deb /var/lib/apt/lists/* \
 && adduser "$USERNAME" ssl-cert

# KasmVNC#373: an uncaught getType() rejection ("Clipboard data has changed") shows the fatal error
# overlay on Chrome. Abandon that one clipboard sync instead. On 1.5.0 a miss fails the build (the
# code moved); other versions only warn.
RUN f=$(ls /usr/share/kasmvnc/www/assets/ui-*.js) \
 && if grep -q 'let l=await e\[a\].getType(c);' "$f"; then \
      sed -i 's/let l=await e\[a\].getType(c);/let l;try{l=await e[a].getType(c)}catch{return}/' "$f"; \
    elif [ "$KASMVNC_VERSION" = 1.5.0 ]; then echo "KasmVNC 1.5.0 clipboard code moved" >&2; exit 1; \
    else echo "warning: KasmVNC clipboard patch does not apply to $KASMVNC_VERSION" >&2; fi

# Node runs chrome-devtools-mcp, and most agent CLIs install through npm. A base image's own Node is kept.
RUN if ! command -v node >/dev/null; then \
      curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
      && DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs \
      && rm -rf /var/lib/apt/lists/*; \
    fi \
 && if command -v corepack >/dev/null; then corepack enable; fi \
 && npm install -g "chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION}"
# Each new container would otherwise ask before fetching a repo's pinned package manager.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# Playwright's Chromium: noble's apt chromium is a snap stub that cannot run in a container.
RUN npx -y "playwright@${PLAYWRIGHT_VERSION}" install --with-deps chromium \
 && rm -rf /var/lib/apt/lists/* \
 && chmod -R a+rX "$PLAYWRIGHT_BROWSERS_PATH" \
 && ln -sf "$(find "$PLAYWRIGHT_BROWSERS_PATH" -type f -name chrome -path '*/chromium-*' | head -1)" /usr/local/bin/wt-chromium

# glibc sorts ::1 before 127.0.0.1 here (macOS does not), so a dev server binds ::1 while a client
# dials 127.0.0.1 and times out. Prefer IPv4 for every process, as on the host.
RUN echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

# Host-owned bind mounts trip git's dubious-ownership check; this box is local-only.
RUN git config --system --add safe.directory '*'

# The engine and the profile are bind-mounted at run time (see wt's generated devcontainer.json),
# so editing wt-start, a hook or a profile script needs no rebuild. Profile bin/ files must be executable.
RUN ln -sf /opt/wt/engine/wt-start /usr/local/bin/wt-start
ENV PATH=/opt/wt/profile/bin:$PATH

# Last, so changing them rebuilds only these layers: the profile's setup, then the agents' installs.
ARG IMAGE_SETUP=""
RUN if [ -n "$IMAGE_SETUP" ]; then bash -euo pipefail -c "$IMAGE_SETUP"; fi
ARG AGENT_SETUP=""
RUN if [ -n "$AGENT_SETUP" ]; then bash -euo pipefail -c "$AGENT_SETUP"; fi
