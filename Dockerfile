# Use Ubuntu 22.04 as the base image
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install essential system packages and dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    git \
    jq \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3 \
    python3-pip \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI for Docker-in-Docker support
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Create a dedicated user for the GitHub Actions runner
RUN useradd -m -s /bin/bash runner \
    && usermod -aG sudo runner \
    && echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up the workspace directory structure and permissions
RUN mkdir -p /github/workspace && \
    chown -R runner:runner /github /github/workspace

# Install Maven for Java-based workflows
RUN apt-get update && \
    apt-get install -y maven && \
    rm -rf /var/lib/apt/lists/*

# Download and install the latest GitHub Actions runner (as root)
# Note: GitHub uses 'x64' for Intel/AMD 64-bit architecture, not 'amd64'
ARG RUNNER_ARCH=x64
RUN RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//') \
    && echo "Installing GitHub Actions Runner version: $RUNNER_VERSION for arch: $RUNNER_ARCH" \
    && curl -o actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz -C /github/workspace \
    && rm actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && cd /github/workspace && ./bin/installdependencies.sh

# Switch to the runner user and set the working directory
USER runner
WORKDIR /github/workspace

# Copy the startup script and set execute permissions
COPY --chown=runner:runner start.sh /github/workspace/start.sh
RUN chmod +x /github/workspace/start.sh

# Set the default command to launch the runner
CMD ["/github/workspace/start.sh"]
