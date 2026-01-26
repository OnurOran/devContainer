FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base tools + deps
RUN apt-get update && apt-get install -y \
    ca-certificates curl iputils-ping gnupg lsb-release \
    sudo git openssh-client \
    iproute2 \
    neovim tmux \
    ripgrep fd-find htop tree unzip jq wget \
    \
    # DinD deps
    iptables uidmap \
    \
    # .NET / general runtime dependencies
    libicu-dev \
    libssl3 \
    zlib1g \
    libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/*

# Docker official repo
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu noble stable" \
  > /etc/apt/sources.list.d/docker.list

# Install Docker Engine (for DinD) + Compose plugin
RUN apt-get update && apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# DinD dockerd config (avoid 172.22 clashes; keep separate from host's 10.200 pool)
RUN mkdir -p /etc/docker \
 && printf '%s\n' \
'{' \
'  "default-address-pools": [' \
'    { "base": "10.210.0.0/16", "size": 24 }' \
'  ]' \
'}' > /etc/docker/daemon.json

# GitHub CLI (gh)
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y gh \
 && rm -rf /var/lib/apt/lists/*

# Fix fd command name
RUN ln -sf /usr/bin/fdfind /usr/local/bin/fd

# User setup
RUN useradd -m -s /bin/bash developer \
 && usermod -aG sudo developer \
 && echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer \
 && chmod 0440 /etc/sudoers.d/developer \
 && groupadd -f docker \
 && usermod -aG docker developer

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
