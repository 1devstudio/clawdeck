# Clawd Deck

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
