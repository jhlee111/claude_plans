import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "4002")

  config :claude_plans, ClaudePlans.Endpoint,
    http: [port: port],
    server: true,
    url: [host: "localhost", port: port]

  config :claude_plans,
    open_browser: System.get_env("NO_BROWSER") != "1"
end

if plans_dir = System.get_env("PLANS_DIR") do
  config :claude_plans, plans_dir: Path.expand(plans_dir)
end

if projects_dir = System.get_env("PROJECTS_DIR") do
  config :claude_plans, projects_dir: Path.expand(projects_dir)
end
