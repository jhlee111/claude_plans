defmodule ClaudePlans.SingleFolderWatcher do
  @moduledoc "Watches a single directory for .md file changes and dispatches events."
  use GenServer
  require Logger

  alias ClaudePlans.Debounce

  @debounce_ms 300

  def start_link(path) do
    GenServer.start_link(__MODULE__, path)
  end

  def child_spec(path) do
    %{
      id: {__MODULE__, path},
      start: {__MODULE__, :start_link, [path]},
      restart: :transient
    }
  end

  @impl true
  def init(path) do
    case FileSystem.start_link(dirs: [path]) do
      {:ok, watcher_pid} ->
        FileSystem.subscribe(watcher_pid)
        {:ok, %{watcher_pid: watcher_pid, path: path, debounce_timers: %{}}}

      {:error, reason} ->
        Logger.warning("[SingleFolderWatcher] Failed to watch #{path}: #{inspect(reason)}")
        :ignore
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {file_path, _events}}, state) do
    if String.ends_with?(file_path, ".md") do
      timers =
        Debounce.debounce(
          state.debounce_timers,
          file_path,
          {:debounced_notify, file_path},
          @debounce_ms
        )

      {:noreply, %{state | debounce_timers: timers}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:debounced_notify, file_path}, state) do
    filename = Path.basename(file_path)

    Registry.dispatch(ClaudePlans.Registry, :folder_updates, fn entries ->
      for {pid, _} <- entries,
          do: send(pid, {:folder_file_updated, state.path, filename})
    end)

    {:noreply, %{state | debounce_timers: Debounce.clear(state.debounce_timers, file_path)}}
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("[SingleFolderWatcher] Watcher stopped for #{state.path}")
    {:noreply, state}
  end
end
