defmodule ClaudePlans.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    configure_logger()

    children = [
      {Phoenix.PubSub, name: ClaudePlans.PubSub},
      {Registry, keys: :duplicate, name: ClaudePlans.Registry},
      {Task.Supervisor, name: ClaudePlans.TaskSupervisor},
      ClaudePlans.Watcher,
      ClaudePlans.VersionStore,
      {ClaudePlans.FolderWatcherSupervisor, []},
      ClaudePlans.DirIndex,
      ClaudePlans.SearchIndex,
      ClaudePlans.RenderCache,
      ClaudePlans.ActivityFeed,
      ClaudePlans.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ClaudePlans.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    # Async init: start folder watchers without blocking app startup
    Task.Supervisor.start_child(ClaudePlans.TaskSupervisor, fn ->
      ClaudePlans.FolderWatcherSupervisor.init_all()
    end)

    if Application.get_env(:claude_plans, :open_browser, false) do
      port = ClaudePlans.Endpoint.config(:http) |> Keyword.get(:port, 4002)
      open_browser("http://localhost:#{port}")
    end

    {:ok, pid}
  end

  defp configure_logger do
    case System.get_env("LOG_LEVEL") do
      nil -> :ok
      level -> Logger.configure(level: String.to_atom(level))
    end
  end

  defp open_browser(url) do
    {cmd, args} =
      case :os.type() do
        {:unix, :darwin} -> {"open", [url]}
        {:unix, _} -> {"xdg-open", [url]}
        _ -> {nil, []}
      end

    if cmd do
      case System.cmd(cmd, args, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> Logger.warning("[ClaudePlans] Failed to open browser: #{output}")
      end
    end
  rescue
    e ->
      Logger.warning("[ClaudePlans] Failed to open browser: #{inspect(e)}")
      :ok
  end
end
