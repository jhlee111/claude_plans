defmodule ClaudePlans.Watcher do
  @moduledoc false
  use GenServer
  require Logger

  @debounce_ms 300

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @type plan_entry :: %{
          filename: String.t(),
          display_name: String.t(),
          modified: integer(),
          path: String.t()
        }

  @doc "Subscribe the calling process to plan file change notifications."
  @spec subscribe() :: :ok
  def subscribe do
    {:ok, _} = Registry.register(ClaudePlans.Registry, :plan_updates, [])
    :ok
  end

  @doc "Lists all .md plan files sorted by modified time (newest first)."
  @spec list_plans() :: [plan_entry()]
  def list_plans do
    dir = ClaudePlans.plans_dir()
    if is_nil(dir), do: [], else: do_list_plans(dir)
  end

  defp do_list_plans(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.flat_map(&plan_entry(dir, &1))
        |> Enum.sort_by(& &1.modified, :desc)

      {:error, _} ->
        []
    end
  end

  defp plan_entry(dir, filename) do
    path = Path.join(dir, filename)

    case File.stat(path, time: :posix) do
      {:ok, stat} ->
        [
          %{
            filename: filename,
            display_name: String.replace_trailing(filename, ".md", ""),
            modified: stat.mtime,
            path: path
          }
        ]

      {:error, _} ->
        []
    end
  end

  @impl true
  def init(_) do
    dir = ClaudePlans.plans_dir()
    File.mkdir_p!(dir)

    {:ok, watcher_pid} = FileSystem.start_link(dirs: [dir])
    FileSystem.subscribe(watcher_pid)

    {:ok, %{watcher_pid: watcher_pid, debounce_timers: %{}}}
  end

  alias ClaudePlans.Debounce

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if String.ends_with?(path, ".md") do
      timers = Debounce.debounce(state.debounce_timers, path, {:debounced_notify, path}, @debounce_ms)
      {:noreply, %{state | debounce_timers: timers}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:debounced_notify, path}, state) do
    filename = Path.basename(path)

    Registry.dispatch(ClaudePlans.Registry, :plan_updates, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:plan_updated, filename})
    end)

    {:noreply, %{state | debounce_timers: Debounce.clear(state.debounce_timers, path)}}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("[ClaudePlans] File watcher stopped")
    {:noreply, state}
  end
end
