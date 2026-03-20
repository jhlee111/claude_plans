import Config

config :claude_plans, ClaudePlans.Endpoint,
  code_reloader: true,
  debug_errors: true,
  check_origin: false,
  watchers: []

config :phoenix_live_view,
  debug_heex_annotations: true

config :claude_plans, dev_routes: true

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_reload,
  dirs: [
    Path.expand("lib", __DIR__ |> Path.dirname())
  ]

config :logger, :console, format: "[$level] $message\n"
