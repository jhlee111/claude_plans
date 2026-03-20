# Claude Plans

Standalone viewer for [Claude Code](https://claude.com/claude-code) plans and project memory files.

Browse `~/.claude/plans/` and `~/.claude/projects/*/memory/` in a clean, searchable web UI with live file watching and Mermaid diagram support.

## Features

- **Plans tab** — Browse and read Claude Code plan files with live updates
- **Projects tab** — Browse project memory files across all Claude Code projects
- **Server-side Markdown** — Rendered via MDEx (no client-side JS dependency)
- **Mermaid diagrams** — Automatic rendering of Mermaid code blocks
- **Live file watching** — Plans auto-reload when files change on disk
- **Self-contained** — No Tailwind, no Node.js, no asset pipeline. CSS and JS embedded at compile time

## Quick Start

### Standalone Binary

```bash
# Download the binary for your platform
curl -L -o claude-plans https://github.com/.../releases/download/v0.1.0/claude-plans-macos-arm64
chmod +x claude-plans
./claude-plans
# Opens http://localhost:4002
```

### As a Hex Package (Phoenix projects)

```elixir
# mix.exs
{:claude_plans, "~> 0.1", only: :dev}
```

```bash
mix igniter.install claude_plans
```

### From Source

```bash
git clone https://github.com/.../claude_plans.git
cd claude_plans
mix deps.get
mix phx.server
# Visit http://localhost:4002
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT`   | `4002`  | HTTP server port |

## Building Standalone Binary

Requires [Zig](https://ziglang.org/) in PATH.

```bash
# Build for current platform
MIX_ENV=prod mix release

# Build for a specific target
BURRITO_TARGET=macos_arm MIX_ENV=prod mix release
BURRITO_TARGET=linux MIX_ENV=prod mix release

# Output in burrito_out/
```

## Inspiration

This project was inspired by a comment from **frankdugan3** in the [Ash Framework Discord](https://discord.gg/ash-framework):

> So another fun thing I've done is used MDex to create an alternative to ExDoc that runtime-generates documentation in a LiveView. That way, I can iterate on docs in realtime. It supports most of the ExDoc features, and one of the really nice perks is that I have Claude Code generate the plan docs into the watched extras folders, so I get realtime previews of implementation plans with Mermaid charts, syntax highlighting, etc.
>
> — frankdugan3, Feb 17, 2026

## License

MIT
