import Config

config :claude_plans,
  plans_dir: nil,
  projects_dir: nil

config :claude_plans, ClaudePlans.Endpoint,
  pubsub_server: ClaudePlans.PubSub,
  url: [host: "localhost"],
  http: [port: String.to_integer(System.get_env("PORT") || "4002")],
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64() |> binary_part(0, 64),
  live_view: [signing_salt: "claude_plans_salt"],
  render_errors: [formats: [html: ClaudePlans.Web.ErrorHTML]],
  server: true

config :phoenix, :json_library, Jason
config :logger, :console, format: "$time $metadata[$level] $message\n"

import_config "#{config_env()}.exs"
