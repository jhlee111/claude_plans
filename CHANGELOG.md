# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-03-21

### Added
- Full-text search across all plan and project memory files with instant results
- In-document match highlighting with navigation between matches (n/N)
- Vim-style keyboard navigation: j/k to move, Enter/l to open, gg/G to jump, / to search
- Keyboard shortcuts help overlay (press ?)
- Navigation between search result documents with ] and [
- Phoenix PubSub for internal messaging
- Live reload in dev mode for faster development

### Changed
- Sidebar now shows search results inline when a query is active

## [0.1.5] - 2026-03-21

### Fixed
- Plans/projects directory path hardcoded to CI runner's home at compile time
- Moved `Path.expand("~/.claude/...")` to runtime config so it resolves to actual user's home

## [0.1.4] - 2026-03-21

### Added
- Homebrew tap distribution (`brew tap jhlee111/tap && brew install claude-plans`)
- `.formatter.exs` for consistent code formatting
- `/pr` and `/release` Claude Code skills
- `CHANGELOG.md`
- Credo for static analysis

### Changed
- CI: switched from self-hosted to GitHub-hosted `macos-14` runner
- CI: removed DMG packaging and code signing (unnecessary for CLI tool)
- CI: auto-updates Homebrew formula on release

### Fixed
- Syntax highlighting now works in dark mode (was being overridden by CSS)

## [0.1.3] - 2026-03-20

### Changed
- Consolidated CI into single job with code signing and notarization
- Removed Intel build target (macOS 13 runners deprecated)

## [0.1.2] - 2026-03-20

### Added
- `PLANS_DIR` and `PROJECTS_DIR` environment variables for custom directory paths
- Linux and Windows Burrito targets (commented out, untested)

### Changed
- Projects directory is now configurable at runtime instead of hardcoded

### Fixed
- README: removed undocumented `mix igniter.install` command
- README: corrected Hex version spec from `~> 0.1` to `~> 0.1.1`
- README: added cross-compilation limitation note for NIF dependencies

## [0.1.1] - 2026-03-19

### Added
- GitHub Actions CI/CD for automated release builds (ARM + Intel)
- ExDoc configuration for API documentation
- CLI options documentation in README

## [0.1.0] - 2026-03-19

### Added
- Plans tab: browse and read Claude Code plan files with live updates
- Projects tab: browse project memory files across all Claude Code projects
- Dark/light mode with OS preference detection and localStorage persistence
- Server-side Markdown rendering via MDEx with `github_light` syntax highlighting
- Mermaid diagram rendering with light/dark theme support
- Live file watching with 300ms debounce via FileSystem GenServer
- Copy path to clipboard on hover
- Self-contained CSS/JS embedded at compile time (Clarity pattern)
- Standalone binary packaging via Burrito (macOS ARM + Intel)
- Registry-based PubSub with `:duplicate` keys
