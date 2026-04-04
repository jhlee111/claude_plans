defmodule ClaudePlans.FolderWatcherSupervisor do
  @moduledoc "DynamicSupervisor for per-folder file watchers."
  use DynamicSupervisor
  require Logger

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @max_watchers 10

  @doc "Start a watcher for a folder path, evicting one if at capacity. No-op if already watched."
  @spec add_folder(String.t()) :: :ok
  def add_folder(path) do
    if Process.whereis(__MODULE__) do
      if watching?(path) do
        :ok
      else
        case DynamicSupervisor.start_child(__MODULE__, {ClaudePlans.SingleFolderWatcher, path}) do
          {:ok, _pid} ->
            enforce_limit()

          {:error, reason} ->
            Logger.warning(
              "[FolderWatcherSupervisor] Failed to start watcher for #{path}: #{inspect(reason)}"
            )

            :ok
        end
      end
    else
      Logger.warning("[FolderWatcherSupervisor] Not running, skipping watcher for #{path}")
      :ok
    end
  end

  @doc "Stop the watcher for a folder path."
  @spec remove_folder(String.t()) :: :ok
  def remove_folder(path) do
    if Process.whereis(__MODULE__) do
      children = DynamicSupervisor.which_children(__MODULE__)

      Enum.each(children, fn {_, pid, _, _} ->
        if is_pid(pid) do
          case :sys.get_state(pid) do
            %{path: ^path} -> DynamicSupervisor.terminate_child(__MODULE__, pid)
            _ -> :ok
          end
        end
      end)
    end

    :ok
  end

  @doc "Return the number of active watchers."
  @spec count() :: non_neg_integer()
  def count do
    if Process.whereis(__MODULE__) do
      DynamicSupervisor.which_children(__MODULE__)
      |> Enum.count(fn {_, pid, _, _} -> is_pid(pid) end)
    else
      0
    end
  end

  @doc "Start watchers for all configured folders."
  @spec init_all() :: :ok
  def init_all do
    for folder <- ClaudePlans.Folders.list() do
      add_folder(folder.path)
    end

    :ok
  end

  defp watching?(path) do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.any?(fn {_, pid, _, _} ->
      is_pid(pid) and match?(%{path: ^path}, :sys.get_state(pid))
    end)
  end

  # Evict one watcher when over the limit to prevent fd exhaustion.
  defp enforce_limit do
    children = DynamicSupervisor.which_children(__MODULE__)
    active = Enum.filter(children, fn {_, pid, _, _} -> is_pid(pid) end)

    if length(active) > @max_watchers do
      {_, oldest_pid, _, _} = hd(active)
      DynamicSupervisor.terminate_child(__MODULE__, oldest_pid)
    end

    :ok
  end
end
