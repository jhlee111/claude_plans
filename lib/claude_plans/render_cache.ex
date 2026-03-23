defmodule ClaudePlans.RenderCache do
  @moduledoc """
  Content-hash based render cache backed by ETS.

  Provides instant lookups for previously rendered markdown and
  parallel background pre-rendering of nearby/all files.
  """
  use GenServer
  require Logger

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Get rendered HTML for markdown content, using cache when available."
  @spec render(String.t() | nil) :: String.t()
  def render(content) when is_binary(content) do
    hash = content_hash(content)

    case :ets.lookup(@table, hash) do
      [{^hash, html}] ->
        html

      [] ->
        html = ClaudePlans.Renderer.to_html(content)
        :ets.insert(@table, {hash, html})
        html
    end
  end

  def render(nil), do: ""

  @doc "Pre-render a list of file paths in parallel in the background."
  @spec prerender([String.t()]) :: :ok
  def prerender(paths) when is_list(paths) and paths != [] do
    GenServer.cast(__MODULE__, {:prerender, paths})
  end

  def prerender([]), do: :ok

  @doc """
  Pre-render files near the given index in a list of file paths.
  Uses a sliding window to render files the user is likely to view next.
  """
  @spec prerender_nearby([String.t()], non_neg_integer(), non_neg_integer()) :: :ok | nil
  def prerender_nearby(all_paths, current_index, window \\ 5) do
    len = length(all_paths)
    start_idx = max(0, current_index - window)
    end_idx = min(len - 1, current_index + window)

    if start_idx <= end_idx do
      paths = Enum.slice(all_paths, start_idx..end_idx)
      prerender(paths)
    end
  end

  @doc "Check if content is already cached."
  @spec cached?(String.t()) :: boolean()
  def cached?(content) when is_binary(content) do
    hash = content_hash(content)
    :ets.lookup(@table, hash) != []
  end

  @doc "Number of cached entries."
  @spec size() :: non_neg_integer()
  def size, do: :ets.info(@table, :size)

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    _table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    send(self(), :prerender_plans)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prerender_plans, state) do
    plans = ClaudePlans.Watcher.list_plans()
    paths = Enum.map(plans, & &1.path)
    do_prerender_async(paths)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:prerender, paths}, state) do
    do_prerender_async(paths)
    {:noreply, state}
  end

  # --- Private ---

  defp do_prerender_async(paths) do
    paths_to_render = Enum.filter(paths, &uncached_path?/1)

    if paths_to_render != [] do
      Task.Supervisor.start_child(ClaudePlans.TaskSupervisor, fn ->
        paths_to_render
        |> Task.async_stream(&render_file/1,
          max_concurrency: System.schedulers_online(),
          timeout: 30_000,
          on_timeout: :kill_task
        )
        |> Stream.run()

        Logger.debug("[RenderCache] Pre-rendered #{length(paths_to_render)} files")
      end)
    end
  end

  defp uncached_path?(path) do
    case File.read(path) do
      {:ok, content} -> not cached?(content)
      _ -> false
    end
  end

  defp render_file(path) do
    case File.read(path) do
      {:ok, content} -> cache_content(content)
      _ -> :error
    end
  end

  defp cache_content(content) do
    hash = content_hash(content)

    case :ets.lookup(@table, hash) do
      [{^hash, _}] ->
        :already_cached

      [] ->
        html = ClaudePlans.Renderer.to_html(content)
        :ets.insert(@table, {hash, html})
        :rendered
    end
  end

  defp content_hash(content) do
    :crypto.hash(:sha256, content)
  end
end
