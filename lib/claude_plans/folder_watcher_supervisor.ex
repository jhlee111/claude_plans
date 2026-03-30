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

  @doc "Start a watcher for a folder path."
  @spec add_folder(String.t()) :: :ok
  def add_folder(path) do
    if Process.whereis(__MODULE__) do
      case DynamicSupervisor.start_child(__MODULE__, {ClaudePlans.SingleFolderWatcher, path}) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} ->
          Logger.warning("[FolderWatcherSupervisor] Failed to start watcher for #{path}: #{inspect(reason)}")
          :ok
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

  @doc "Start watchers for all configured folders."
  @spec init_all() :: :ok
  def init_all do
    for folder <- ClaudePlans.Folders.list() do
      add_folder(folder.path)
    end

    :ok
  end
end
