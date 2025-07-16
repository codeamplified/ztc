# Zero Touch Cluster - Docker Environment
# This container includes all tools needed for ZTC cluster management
# Reduces user dependencies from 8-10 tools to just Docker

FROM ubuntu:22.04

# Metadata
LABEL maintainer="Zero Touch Cluster Project"
LABEL description="Complete ZTC environment with all dependencies"
LABEL version="1.0.0"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install system dependencies and core tools
RUN apt-get update && apt-get install -y \
    # Core system tools
    curl \
    wget \
    git \
    ssh-client \
    openssh-client \
    ca-certificates \
    gnupg \
    lsb-release \
    # Build tools
    make \
    gcc \
    python3 \
    python3-pip \
    python3-venv \
    # Go for TUI application
    golang-go \
    # Network tools
    dnsutils \
    net-tools \
    iputils-ping \
    # File processing
    jq \
    unzip \
    tar \
    gzip \
    # Permission management
    sudo \
    # Clean up
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install yq (YAML processor)
RUN YQ_VERSION="v4.35.2" \
    && curl -Lo /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq

# Install kubectl
RUN KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt) \
    && curl -Lo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl

# Install Helm
RUN HELM_VERSION="v3.13.3" \
    && curl -Lo helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf helm.tar.gz \
    && mv linux-amd64/helm /usr/local/bin/ \
    && chmod +x /usr/local/bin/helm \
    && rm -rf helm.tar.gz linux-amd64

# Install Ansible and required collections
RUN pip3 install --no-cache-dir \
    ansible>=9.0.0 \
    ansible-core>=2.16.0 \
    kubernetes>=28.0.0 \
    PyYAML>=6.0.0 \
    Jinja2>=3.1.0 \
    cryptography>=41.0.0

# Install Ansible collections required by ZTC
RUN ansible-galaxy collection install \
    kubernetes.core \
    community.general \
    ansible.posix

# Install kubeseal (for Sealed Secrets)
RUN KUBESEAL_VERSION="v0.24.5" \
    && curl -Lo kubeseal.tar.gz "https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_VERSION}/kubeseal-0.24.5-linux-amd64.tar.gz" \
    && tar -xzf kubeseal.tar.gz \
    && mv kubeseal /usr/local/bin/ \
    && chmod +x /usr/local/bin/kubeseal \
    && rm -f kubeseal.tar.gz

# Create non-root user for better security
RUN groupadd -r ztc && useradd -r -g ztc -u 1000 ztc \
    && mkdir -p /home/ztc/.ssh \
    && chown -R ztc:ztc /home/ztc \
    && chmod 700 /home/ztc/.ssh \
    && echo "ztc ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Create workspace directory
RUN mkdir -p /workspace && chown ztc:ztc /workspace

# Copy TUI application source
COPY --chown=ztc:ztc tui/ /home/ztc/tui/

# Build TUI application
RUN cd /home/ztc/tui && \
    go mod tidy && \
    go mod download && \
    go build -o /usr/local/bin/tui-wizard ./main.go && \
    chmod +x /home/ztc/tui/wrapper.sh && \
    cp /home/ztc/tui/wrapper.sh /usr/local/bin/

# Switch to non-root user
USER ztc

# Set working directory
WORKDIR /workspace

# Set default environment variables
ENV ANSIBLE_HOST_KEY_CHECKING=false
ENV ANSIBLE_STDOUT_CALLBACK=yaml
ENV ANSIBLE_CALLBACKS_ENABLED=timer,profile_tasks
ENV KUBECONFIG=/home/ztc/.kube/config

# Health check to verify tools are working
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ansible --version && kubectl version --client && helm version --short && yq --version

# Default command - use wrapper to handle both TUI and make commands
ENTRYPOINT ["/usr/local/bin/wrapper.sh"]
CMD ["tui-wizard"]