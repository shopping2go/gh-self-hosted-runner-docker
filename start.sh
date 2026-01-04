#!/bin/bash

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
        echo "Stopping Docker daemon..."
        sudo kill "$DOCKERD_PID" 2>/dev/null || true
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
if [[ "${ENABLE_DIND,,}" == "true" || "${ENABLE_DIND}" == "1" ]]; then
    echo "🐳 Starting Docker daemon (ENABLE_DIND=true)..."
    sudo dockerd &
    DOCKERD_PID=$!
    
    # Wait for Docker daemon to be ready
    echo "Waiting for Docker daemon to be ready..."
    max_attempts=30
    attempt=0
    while ! docker info >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo "ERROR: Docker daemon failed to start after ${max_attempts} seconds"
            exit 1
        fi
        sleep 1
    done
    echo "✅ Docker daemon is running and ready!"
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
