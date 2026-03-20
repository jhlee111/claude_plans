defmodule ClaudePlans.Watcher do
  @moduledoc false
  use GenServer
  require Logger

  @debounce_ms 300

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Subscribe the calling process to plan file change notifications."
  def subscribe do
    {:ok, _} = Registry.register(ClaudePlans.Registry, :plan_updates, [])
    :ok
  end

  @doc "Lists all .md plan files sorted by modified time (newest first)."
  def list_plans do
    dir = ClaudePlans.plans_dir()
    if is_nil(dir), do: [], else: do_list_plans(dir)
  end

  defp do_list_plans(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn filename ->
          path = Path.join(dir, filename)

          case File.stat(path, time: :posix) do
            {:ok, stat} ->
              %{
                filename: filename,
                display_name: String.replace_trailing(filename, ".md", ""),
                modified: stat.mtime,
                path: path
              }

            {:error, _} ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.modified, :desc)

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

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if String.ends_with?(path, ".md") do
      state =
        case Map.get(state.debounce_timers, path) do
          nil -> state
          ref -> Process.cancel_timer(ref); state
        end

      ref = Process.send_after(self(), {:debounced_notify, path}, @debounce_ms)
      {:noreply, %{state | debounce_timers: Map.put(state.debounce_timers, path, ref)}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:debounced_notify, path}, state) do
    filename = Path.basename(path)

    Registry.dispatch(ClaudePlans.Registry, :plan_updates, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:plan_updated, filename})
    end)

    {:noreply, %{state | debounce_timers: Map.delete(state.debounce_timers, path)}}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("[ClaudePlans] File watcher stopped")
    {:noreply, state}
  end
end
