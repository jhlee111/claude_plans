defmodule ClaudePlans.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: ClaudePlans.PubSub},
      {Registry, keys: :duplicate, name: ClaudePlans.Registry},
      ClaudePlans.Watcher,
      ClaudePlans.SearchIndex,
      ClaudePlans.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ClaudePlans.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    if Application.get_env(:claude_plans, :open_browser, false) do
      port = ClaudePlans.Endpoint.config(:http) |> Keyword.get(:port, 4002)
      open_browser("http://localhost:#{port}")
    end

    {:ok, pid}
  end

  defp open_browser(url) do
    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [url])
      {:unix, _} -> System.cmd("xdg-open", [url])
      _ -> :ok
    end
  rescue
    _ -> :ok
  end
end
