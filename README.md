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

---

## 📦 Requirements

- Docker ≥ **20.10**
- Docker Compose ≥ **1.29**
- GitHub **Personal Access Token** (PAT) with `repo` and `workflow` scopes ([see instructions below](#-how-to-get-a-personal-access-token))
- Linux host recommended (for Docker socket access)
- More info: [GitHub documentation for self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/about-self-hosted-runners)

---

## 🔑 How to Get a Personal Access Token

To create a Personal Access Token (PAT) for GitHub Actions, follow these steps:

1. Go to [GitHub Settings – Developer settings – Personal access tokens](https://github.com/settings/tokens).
2. Click **Generate new token** (Classic) or **Generate new token (Fine-grained)**.
3. Give your token a name and select an expiration date.
4. Select at least the following permissions:
   - **repo** (for repository access)
   - **workflow** (for Actions workflows)
5. Click **Generate token** and copy the token. It will only be shown once!
6. Use this token in your `.env` file as `ACCESS_TOKEN`.

For more details, see the official GitHub documentation:  
👉 [Creating a personal access token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token)

---

## ⚡ Quick Start

### 1. Clone this repository

```bash
git clone https://github.com/shopping2go/gh-self-hosted-runner-docker.git
cd gh-self-hosted-runner-docker
```

### 2. Configure your environment

#### 🧱 Repository Runner – `.env-repo`

```env
RUNNER_SCOPE=repos
REPO_URL=https://github.com/ORGANIZATION/REPO
ACCESS_TOKEN=<your_repo_token>
RUNNER_NAME=repo-runner
LABELS=docker,repo
DOCKER_GID=999
```

#### 🏢 Organization Runner – `.env-org`

```env
RUNNER_SCOPE=orgs
REPO_URL=https://github.com/ORGANIZATION
ACCESS_TOKEN=<your_org_token>
RUNNER_NAME=org-runner
LABELS=docker,org
DOCKER_GID=999
```

### 3. Build & start the runner

```bash
# For repository-level runner
docker-compose --env-file .env-repo up -d

# For organization-level runner
docker-compose --env-file .env-org up -d
```

---

## 🧠 How It Works

- Fetches a fresh GitHub registration token on startup
- Configures and registers the runner using `config.sh`
- Starts both the runner and a background token refresher
- Automatically removes stale runners on restart
- Supports Docker socket access for Docker-based workflows

---

## 🗂️ File Overview

```text
.
├── Dockerfile          # Image definition
├── docker-compose.yml  # Container setup
├── start.sh            # Runner bootstrap & token refresh logic
├── .env-org            # Environment file for organization runner
├── .env-repo           # Environment file for repository runner
└── LICENSE
```

---

## ⚙️ Customization Options

| Variable       | Description                        | Example                        |
|---------------|------------------------------------|---------------------------------|
| RUNNER_SCOPE  | Runner type (repos or orgs)        | repos                          |
| REPO_URL      | GitHub URL for repo or org         | https://github.com/myorg/myrepo |
| ACCESS_TOKEN  | Personal Access Token              | ghp_abc123...                   |
| RUNNER_NAME   | Custom runner name                 | ci-runner-1                     |
| LABELS        | Comma-separated labels             | linux,docker,self-hosted        |
| DOCKER_GID    | Host Docker group ID               | 999                             |

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

## 🔍 Keywords

GitHub Actions, self-hosted runner, Docker, CI/CD, automation, repository runner, organization runner, token refresh, workflow runner, Docker-in-Docker, DevOps

<div> <sub>💡 Maintained with ❤️ by <a href="https://www.shopping2go.de">shopping2go GmbH</a></sub> </div>
