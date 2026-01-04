# 🧩 GitHub Actions Docker Runner

[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-green.svg)](https://github.com/features/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Pull Requests welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/shopping2go/gh-actions-docker-runner/pulls)
[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)

> **Lightweight, self-hosted GitHub Actions runner in Docker** – works for both **repositories** and **organizations**, with automatic token refresh, Docker-in-Docker, and easy `.env` setup.  
> Ideal for scalable CI/CD setups or on-premise runner environments.

---

## 🚀 Features

- ✅ Run self-hosted GitHub Actions runners in Docker
- 🔁 Automatic token refresh (no manual re-registration)
- 🏗️ Supports both **repo** and **org** scopes
- 🐳 Full Docker-in-Docker compatibility
- ⚙️ Easy configuration via `.env` files
- 🧹 Automatic cleanup of old runners
- 🔒 Security-hardened configuration
- 🛠️ GitHub CLI (`gh`) pre-installed for advanced GitHub operations

---

## ⚠️ Security Warning

**WICHTIG:** Self-hosted Runner mit Docker-Socket-Zugriff sollten **NUR** für **private, vertrauenswürdige Repositories** verwendet werden!

- ❌ **NICHT** für public Repositories verwenden
- ❌ **NICHT** für Repositories mit externen Contributoren ohne Review-Prozess
- ✅ **NUR** für private, interne Projekte mit Code-Review-Prozess


---

## 📦 Requirements

- Docker ≥ **20.10**
- Docker Compose ≥ **1.29**
- GitHub **Personal Access Token** (PAT) with `repo` and `workflow` scopes ([see instructions below](#-how-to-get-a-personal-access-token))
- Linux host recommended (for Docker socket access)
- More info: [GitHub documentation for self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners)

---

## ⚙️ Environment Variables

All configuration is done via environment variables, which can be set in `.env` files, via `docker-compose`, or directly with `docker run`.

### Supported Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `RUNNER_SCOPE` | String | Yes | `repos` | Runner scope: `repos` for repository-level or `orgs` for organization-level |
| `REPO_URL` | String | Yes | - | Full GitHub URL to repository (e.g., `https://github.com/owner/repo`) or organization (e.g., `https://github.com/owner`) |
| `ACCESS_TOKEN` | String | Yes | - | GitHub Personal Access Token with `repo` and `workflow` scopes ([see instructions below](#-how-to-get-a-personal-access-token)) |
| `RUNNER_NAME` | String | No | Container hostname | Custom name for this runner instance (visible in GitHub Settings → Actions → Runners) |
| `LABELS` | String | No | `self-hosted,linux,x64,docker` | Comma-separated list of labels for workflow targeting (e.g., `docker,linux,custom`) |
| `DOCKER_GID` | Integer | No | `999` | Docker group ID from the host system. Must match host's docker group for Docker socket access ([see instructions below](#getting-docker-group-id)) |
| `RUNNER_ARCH` | String | No | `x64` | Architecture for the GitHub Actions runner binary (e.g., `x64`, `arm64`) |
| `ENABLE_DIND` | Boolean | No | `false` | Enable Docker-in-Docker mode. Set to `true` to start Docker daemon inside the container instead of using host Docker socket |

### Configuration Methods

You can configure these variables using any of the following methods:

#### Method 1: Using `.env` files (Recommended)

Create a `.env-repo` file for repository runners:

```env
RUNNER_SCOPE=repos
REPO_URL=https://github.com/ORGANIZATION/REPO
ACCESS_TOKEN=ghp_your_token_here
RUNNER_NAME=repo-runner
LABELS=docker,repo,linux
DOCKER_GID=999
ENABLE_DIND=false
```

Or a `.env-org` file for organization runners:

```env
RUNNER_SCOPE=orgs
REPO_URL=https://github.com/ORGANIZATION
ACCESS_TOKEN=ghp_your_token_here
RUNNER_NAME=org-runner
LABELS=docker,org,linux
DOCKER_GID=999
ENABLE_DIND=false
```

Then start with:
```bash
# For repository runner
docker-compose --env-file .env-repo up -d

# For organization runner
docker-compose --env-file .env-org up -d
```

#### Method 2: Environment variables with docker-compose

```bash
ENABLE_DIND=true RUNNER_NAME=custom-runner docker-compose --env-file .env-repo up -d
```

#### Method 3: Direct docker run

```bash
docker run -d \
  -e RUNNER_SCOPE=repos \
  -e REPO_URL=https://github.com/owner/repo \
  -e ACCESS_TOKEN=ghp_your_token_here \
  -e RUNNER_NAME=my-runner \
  -e LABELS=docker,linux \
  -e DOCKER_GID=999 \
  -e ENABLE_DIND=false \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/shopping2go/gh-self-hosted-runner-docker:latest
```

### 🔑 How to Get a Personal Access Token

To create a Personal Access Token (PAT) for GitHub Actions:

1. Go to [GitHub Settings – Developer settings – Personal access tokens](https://github.com/settings/tokens)
2. Click **Generate new token** (Classic) or **Generate new token (Fine-grained)**
3. Give your token a name and select an expiration date
4. Select at least the following permissions:
   - **repo** (for repository access)
   - **workflow** (for Actions workflows)
5. Click **Generate token** and copy the token (it will only be shown once!)
6. Use this token as the `ACCESS_TOKEN` value in your configuration

For more details, see: [Creating a personal access token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token)

### Getting Docker Group ID

To get your host system's Docker group ID (needed for `DOCKER_GID`):

```bash
# On Linux/Mac:
getent group docker | cut -d: -f3

# Example output: 999
```

Use this value as `DOCKER_GID` in your configuration.

### Docker-in-Docker Mode (`ENABLE_DIND`)

The runner supports two modes for Docker access:

1. **Host Docker Socket (default, `ENABLE_DIND=false`)**: Mounts the host's Docker socket into the container. Faster and simpler, but shares Docker daemon with host.

2. **Docker-in-Docker (`ENABLE_DIND=true`)**: Runs a separate Docker daemon inside the container. More isolated but requires privileged mode.

When `ENABLE_DIND=true`:
- The container automatically starts its own Docker daemon
- Container requires `privileged: true` mode (already configured in `docker-compose.yml`)
- Workflows can run Docker commands without accessing the host's Docker daemon
- Useful for building images, running containers, or using Docker Compose in workflows

Example workflow to verify Docker availability:

```yaml
jobs:
  my-docker-job:
    runs-on: [self-hosted, docker]
    steps:
      - name: Check Docker status
        run: docker info
      
      - name: Run Docker commands
        run: docker run --rm hello-world
```

### Common Configuration Examples

#### Example 1: Repository runner with host Docker
```env
RUNNER_SCOPE=repos
REPO_URL=https://github.com/mycompany/myproject
ACCESS_TOKEN=ghp_xxxxxxxxxxxxx
RUNNER_NAME=project-ci-runner
LABELS=docker,linux,ci
DOCKER_GID=999
ENABLE_DIND=false
```

#### Example 2: Organization runner with Docker-in-Docker
```env
RUNNER_SCOPE=orgs
REPO_URL=https://github.com/mycompany
ACCESS_TOKEN=ghp_xxxxxxxxxxxxx
RUNNER_NAME=org-dind-runner
LABELS=docker,dind,isolated
ENABLE_DIND=true
```

#### Example 3: Multiple runners for different teams
```env
# Team A - .env-team-a
RUNNER_SCOPE=repos
REPO_URL=https://github.com/mycompany/team-a-repo
ACCESS_TOKEN=ghp_team_a_token
RUNNER_NAME=team-a-runner
LABELS=docker,team-a,linux
```

```env
# Team B - .env-team-b
RUNNER_SCOPE=repos
REPO_URL=https://github.com/mycompany/team-b-repo
ACCESS_TOKEN=ghp_team_b_token
RUNNER_NAME=team-b-runner
LABELS=docker,team-b,linux
```

---

## 🚀 Quick Start

### 1. Configure your environment

Choose and configure one of the methods described in the [Environment Variables](#%EF%B8%8F-environment-variables) section above.

### 2. Build & start the runner

```bash
# For repository runner
docker-compose --env-file .env-repo up -d

# For organization runner
docker-compose --env-file .env-org up -d
```

### 3. Verify Runner Registration

Nach dem Start sollte der Runner in GitHub sichtbar sein:
- **Repository:** `Settings` → `Actions` → `Runners`
- **Organization:** `Settings` → `Actions` → `Runners`

Der Runner sollte als "Idle" oder "Active" angezeigt werden.

---

## 🧠 How It Works

- Fetches a fresh GitHub registration token on startup
- Configures and registers the runner using `config.sh`
- Starts both the runner and a background token refresher
- Automatically removes stale runners on restart
- Supports Docker socket access for Docker-based workflows

---

## 🛠️ Pre-installed Tools

The Docker image comes with several essential tools pre-installed:

- **GitHub CLI (`gh`)** - Direct GitHub API interaction and automation
  - Version: Latest stable release
  - Documentation: https://cli.github.com/
  - Example usage in workflows:
    ```yaml
    - name: Create GitHub Issue
      run: |
        gh issue create --title "Build Failed" --body "Details here"
      env:
        GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    ```

- **Docker CLI** - Docker-in-Docker support for containerized builds
- **Git** - Version control operations
- **jq** - JSON processing for API responses
- **Maven** - Java build automation
- **Python 3** - Python runtime and pip package manager

---

## 🗂️ File Overview

```text
.
├── .github/
│   └── workflows/
│       └── docker-ghcr.yml   # CI/CD workflow for building and pushing Docker images
├── Dockerfile          # Image definition
├── docker-compose.yml  # Container setup
├── start.sh            # Runner bootstrap & token refresh logic
├── .env-org            # Environment file for organization runner
├── .env-repo           # Environment file for repository runner
└── LICENSE
```

---

## 🧩 Example Use Cases

- Run self-hosted runners on your private infrastructure
- Integrate Docker builds directly in CI pipelines
- Manage separate runners per team or repo
- Create scalable, disposable runner pools

---

## 🪪 License

Licensed under the MIT License – see [LICENSE](LICENSE) for details.

---

## Haftungsausschluss \- Nutzung auf eigene Gefahr

Die Nutzung dieses Projekts erfolgt vollständig auf eigene Gefahr. Die Maintainer übernehmen keine Gewähr für die Funktionsfähigkeit, Sicherheit oder Eignung des Codes für einen bestimmten Zweck. Insbesondere wird keine Haftung übernommen für direkte oder indirekte Schäden, Datenverlust, entgangene Gewinne oder sonstige Folgeschäden, die aus der Nutzung oder Unmöglichkeit der Nutzung dieses Projekts entstehen.

Der Nutzer ist allein verantwortlich für die Implementierung zusätzlicher Sicherheitsmaßnahmen, Backups und Prüfprozesse vor dem produktiven Einsatz. Es obliegt dem Anwender, dieses Projekt in einer geeigneten, abgesicherten Umgebung zu betreiben (z.\,B. isolierte Netzwerke, eingeschränkte Zugriffsrechte, least-privilege PATs).

Der Nutzer stellt die Maintainer von allen Ansprüchen Dritter frei, die aus der Nutzung dieses Projekts resultieren, soweit gesetzlich zulässig.

Hinweis: Dies stellt keine Rechtsberatung dar. Für eine rechtsverbindliche Haftungsbegrenzung oder rechtliche Absicherung sollte ein qualifizierter Rechtsbeistand konsultiert werden.

---

## 🔍 Keywords

GitHub Actions, self-hosted runner, Docker, CI/CD, automation, repository runner, organization runner, token refresh, workflow runner, Docker-in-Docker, DevOps

<div> <sub>💡 Maintained with ❤️ by <a href="https://www.shopping2go.de">shopping2go GmbH</a></sub> </div>
