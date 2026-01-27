# Contributing to Pindrop

Thank you for your interest in contributing to Pindrop! This document provides guidelines and instructions for contributing.

## Getting Started

### Prerequisites

- macOS 14+ (Sonoma or later)
- Xcode 15+
- `just` command runner: `brew install just`

### Setup

1. Fork and clone the repository:
```bash
git clone https://github.com/YOUR_USERNAME/pindrop.git
cd pindrop
```

2. Open in Xcode:
```bash
just xcode
```

3. Build and test:
```bash
just dev
```

## Development Workflow

### Building

```bash
just build              # Debug build
just build-release      # Release build
just clean              # Clean artifacts
```

### Testing

```bash
just test               # Run tests
just test-coverage      # Run with coverage
```

### Code Quality

```bash
just lint               # Lint code (requires swiftlint)
just format             # Format code (requires swiftformat)
```

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Your Changes

Follow the existing code style and patterns. See `AGENTS.md` for architecture details.

### 3. Test Your Changes

```bash
just test
```

### 4. Commit Your Changes

Use clear, descriptive commit messages:

```bash
git commit -m "Add feature: description of what you added"
```

### 5. Push and Create PR

```bash
git push origin feature/your-feature-name
```

Then create a Pull Request on GitHub.

## Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI for all UI code
- Use `@Observable` (not `ObservableObject`) for new code
- All services should be `@MainActor` (except `HotkeyManager`)
- Use `Log.{category}` for logging
- Store secrets in Keychain, not UserDefaults

## Project Structure

```
Pindrop/
├── Services/           # Business logic
├── UI/                 # SwiftUI views
├── Models/             # Data models
└── Utils/              # Utilities
```

See `AGENTS.md` for detailed architecture documentation.

## Testing

- Write tests for new features
- Maintain or improve code coverage
- Test on a clean Mac before submitting

## Documentation

- Update README.md for user-facing changes
- Update AGENTS.md for architecture changes
- Add comments for complex logic only

## Pull Request Guidelines

### Before Submitting

- [ ] Code builds without errors
- [ ] All tests pass
- [ ] Code is formatted and linted
- [ ] Documentation is updated
- [ ] Commit messages are clear

### PR Description

Include:
- What changed and why
- How to test the changes
- Screenshots (for UI changes)
- Related issues

## Release Process

Maintainers only:

```bash
just release            # Build, sign, create DMG
just notarize dist/Pindrop.dmg
just staple dist/Pindrop.dmg
```

## Questions?

Open an issue or discussion on GitHub.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
