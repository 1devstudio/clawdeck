# Contributing to ClawDeck

Thank you for your interest in contributing to ClawDeck! We're excited to have you as part of our community. This native macOS app aims to provide the best possible desktop experience for interacting with Clawdbot, and your contributions help make that vision a reality.

## Getting Started

### Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/clawd-deck.git
   cd clawd-deck
   ```

2. **Build the project**:
   ```bash
   # Using Swift Package Manager
   swift build
   
   # Or open in Xcode (optional but recommended)
   open Package.swift
   ```

3. **Run the application**:
   ```bash
   swift run ClawdDeck
   ```

### Requirements

- **macOS 15+** (Sequoia or later)
- **Swift 6.0+** 
- **Xcode 16+** (if you prefer the IDE experience)
- A running Clawdbot gateway for testing connections

## Project Structure

ClawDeck follows a clean MVVM architecture using modern SwiftUI patterns:

```
Sources/ClawdDeck/
├── App/            # Application entry point and main app configuration
├── Models/         # Data models (Agent, Session, ChatMessage, ConnectionState, etc.)
├── Protocol/       # Gateway wire protocol definitions and constants
├── Services/       # Core services (Gateway client, connection management, message persistence)
├── ViewModels/     # Observable view models following MVVM pattern
├── Views/          # SwiftUI views (sidebar, chat interface, inspector panels, settings)
├── Utilities/      # Helper utilities (Keychain access, extensions, formatters)
└── Resources/      # Assets, colors, and other resources
```

### Key Architecture Principles

- **SwiftUI + @Observable**: We use Swift 5.9's Observation framework for reactive state management
- **MVVM Pattern**: ViewModels own business logic and state; Views are purely declarative
- **Actor Isolation**: Thread-safe networking and data access using Swift's actor model
- **No External Dependencies**: Pure Swift/SwiftUI implementation using native Apple frameworks

## Code Style

We follow these conventions to maintain consistency:

- **SwiftUI Declarative Style**: Prefer declarative view composition over imperative UI updates
- **@Observable Models**: Use `@Observable` for ViewModels and shared state objects
- **swift-format**: We use `swift-format` for consistent code formatting
- **Descriptive Naming**: Use clear, self-documenting variable and function names
- **Minimal Comments**: Write code that explains itself; use comments for complex business logic only

### Formatting

Before submitting a PR, please run:

```bash
swift-format --in-place --recursive Sources/
```

## How to Contribute

### Reporting Issues

If you encounter a bug or have a feature request:

1. **Check existing issues** to avoid duplicates
2. **Use our issue templates** when creating new issues
3. **Include relevant details**:
   - macOS version
   - Xcode version (if applicable)
   - Steps to reproduce
   - Expected vs actual behavior
   - Console logs or error messages

### Submitting Changes

1. **Fork the repository** to your GitHub account

2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**:
   - Follow our code style guidelines
   - Add tests for new functionality when appropriate
   - Update documentation if needed

4. **Test your changes**:
   - Build and run the app locally
   - Test with a real Clawdbot gateway connection
   - Verify your changes work across different macOS versions if possible

5. **Commit with clear messages**:
   ```bash
   git commit -m "Add feature: brief description of what you added"
   ```

6. **Push to your fork and create a Pull Request**:
   - Provide a clear description of your changes
   - Reference any related issues
   - Include screenshots for UI changes

### Pull Request Review Process

- All PRs require review from maintainers
- We'll provide constructive feedback and work with you to refine changes
- Once approved, we'll merge your contribution

## Types of Contributions

We welcome various types of contributions:

- **Bug fixes**: Help us squash issues and improve stability
- **Feature enhancements**: Add new functionality or improve existing features
- **UI/UX improvements**: Make the app more intuitive and visually appealing
- **Performance optimizations**: Help ClawDeck run faster and use fewer resources
- **Documentation**: Improve README, code comments, or create tutorials
- **Testing**: Add unit tests or help with manual testing across macOS versions

## Getting Help

Need help or have questions?

- **GitHub Issues**: For bug reports and feature requests
- **GitHub Discussions**: For general questions, ideas, and community discussion
- **Documentation**: Check the README and inline code documentation

## Code of Conduct

We're committed to providing a welcoming and inclusive environment for all contributors. Please:

- **Be respectful** in all interactions
- **Provide constructive feedback** in code reviews
- **Be patient** with newcomers and questions
- **Focus on the technical merits** of contributions
- **Assume good intentions** from other contributors

## Recognition

All contributors will be recognized in our project. Your GitHub profile will automatically appear in the contributors section, and significant contributions may be highlighted in release notes.

---

Thank you for contributing to ClawDeck! Your efforts help make this the best possible macOS client for Clawdbot users everywhere. 🚀