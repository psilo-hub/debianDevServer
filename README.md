# debianDevServer

One-stop-shop bash script for turning a fresh Debian machine into a useful dev environment.

> **Status:** Work in progress. The toolset, categories, and structure are evolving as needs are identified. Contributions and suggestions welcome.

## Use case

The primary use case is setting up a development server on a **Debian VM running inside an Android Linux VM host** (e.g. via Termux, UserLAnd, or similar). This gives you a portable coding environment with Java/Node.js toolchains, opencode CLI with a Telegram bot bridge, VS Code Server — accessible from your phone or any browser on the local network.

## Roadmap

- [x] Core toolchain (Node.js, Java, Maven)
- [x] opencode CLI + Telegram bot bridge
- [x] VS Code Server with random password
- [x] Utilities
- [x] UFW firewall, dotfiles
- [ ] Idempotency improvements
- [ ] Optional SSH hardening (key-only auth, custom port, fail2ban)

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/psilo-hub/debianDevServer/main/debianDevServer.sh | sudo bash
```

Firewall is configured automatically — see [Security](#security) below.

## What it installs

| Category | Tools |
|---|---|---|
| System | build-essential, curl, git, htop, tmux |
| Languages | Node.js 22, Java JDK, Maven |
| CLI tools | opencode, opencode Telegram bot |
| IDE | VS Code Server (random password, port 8080) |
| Utilities | ripgrep, fd-find, bat, jq, shellcheck, tree, ncdu |
| Security | **ufw firewall** — denies incoming by default, opens SSH (22) and code-server (8080), enabled at install |
| Dotfiles | bash aliases & PATH, .gitconfig, .tmux.conf, .inputrc |

Auto-detects already-installed tools to avoid reinstalling.

## Security

- **ufw** is installed and configured with `deny incoming` / `allow outgoing` as default policies.
- **Ports opened:** `22/tcp` (SSH), `8080/tcp` (code-server).
- **Firewall is enabled immediately** during installation (mandatory — cannot be skipped).
- **VS Code Server** is configured with a **random password** (generated via `openssl rand`). The password is displayed once at the end of the script. Save it — it will not be shown again.

## Notes

- Designed for Debian 12+ (bookworm or later)
- ANSI-colored output for clear progress reporting
- All logic is organized into named functions for maintainability
- Node.js installs to the invoking user's home directory

