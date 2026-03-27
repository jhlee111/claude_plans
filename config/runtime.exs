import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4002")

  config :claude_plans, ClaudePlans.Endpoint,
    http: [port: port],
    server: true,
    url: [host: "localhost", port: port]

  config :claude_plans,
    open_browser: System.get_env("NO_BROWSER") != "1"

  log_level =
    case System.get_env("LOG_LEVEL") do
      nil -> :info
      level -> String.to_existing_atom(level)
    end

  config :logger, level: log_level
end

config :claude_plans,
  plans_dir: Path.expand(System.get_env("PLANS_DIR") || "~/.claude/plans"),
  projects_dir: Path.expand(System.get_env("PROJECTS_DIR") || "~/.claude/projects")
