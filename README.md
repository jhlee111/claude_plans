# Claude Plans

Standalone viewer for [Claude Code](https://claude.com/claude-code) plans and project memory files.

Browse `~/.claude/plans/` and `~/.claude/projects/*/memory/` in a clean, searchable web UI with live file watching, syntax highlighting, and Mermaid diagram support.

![Claude Plans Preview](assets/preview.png)

## Features

- **Plans tab** — Browse and read Claude Code plan files with live updates
- **Projects tab** — Browse project memory files across all Claude Code projects
- **Dark / Light mode** — Auto-detects OS preference, toggle with one click, persisted in localStorage
- **Server-side Markdown** — Rendered via MDEx with GitHub-style syntax highlighting
- **Mermaid diagrams** — Automatic rendering of Mermaid code blocks
- **Live file watching** — Plans auto-reload when files change on disk
- **Copy path** — Hover any file to copy its absolute path to clipboard
- **Self-contained** — No Tailwind, no Node.js, no asset pipeline. CSS and JS embedded at compile time
- **Standalone binary** — Single executable via Burrito, no Elixir/Erlang installation required

## Quick Start

### Standalone Binary (recommended)

Download the latest binary from [Releases](https://github.com/jhlee111/claude_plans/releases):

```bash
# macOS Apple Silicon
curl -L -o claude-plans https://github.com/jhlee111/claude_plans/releases/download/v0.1.2/claude_plans_macos_arm
chmod +x claude-plans
./claude-plans
# Opens http://localhost:4002 in your browser
```

### From Source

```bash
git clone https://github.com/jhlee111/claude_plans.git
cd claude_plans
mix deps.get
mix phx.server
# Visit http://localhost:4002
```

### As a Hex Package (Phoenix projects)

```elixir
# mix.exs
{:claude_plans, "~> 0.1.1", only: :dev}
```

## Command Line Options

All configuration is done via environment variables:

| Variable | Default | Description |
|---|---|---|
| `PORT` | `4002` | HTTP server port |
| `NO_BROWSER` | (unset) | Set to `1` to disable auto-opening browser on launch |
| `PLANS_DIR` | `~/.claude/plans` | Directory containing Claude Code plan files |
| `PROJECTS_DIR` | `~/.claude/projects` | Directory containing Claude Code project directories |

### Examples

```bash
# Default: starts on port 4002, opens browser
./claude_plans_macos_arm

# Custom port
PORT=3000 ./claude_plans_macos_arm

# Headless (no browser auto-open)
NO_BROWSER=1 ./claude_plans_macos_arm

# Custom plans directory
PLANS_DIR=/path/to/plans ./claude_plans_macos_arm

# Both
PORT=8080 NO_BROWSER=1 ./claude_plans_macos_arm
```

## Building from Source

### Development

```bash
mix deps.get
mix phx.server
# Visit http://localhost:4002
```

### Standalone Binary

Requires [Zig](https://ziglang.org/) (`brew install zig` on macOS).

```bash
# Build for your native architecture
BURRITO_TARGET=macos_arm MIX_ENV=prod mix release

# Output in burrito_out/
```

> **Note:** Cross-compilation is not supported due to native NIF dependencies (MDEx/Rust).
> Each target must be built on its matching architecture. The GitHub Actions CI handles this
> automatically using `macos-14` (ARM) and `macos-13` (Intel) runners.

Linux and Windows targets are defined but commented out in `mix.exs` (untested). Uncomment and build on the matching platform with:

```bash
BURRITO_TARGET=linux_intel MIX_ENV=prod mix release
BURRITO_TARGET=windows_intel MIX_ENV=prod mix release
```

## Architecture

- **Phoenix LiveView** single-page app with two tabs (Plans / Projects)
- **MDEx** for server-side Markdown-to-HTML with syntax highlighting (`github_light` theme)
- **Mermaid CDN** for diagram rendering with light/dark theme support
- **file_system** GenServer with 300ms debounce for live plan file watching
- **Registry** with `:duplicate` keys for PubSub (no dependency on host app)
- **Burrito** for self-extracting standalone binary packaging
- **Compile-time CSS/JS embedding** (Clarity pattern) — fully self-contained, no asset pipeline

## Inspiration

This project was inspired by a comment from **frankdugan3** in the [Ash Framework Discord](https://discord.gg/ash-framework):

> So another fun thing I've done is used MDex to create an alternative to ExDoc that runtime-generates documentation in a LiveView. That way, I can iterate on docs in realtime. It supports most of the ExDoc features, and one of the really nice perks is that I have Claude Code generate the plan docs into the watched extras folders, so I get realtime previews of implementation plans with Mermaid charts, syntax highlighting, etc.
>
> — frankdugan3, Feb 17, 2026

## License

MIT
