# Clawd Deck

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Native macOS desktop app for [Clawdbot](https://github.com/clawdbot/clawdbot).

## Requirements

- macOS 14+ (Sonoma)
- Xcode 15+
- A running Clawdbot gateway

## Build

Open `Package.swift` in Xcode, select the ClawdDeck scheme, and run.

Or via command line:

```bash
swift build
swift run clawdeck
```

## Connecting to Your Gateway

ClawDeck connects to a running [Clawdbot](https://github.com/clawdbot/clawdbot) gateway. You'll need three things:

| Setting | Description | Example |
|---------|-------------|---------|
| **Host** | Your gateway's domain or IP | `my-server.example.com` |
| **Port** | 443 for TLS, 18789 for local | `443` |
| **Token** | Gateway auth token | `8321e17a...` |

### Getting Your Connection Details

If your Clawdbot agent is already running, you can ask it directly in any connected channel (Telegram, webchat, etc.):

> **You:** *What's my gateway URL and auth token for ClawDeck?*

The agent has access to the gateway config and Caddy setup, so it can look up and provide:
- The external hostname from your Caddyfile or reverse proxy config
- The auth token from the gateway config
- The correct port and TLS settings

### Manual Lookup

If you prefer to find the details yourself:

```bash
# Gateway auth token
cat ~/.clawdbot/clawdbot.json | python3 -c "import json,sys; print(json.load(sys.stdin)['gateway']['auth']['token'])"

# External hostname (if using Caddy)
grep -E '^[a-zA-Z0-9]' /etc/caddy/Caddyfile | head -1

# Gateway port
cat ~/.clawdbot/clawdbot.json | python3 -c "import json,sys; print(json.load(sys.stdin)['gateway']['port'])"
```

### Connection Setup

1. Launch ClawDeck
2. Enter your **Host**, **Port**, and **Token**
3. Enable **TLS** if connecting over the internet (port 443)
4. Click **Connect**

For gateway installation and configuration, see the [Clawdbot documentation](https://docs.clawd.bot).

### Securing Your VPS

The Clawdbot gateway listens on `localhost:18789` by default and is **not exposed to the internet**. To connect from ClawDeck remotely, you need a reverse proxy with TLS.

**1. Point a domain to your VPS**

Add an A record for your domain (e.g. `gateway.example.com`) pointing to your VPS IP address.

**2. Install Caddy** (recommended — automatic HTTPS via Let's Encrypt)

```bash
sudo apt install -y caddy
```

**3. Configure the reverse proxy**

Edit `/etc/caddy/Caddyfile`:

```
gateway.example.com {
    reverse_proxy localhost:18789
}
```

Caddy will automatically obtain and renew a TLS certificate for your domain.

```bash
sudo systemctl restart caddy
```

**4. Configure the firewall**

Only expose HTTPS — keep the gateway port closed to the outside:

```bash
# Allow HTTPS (Caddy handles TLS termination)
sudo ufw allow 443/tcp

# Allow SSH (so you don't lock yourself out)
sudo ufw allow 22/tcp

# Enable firewall
sudo ufw enable

# Verify — port 18789 should NOT be listed
sudo ufw status
```

**5. Connect from ClawDeck**

| Setting | Value |
|---------|-------|
| Host | `gateway.example.com` |
| Port | `443` |
| TLS | ✅ Enabled |
| Token | Your gateway auth token |

> **Tip:** The gateway auth token is your only authentication layer. Use a strong token and never commit it to version control. You can regenerate it in `~/.clawdbot/clawdbot.json` under `gateway.auth.token`.

## Features

- Multiple agent support
- Session management
- Markdown rendering with syntax highlighting
- Keyboard-driven navigation (Cmd+K, Cmd+N, etc.)
- Native macOS look and feel

## Architecture

- **SwiftUI** with `@Observable` (Swift 5.9 Observation framework)
- **MVVM** — ViewModels own state, Views are declarative
- **Gateway Protocol v3** — WebSocket-based communication with Clawdbot
- **URLSessionWebSocketTask** — native Apple networking, no third-party deps
- **Actor isolation** — thread-safe gateway client

## Project Structure

```
Sources/ClawdDeck/
├── App/            # App entry point
├── Models/         # Data models (Agent, Session, ChatMessage, etc.)
├── Protocol/       # Gateway wire protocol types and constants
├── Services/       # Gateway client, connection manager, message store
├── ViewModels/     # Observable view models (MVVM)
├── Views/          # SwiftUI views (sidebar, chat, inspector, settings)
├── Utilities/      # Keychain helper, extensions
└── Resources/      # Assets catalog
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to ClawDeck.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
