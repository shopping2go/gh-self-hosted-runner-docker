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
- GitHub **Personal Access Token** (PAT) with `repo` and `workflow` scopes ([see instructions below](#how-to-get-a-personal-access-token))
- Linux host recommended (for Docker socket access)
- More info: [GitHub documentation for self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners)

---

## ⚙️ Environment Variables

All configuration is done via environment variables, which can be set in `.env` files, via `docker-compose`, or directly with `docker run`.

### Supported Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `RUNNER_SCOPE` | String | No | `repos` | Runner scope: `repos` or `orgs` |
| `REPO_URL` | String | Yes | - | GitHub repository or organization URL |
| `ACCESS_TOKEN` | String | Yes | - | GitHub PAT with `repo` and `workflow` scopes ([see below](#how-to-get-a-personal-access-token)) |
| `RUNNER_NAME` | String | No | Container hostname | Custom runner name |
| `LABELS` | String | No | `self-hosted,linux,x64,docker` | Comma-separated labels for workflow targeting |
| `DOCKER_GID` | Integer | No | `999` | Host Docker group ID ([see below](#getting-docker-group-id)) |
| `RUNNER_ARCH` | String | No | `x64` | Runner architecture (`x64` or `arm64`) |
| `ENABLE_DIND` | Boolean | No | `false` | Enable Docker-in-Docker mode |

### Configuration Methods

#### Using `.env` files (Recommended)

```env
RUNNER_SCOPE=repos  # or "orgs" for organization-level
REPO_URL=https://github.com/ORGANIZATION/REPO
ACCESS_TOKEN=ghp_your_token_here
RUNNER_NAME=my-runner
LABELS=docker,linux
DOCKER_GID=999
RUNNER_ARCH=x64  # Optional: auto-detected, specify for arm64
ENABLE_DIND=false  # Set to true for Docker-in-Docker mode
```

```bash
docker-compose --env-file .env-repo up -d
```

#### Using docker-compose with inline variables

```bash
ENABLE_DIND=true docker-compose --env-file .env-repo up -d
```

#### Using docker run directly

```bash
docker run -d -e RUNNER_SCOPE=repos -e REPO_URL=https://github.com/owner/repo \
  -e ACCESS_TOKEN=ghp_xxx -e RUNNER_NAME=my-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/shopping2go/gh-self-hosted-runner-docker:latest
```

### 🔑 How to Get a Personal Access Token

Create a [Personal Access Token](https://github.com/settings/tokens) with `repo` and `workflow` scopes. See: [GitHub documentation](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token)

### 🐳 Getting Docker Group ID

```bash
getent group docker | cut -d: -f3  # Output: 999
```

### Docker-in-Docker Mode

Set `ENABLE_DIND=true` to run a separate Docker daemon inside the container (requires privileged mode). Default is `false` (uses host Docker socket).

---

## 🚀 Quick Start

### 1. Configure your environment

Choose and configure one of the methods described in the [Environment Variables](#environment-variables) section above.

### 2. Build & start the runner

```bash
# For repository runner
docker-compose --env-file .env-repo up -d

# For organization runner
docker-compose --env-file .env-org up -d
```

### 3. Verify Runner Registration

After startup, the runner should be visible in GitHub:
- **Repository:** `Settings` → `Actions` → `Runners`
- **Organization:** `Settings` → `Actions` → `Runners`

The runner should be displayed as "Idle" or "Active".

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
