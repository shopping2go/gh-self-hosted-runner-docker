#!/bin/bash

# Global variable for Docker daemon PID (needed for cleanup function)
DOCKERD_PID=""

# --- Print actionable guidance for Docker-in-Docker failures ---
print_dind_troubleshooting() {
    local log_file="$1"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ Docker-in-Docker failed to start"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Check for specific error patterns in the log
    if [[ -n "$log_file" ]] && [[ -f "$log_file" ]]; then
        if sudo grep -q "you must be root\|Permission denied\|operation not permitted" "$log_file" 2>/dev/null; then
            echo ""
            echo "🔍 Detected: Permission/privilege errors"
            echo ""
            echo "The container is not running with sufficient privileges for Docker-in-Docker."
            echo ""
            echo "✅ Solution: Run the container with privileged mode enabled:"
            echo ""
            echo "   docker run --privileged ..."
            echo ""
            echo "   Or in docker-compose.yml:"
            echo "     privileged: true"
            echo ""
        fi
        
        if sudo grep -q "iptables\|NAT chain\|network controller\|bridge" "$log_file" 2>/dev/null; then
            echo ""
            echo "🔍 Detected: Network/IPTables errors"
            echo ""
            echo "Docker cannot set up networking (NAT/iptables) without proper capabilities."
            echo ""
            echo "✅ Solution: Ensure the container has NET_ADMIN capability or privileged mode:"
            echo ""
            echo "   docker run --privileged ..."
            echo "   # OR"
            echo "   docker run --cap-add=NET_ADMIN --cap-add=SYS_ADMIN ..."
            echo ""
        fi
    fi
    
    echo ""
    echo "📚 For more information, see the README.md section on Docker-in-Docker mode."
    echo ""
    echo "💡 Alternative: If you don't need a full Docker daemon, mount the host socket:"
    echo "   Set ENABLE_DIND=false and add: -v /var/run/docker.sock:/var/run/docker.sock:rw"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# --- Validate the RUNNER_SCOPE variable ---
validate_runner_scope() {
    # Default to 'repos' if invalid
    if [[ "$RUNNER_SCOPE" != "repos" && "$RUNNER_SCOPE" != "orgs" ]]; then
        echo "WARNING: RUNNER_SCOPE is not set or invalid ('$RUNNER_SCOPE'). Using 'repos' as default."
        RUNNER_SCOPE="repos"
    else
        echo "RUNNER_SCOPE is set to '$RUNNER_SCOPE'"
    fi

    # Check if REPO_URL matches the expected format for the scope
    REPO_PATH=$(echo "${REPO_URL}" | sed 's|https://github.com/||')
    SLASH_COUNT=$(echo "$REPO_PATH" | awk -F"/" '{print NF-1}')

    if [[ "$RUNNER_SCOPE" == "repos" && "$SLASH_COUNT" -ne 1 ]]; then
        echo "WARNING: RUNNER_SCOPE='repos' but REPO_URL='$REPO_URL' does not match '/org/repo'. Switching to 'orgs'."
        RUNNER_SCOPE="orgs"
    elif [[ "$RUNNER_SCOPE" == "orgs" && "$SLASH_COUNT" -ne 0 ]]; then
        echo "WARNING: RUNNER_SCOPE='orgs' but REPO_URL='$REPO_URL' looks like a repository URL. Switching to 'repos'."
        RUNNER_SCOPE="repos"
    fi
}

# --- Run validation at script start ---
validate_runner_scope

# Obtain a fresh GitHub runner registration token
get_runner_token() {
    echo "Requesting a new runner token from GitHub..."

    if [[ -z "${ACCESS_TOKEN}" ]]; then
        echo "ERROR: ACCESS_TOKEN is missing."
        echo "Please set your Personal Access Token in the ACCESS_TOKEN environment variable."
        echo "Create one at: https://github.com/settings/tokens with 'repo' and 'workflow' scopes."
        exit 1
    fi

    REPO_PATH=$(echo "${REPO_URL}" | sed 's|https://github.com/||')

    RESPONSE=$(curl -s -X POST \
        -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/${RUNNER_SCOPE}/${REPO_PATH}/actions/runners/registration-token")

    RUNNER_TOKEN=$(echo "$RESPONSE" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [[ -n "$RUNNER_TOKEN" ]]; then
        echo "Runner token acquired successfully."
        export RUNNER_TOKEN
        return 0
    else
        echo "Failed to retrieve runner token. Response: $RESPONSE"
        echo "Check your ACCESS_TOKEN and repository permissions."
        exit 1
    fi
}

# Remove any existing runner with the same name from GitHub
remove_runner() {
    local runner_name="${RUNNER_NAME:-$(hostname)}"
    echo "Checking for existing runner named: $runner_name"

    REPO_PATH=$(echo "${REPO_URL}" | sed 's|https://github.com/||')

    RUNNERS_RESPONSE=$(curl -s -H "Authorization: token ${ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/${RUNNER_SCOPE}/${REPO_PATH}/actions/runners")

    RUNNER_ID=$(echo "$RUNNERS_RESPONSE" | sed -n "s/.*\"id\":[[:space:]]*\([0-9]*\),.*\"name\":[[:space:]]*\"$runner_name\".*/\1/p")

    if [[ -z "$RUNNER_ID" ]]; then
        RUNNER_ID=$(echo "$RUNNERS_RESPONSE" | grep -B 5 "\"name\":\"$runner_name\"" | grep -o '"id":[0-9]*' | cut -d':' -f2 | head -1)
    fi

    if [[ -n "$RUNNER_ID" ]]; then
        echo "Existing runner found (ID: $RUNNER_ID). Removing from GitHub..."
        curl -s -X DELETE \
            -H "Authorization: token ${ACCESS_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/${RUNNER_SCOPE}/${REPO_PATH}/actions/runners/$RUNNER_ID" > /dev/null
        echo "Runner removed."
        sleep 2
    else
        echo "No runner with this name found on GitHub."
    fi
}

# Configure the GitHub Actions runner
setup_runner() {
    remove_runner

    echo "Registering runner for: ${REPO_URL}"
    ./config.sh --unattended \
        --url ${REPO_URL} \
        --token ${RUNNER_TOKEN} \
        --name ${RUNNER_NAME:-$(hostname)} \
        --work /github/workspace \
        --labels ${LABELS:-self-hosted,linux,x64,docker} \
        --replace
}

# Background process to refresh the runner token periodically
refresh_token_service() {
    local refresh_interval=3000  # 50 minutes

    while true; do
        sleep $refresh_interval
        echo "$(date): Refreshing runner token..."

        if get_runner_token; then
            echo "$(date): Token refreshed. Restarting runner..."

            local runner_pid=$(pgrep -f "Runner.Listener")
            if [[ -n "$runner_pid" ]]; then
                echo "$(date): Stopping runner process (PID: $runner_pid)"
                kill -TERM "$runner_pid"

                local timeout=30
                while [[ $timeout -gt 0 ]] && kill -0 "$runner_pid" 2>/dev/null; do
                    sleep 1
                    ((timeout--))
                done

                if kill -0 "$runner_pid" 2>/dev/null; then
                    echo "$(date): Forcibly killing runner process."
                    kill -KILL "$runner_pid"
                fi
            fi

            echo "$(date): Reconfiguring runner with new token."
            setup_runner

            echo "$(date): Restarting runner process."
            ./run.sh &
            RUNNER_PID=$!
            echo "$(date): Runner restarted (PID: $RUNNER_PID)"
        else
            echo "$(date): Token refresh failed. Keeping current runner."
        fi
    done
}

# Cleanup function to remove runner registration on exit
cleanup() {
    echo "Performing cleanup before exit..."

    if [[ -n "$REFRESH_PID" ]]; then
        echo "Stopping token refresh background process..."
        kill "$REFRESH_PID" 2>/dev/null || true
    fi

    if [[ -n "$RUNNER_PID" ]]; then
        echo "Stopping runner process..."
        kill "$RUNNER_PID" 2>/dev/null || true
    fi

    if [[ -n "$DOCKERD_PID" ]]; then
        echo "Stopping Docker daemon gracefully..."
        
        # Stop all running containers first for clean shutdown
        if command -v docker >/dev/null 2>&1; then
            echo "Stopping all running containers..."
            docker stop $(docker ps -q) 2>/dev/null || true
        fi
        
        sudo kill -TERM "$DOCKERD_PID" 2>/dev/null || true

        local dockerShutdownTimeout=30
        while [[ $dockerShutdownTimeout -gt 0 ]] && sudo kill -0 "$DOCKERD_PID" 2>/dev/null; do
            sleep 1
            ((dockerShutdownTimeout--))
        done

        if sudo kill -0 "$DOCKERD_PID" 2>/dev/null; then
            echo "Forcibly killing Docker daemon."
            sudo kill -KILL "$DOCKERD_PID" 2>/dev/null || true
        fi
    fi

    echo "Unregistering runner from GitHub..."
    ./config.sh remove --unattended --token ${RUNNER_TOKEN} 2>/dev/null || remove_runner
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Add runner user to docker group if DOCKER_GID is provided
if [[ -n "$DOCKER_GID" ]]; then
    if ! getent group docker >/dev/null; then
        sudo groupadd -g "$DOCKER_GID" docker
    fi
    sudo usermod -aG docker runner
    echo "Runner user added to docker group (GID: $DOCKER_GID)"
else
    echo "DOCKER_GID not set. Skipping docker group setup."
fi

# Start Docker daemon if ENABLE_DIND is set to true
if [[ "${ENABLE_DIND,,}" == "true" ]]; then
    echo "🐳 Starting Docker daemon (ENABLE_DIND=true)..."
    
    # Check for required privileges before attempting to start Docker daemon
    echo "Checking required privileges for Docker-in-Docker..."
    
    MISSING_CAPABILITIES=""
    
    # Check if we can perform privileged operations (test mount propagation capability)
    if ! sudo mount --make-shared / 2>/dev/null; then
        # Try to detect if we're running in privileged mode by checking capabilities
        if [[ -f /proc/self/status ]]; then
            CAP_EFF=$(grep "CapEff:" /proc/self/status 2>/dev/null | awk '{print $2}')
            # Full capabilities for privileged containers is typically 0000003fffffffff (hex)
            # which equals 274877906943 in decimal. Lower values indicate missing capabilities.
            if [[ -n "$CAP_EFF" ]] && [[ "$CAP_EFF" != "0000003fffffffff" ]] && [[ $(printf "%d" "0x$CAP_EFF" 2>/dev/null || echo 0) -lt 274877906943 ]]; then
                MISSING_CAPABILITIES="mount"
            fi
        fi
    fi
    
    # Check if we can access iptables (required for Docker networking)
    if ! sudo iptables -L -n >/dev/null 2>&1; then
        if [[ -n "$MISSING_CAPABILITIES" ]]; then
            MISSING_CAPABILITIES="$MISSING_CAPABILITIES, iptables"
        else
            MISSING_CAPABILITIES="iptables"
        fi
    fi
    
    # If missing critical capabilities, provide actionable error and exit
    if [[ -n "$MISSING_CAPABILITIES" ]]; then
        echo ""
        echo "❌ ERROR: Docker-in-Docker requires privileged mode!"
        echo ""
        echo "Missing capabilities: $MISSING_CAPABILITIES"
        echo ""
        echo "To fix this issue, run the container with one of the following options:"
        echo ""
        echo "  Option 1: Using docker run:"
        echo "    docker run --privileged ..."
        echo ""
        echo "  Option 2: Using docker-compose.yml:"
        echo "    services:"
        echo "      github-runner:"
        echo "        privileged: true"
        echo ""
        echo "  Note: The included docker-compose.yml already sets 'privileged: \${ENABLE_DIND:-false}',"
        echo "        so if ENABLE_DIND=true is set, privileged mode should be enabled automatically."
        echo "        If you're seeing this error, your container may have been started differently."
        echo ""
        echo "⚠️  Security Note: Privileged mode gives the container full access to the host."
        echo "   Only use this with trusted workloads and in isolated environments."
        echo ""
        echo "Alternative: If you don't need Docker-in-Docker, you can mount the host's"
        echo "Docker socket instead by setting ENABLE_DIND=false (or removing it) and"
        echo "adding this volume mount:"
        echo "    -v /var/run/docker.sock:/var/run/docker.sock:rw"
        echo ""
        exit 1
    fi
    
    echo "✅ Required privileges detected"
    
    # Load overlay kernel module if available (required for overlay2 storage driver)
    echo "Checking overlay kernel module..."
    if sudo modprobe overlay 2>/dev/null; then
        echo "✅ Overlay kernel module loaded successfully"
    else
        echo "⚠️  Could not load overlay module (may already be loaded or not available)"
    fi
    
    # Create secure log directory outside the workspace to avoid exposing daemon logs
    DOCKERD_LOG_DIR="/var/log/dockerd"
    sudo mkdir -p "$DOCKERD_LOG_DIR"
    sudo chmod 700 "$DOCKERD_LOG_DIR"
    DOCKERD_LOG="$DOCKERD_LOG_DIR/dockerd.log"
    
    # Use a pidfile so we can capture the actual dockerd PID instead of the sudo PID
    DOCKERD_PIDFILE="/var/run/dockerd.pid"
    sudo rm -f "$DOCKERD_PIDFILE"
    
    # Try to start dockerd with overlay2 first, fallback to vfs if it fails
    STORAGE_DRIVER="overlay2"
    echo "Attempting to start Docker daemon with $STORAGE_DRIVER storage driver..."
    
    # Start dockerd with security-hardening options
    # Wrap the entire command including redirection in sudo bash -c to ensure proper permissions
    sudo bash -c "dockerd --iptables=true --icc=false --storage-driver=$STORAGE_DRIVER --pidfile=\"$DOCKERD_PIDFILE\" >> \"$DOCKERD_LOG\" 2>&1 &"
    
    # Resolve the actual Docker daemon PID from the pidfile
    DOCKERD_PID=""
    for i in {1..30}; do
        DOCKERD_PID=$(sudo cat "$DOCKERD_PIDFILE" 2>/dev/null || true)
        if [[ -n "$DOCKERD_PID" ]]; then
            break
        fi
        sleep 1
    done

    if [[ -z "$DOCKERD_PID" ]]; then
        echo "⚠️  Failed to obtain Docker daemon PID with $STORAGE_DRIVER driver."
        echo "Docker daemon logs:"
        sudo cat "$DOCKERD_LOG" 2>/dev/null || echo "⚠️  Unable to read Docker daemon log file."
        
        # Check if the failure was due to overlay2 not being supported
        if [[ "$STORAGE_DRIVER" == "overlay2" ]] && sudo grep -q "driver not supported\|operation not permitted\|failed to mount overlay\|overlay2: not supported" "$DOCKERD_LOG" 2>/dev/null; then
            echo ""
            echo "🔄 Retrying with vfs storage driver (slower but more compatible)..."
            STORAGE_DRIVER="vfs"
            
            # Clean up log and pidfile for retry
            sudo rm -f "$DOCKERD_PIDFILE"
            sudo bash -c "> \"$DOCKERD_LOG\""
            
            # Retry with vfs storage driver
            sudo bash -c "dockerd --iptables=true --icc=false --storage-driver=$STORAGE_DRIVER --pidfile=\"$DOCKERD_PIDFILE\" >> \"$DOCKERD_LOG\" 2>&1 &"
            
            # Wait for pidfile again
            for i in {1..30}; do
                DOCKERD_PID=$(sudo cat "$DOCKERD_PIDFILE" 2>/dev/null || true)
                if [[ -n "$DOCKERD_PID" ]]; then
                    break
                fi
                sleep 1
            done
            
            if [[ -z "$DOCKERD_PID" ]]; then
                echo "ERROR: Failed to start Docker daemon even with vfs storage driver."
                echo "Docker daemon logs:"
                sudo cat "$DOCKERD_LOG" 2>/dev/null || echo "⚠️  Unable to read Docker daemon log file."
                print_dind_troubleshooting "$DOCKERD_LOG"
                exit 1
            fi
        else
            echo "ERROR: Failed to obtain Docker daemon PID."
            print_dind_troubleshooting "$DOCKERD_LOG"
            exit 1
        fi
    fi
    
    # Wait for Docker daemon to be ready
    echo "Waiting for Docker daemon to be ready..."
    maxAttempts=30
    attempt=0
    while ! docker version --format '{{.Server.Version}}' >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        
        # Check if dockerd process is still running
        if ! sudo kill -0 "$DOCKERD_PID" 2>/dev/null; then
            echo "ERROR: Docker daemon process exited unexpectedly. Check logs:"
            sudo cat "$DOCKERD_LOG" 2>/dev/null || echo "⚠️  Unable to read Docker daemon log file."
            
            # If overlay2 failed, try vfs as fallback (only if not already using vfs)
            if [[ "$STORAGE_DRIVER" == "overlay2" ]] && sudo grep -q "driver not supported\|operation not permitted\|failed to mount overlay\|overlay2: not supported" "$DOCKERD_LOG" 2>/dev/null; then
                echo ""
                echo "🔄 Retrying with vfs storage driver (slower but more compatible)..."
                STORAGE_DRIVER="vfs"
                
                # Clean up for retry
                sudo rm -f "$DOCKERD_PIDFILE"
                sudo bash -c "> \"$DOCKERD_LOG\""
                
                # Retry with vfs storage driver
                sudo bash -c "dockerd --iptables=true --icc=false --storage-driver=$STORAGE_DRIVER --pidfile=\"$DOCKERD_PIDFILE\" >> \"$DOCKERD_LOG\" 2>&1 &"
                
                # Wait for pidfile
                DOCKERD_PID=""
                for i in {1..30}; do
                    DOCKERD_PID=$(sudo cat "$DOCKERD_PIDFILE" 2>/dev/null || true)
                    if [[ -n "$DOCKERD_PID" ]]; then
                        break
                    fi
                    sleep 1
                done
                
                if [[ -z "$DOCKERD_PID" ]]; then
                    echo "ERROR: Failed to start Docker daemon even with vfs storage driver."
                    echo "Docker daemon logs:"
                    sudo cat "$DOCKERD_LOG" 2>/dev/null || echo "⚠️  Unable to read Docker daemon log file."
                    print_dind_troubleshooting "$DOCKERD_LOG"
                    exit 1
                fi
                
                # Reset attempt counter for new daemon start
                attempt=0
                continue
            fi
            
            print_dind_troubleshooting "$DOCKERD_LOG"
            exit 1
        fi
        
        if [[ $attempt -ge $maxAttempts ]]; then
            echo "ERROR: Docker daemon failed to start after ${maxAttempts} seconds"
            echo "Docker daemon logs:"
            sudo cat "$DOCKERD_LOG" 2>/dev/null || echo "⚠️  Unable to read Docker daemon log file."
            print_dind_troubleshooting "$DOCKERD_LOG"
            exit 1
        fi
        sleep 1
    done
    echo "✅ Docker daemon is running and ready with $STORAGE_DRIVER storage driver!"
else
    echo "ℹ️  Docker daemon not started (ENABLE_DIND=${ENABLE_DIND:-false})"
    echo "   Set ENABLE_DIND=true to start the Docker daemon inside the container"
fi

# Get a fresh runner token at container startup
get_runner_token

# Register the runner
setup_runner

# Start the background token refresh process
echo "Launching token refresh background service..."
refresh_token_service &
REFRESH_PID=$!
echo "Token refresh service running (PID: $REFRESH_PID)"

# Start the GitHub Actions runner
echo "Starting GitHub Actions runner process..."
./run.sh &
RUNNER_PID=$!
echo "Runner process started (PID: $RUNNER_PID)"

# Wait for the runner process to finish
wait $RUNNER_PID
