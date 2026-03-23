# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2026-03-23

### Added
- Inline activity tab navigation — j/k and click now select events in-place with diff preview in the main content area, instead of navigating away
- "Go to file" action via Enter key, header button, or per-row `›` arrow icon to explicitly navigate to the source file
- Active row highlighting in activity sidebar with scroll-into-view support

### Changed
- Activity tab main content shows diff preview when an event is selected (was a static placeholder)
- Escape key clears activity selection before other dismiss actions
- New activity events shift the selected index to maintain position

### Improved
- Resolved all 23 credo static analysis issues across 7 files (complexity, nesting, naming, efficiency)
- Extracted helpers to reduce cyclomatic complexity in `handle_params`, `handle_event`, `handle_info`
- Renamed `is_plan_path?`/`is_project_path?` to `plan_path?`/`project_path?` per Elixir convention
- Replaced `Enum.map |> Enum.join` with `Enum.map_join`, merged double `Enum.filter`

## [0.7.0] - 2026-03-23

### Added
- Plan annotation system — inspector mode (`i` key or Annotate button) to select any rendered element and attach developer feedback
- Block-level selection for paragraphs, headings, bullets, blockquotes, code blocks, table cells, and Mermaid diagram nodes/edges/labels
- Code block line-level selection with line number and code preview in annotation reference
- Mermaid diagram node/edge/label selection using `elementsFromPoint()` with post-render data tagging (`data-mermaid-*` attributes)
- Inspector tooltip follows cursor showing element type and content preview
- Annotation panel (right sidebar) with edit/display mode toggle and Save button
- Copy All Annotations to clipboard in structured format for pasting into Claude Code terminal
- Write to Plan File — appends annotations as HTML comment block at end of file, preserving content flow for LLM readability
- Strip Annotations from File — removes annotation block after Claude Code processes feedback
- Keyboard shortcut `i` to toggle annotation inspector

### Changed
- Renamed `Mermaid` JS hook to `PlanContent` — consolidates mermaid rendering, search highlighting, inspector, and annotation marker behaviors
- Escape key cascade now includes inspector mode and annotation panel

## [0.6.1] - 2026-03-22

### Fixed
- Mermaid charts now re-render with correct colors when toggling between light and dark mode
- Dark mode mermaid theme uses custom color palette for better contrast and readability

## [0.6.0] - 2026-03-22

### Added
- Real-time activity feed (Activity tab) tracking file creates, updates, and deletes across plans and project memory
- Activity events link directly to the relevant file — click an event to navigate to the plan or project file
- Unseen activity badge on the Activity tab when changes happen in the background
- Keyboard shortcut `3` to switch to Activity tab

### Changed
- Unified selection state: removed `highlight_index` in favor of a single `selected`/`selected_file` source of truth, fixing dual-highlight bugs when navigating between tabs
- Keyboard navigation (J/K) now blurs previously focused elements to prevent stale browser focus outlines

### Removed
- `cb-file-btn--highlighted` CSS class (replaced by unified `--active` styling)

## [0.5.0] - 2026-03-22

### Added
- Font size control (A/A buttons) in the sidebar tabs bar for adjustable content size (10px–28px)
- Inline Lucide SVG icons replacing all text/unicode icons (help, theme, edit, copy, delete, search clear)
- Relative timestamps in sidebar ("5 min ago", "3h ago", "2d ago" instead of absolute dates)

### Fixed
- Keyboard shortcuts no longer fire when the iframe is not focused (fixes input conflict in Tidewave)

## [0.4.0] - 2026-03-21

### Added
- Open files in external editor via `PLUG_EDITOR` env var (`e` shortcut or "Edit" button)
- Delete plan and project files with confirmation (`x` shortcut or delete button)
- File action buttons (Edit, Copy, Delete) grouped on hover

### Changed
- Dark mode redesigned with true black background for improved contrast
- Dark mode code blocks use CSS invert for automatic syntax theme adaptation
- CI workflow uses `setup-zig` action and caches Burrito ERTS downloads for faster builds
- CI workflow uses `erlef/setup-beam` with prebuilt binaries instead of `brew install`

### Fixed
- Compiler warning in layouts module
- CI Zig version updated to 0.15.2 (required by Burrito 1.5.0)

## [0.3.0] - 2026-03-21

### Added
- Plan version history with automatic snapshots on each file change
- Diff view comparing any two plan versions with line-level ins/del highlighting and hunk collapsing
- Persistent version storage in `.history/` JSON files (survives app restarts)
- Render cache with ETS-backed parallel pre-rendering for instant plan switching
- Keyboard shortcuts: `d` to toggle diff view, `v` to toggle version history panel
- Version comparison dropdowns to diff arbitrary version pairs

### Fixed
- Tidewave plug ordering — moved before `code_reloading?` block
- Live reload socket setup now uses `code_reloading?` guard

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
