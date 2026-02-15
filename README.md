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
swift run ClawdDeck
```

## Connect

1. Launch Clawd Deck
2. Enter your gateway address (default: localhost:18789)
3. Enter your gateway token (if configured)
4. Click Connect

## VPS Connection Setup Guide

To connect ClawDeck to a remote server or VPS, you'll need to set up a Clawdbot gateway on your server.

### Prerequisites

- A VPS or server (any Linux distribution)
- Node.js 20 or later installed on the server
- Basic command line access to your server

### Installing Clawdbot Gateway

Install the Clawdbot CLI globally on your server:

```bash
# Using pnpm (recommended)
pnpm install -g clawdbot

# Or using npm
npm install -g clawdbot
```

### Gateway Configuration

1. Initialize the gateway configuration:
   ```bash
   clawdbot init
   ```

2. Edit the generated configuration file to customize your setup. The config includes:
   - Port settings (default: 18789 for local, 443 for TLS)
   - Authentication tokens
   - SSL/TLS certificates (if enabled)

### TLS/SSL Setup

For secure remote connections, we recommend using HTTPS/WSS:

**Option 1: Reverse Proxy (Recommended)**
- Set up nginx or Caddy as a reverse proxy
- Use Let's Encrypt for automatic SSL certificates
- Configure the proxy to forward WebSocket connections to your gateway

**Option 2: Cloudflare Tunnel**
- Use Cloudflare's tunnel service for secure access without port forwarding
- No need to expose ports or manage certificates directly

### Firewall Configuration

Open the required port in your server's firewall:

```bash
# For TLS connections (port 443)
sudo ufw allow 443

# For local/non-TLS connections (port 18789)
sudo ufw allow 18789
```

### Getting Your Gateway Token

After initialization, find your gateway token in the configuration file:

```bash
cat ~/.config/clawdbot/config.json | grep token
```

### Connecting from ClawDeck

1. In ClawDeck's connection setup, enter:
   - **Host**: Your server's IP address or domain
   - **Port**: 443 (for TLS) or 18789 (for local)
   - **Token**: The token from your gateway config

2. Click Connect to establish the connection

For detailed setup instructions and troubleshooting, visit the [Clawdbot documentation](https://docs.clawd.bot).

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
