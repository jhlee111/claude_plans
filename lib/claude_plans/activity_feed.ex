defmodule ClaudePlans.ActivityFeed do
  @moduledoc "Watches ~/.claude/ for file changes and maintains a live activity feed."
  use GenServer
  require Logger

  @debounce_ms 300
  @max_events 100
  @ttl_ms 3_600_000
  @gc_interval_ms 60_000

  # --- Public API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Subscribe the calling process to activity feed updates."
  def subscribe do
    {:ok, _} = Registry.register(ClaudePlans.Registry, :activity_updates, [])
    :ok
  end

  @doc "Returns the current list of events (newest first)."
  def list_events do
    GenServer.call(__MODULE__, :list_events)
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    plans_dir = ClaudePlans.plans_dir()
    projects_dir = ClaudePlans.projects_dir()

    known_files = scan_known_files(plans_dir, projects_dir)

    dirs = Enum.filter([plans_dir, projects_dir], &is_binary/1)
    {:ok, watcher_pid} = FileSystem.start_link(dirs: dirs)
    FileSystem.subscribe(watcher_pid)

    Process.send_after(self(), :gc_expired, @gc_interval_ms)

    {:ok,
     %{
       watcher_pid: watcher_pid,
       plans_dir: plans_dir,
       projects_dir: projects_dir,
       debounce_timers: %{},
       known_files: known_files,
       events: []
     }}
  end

  @impl true
  def handle_call(:list_events, _from, state) do
    {:reply, state.events, state}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, _events}}, state) do
    if relevant_path?(path, state.plans_dir, state.projects_dir) do
      {:noreply, debounce_path(state, path)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:debounced_event, path}, state) do
    state = %{state | debounce_timers: Map.delete(state.debounce_timers, path)}

    action = determine_action(path, state.known_files)

    case classify_path(path, state.plans_dir, state.projects_dir) do
      nil ->
        {:noreply, state}

      {category, project, rel_path} ->
        process_activity_event(state, path, action, category, project, rel_path)
    end
  end

  def handle_info(:gc_expired, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -@ttl_ms, :millisecond)
    events = Enum.filter(state.events, &(DateTime.compare(&1.timestamp, cutoff) == :gt))
    Process.send_after(self(), :gc_expired, @gc_interval_ms)
    {:noreply, %{state | events: events}}
  end

  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("[ActivityFeed] File watcher stopped")
    {:noreply, state}
  end

  defp process_activity_event(state, path, action, category, project, rel_path) do
    now = DateTime.utc_now()

    event = %{
      id: event_id(path, now),
      path: path,
      action: action,
      category: category,
      display_name: display_name(path, category),
      project: project,
      rel_path: rel_path,
      filename: Path.basename(path),
      timestamp: now
    }

    events = [event | state.events] |> Enum.take(@max_events)
    known_files = update_known_files(state.known_files, path, action)

    Registry.dispatch(ClaudePlans.Registry, :activity_updates, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:activity_event, event})
    end)

    {:noreply, %{state | events: events, known_files: known_files}}
  end

  defp update_known_files(known_files, path, :deleted), do: Map.delete(known_files, path)
  defp update_known_files(known_files, path, _action), do: update_known_file(known_files, path)

  # --- Internal helpers ---

  defp debounce_path(state, path) do
    cancel_existing_timer(state.debounce_timers, path)
    ref = Process.send_after(self(), {:debounced_event, path}, @debounce_ms)
    %{state | debounce_timers: Map.put(state.debounce_timers, path, ref)}
  end

  defp cancel_existing_timer(timers, path) do
    case Map.get(timers, path) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
  end

  defp scan_known_files(plans_dir, projects_dir) do
    plan_files = scan_dir_files(plans_dir, "*.md")
    project_files = scan_project_files(projects_dir)
    Map.new(plan_files ++ project_files)
  end

  defp scan_project_files(projects_dir) when not is_binary(projects_dir), do: []

  defp scan_project_files(projects_dir) do
    case File.ls(projects_dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.map(&Path.join(projects_dir, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.flat_map(&scan_single_project/1)

      {:error, _} ->
        []
    end
  end

  defp scan_single_project(project_path) do
    memory_files = scan_dir_files(Path.join(project_path, "memory"), "*.md")
    claude_md = Path.join(project_path, "CLAUDE.md")

    if File.exists?(claude_md) do
      [{claude_md, mtime_posix(claude_md)} | memory_files]
    else
      memory_files
    end
  end

  defp scan_dir_files(dir, pattern) do
    if is_binary(dir) and File.dir?(dir) do
      Path.join(dir, pattern)
      |> Path.wildcard()
      |> Enum.map(fn path -> {path, mtime_posix(path)} end)
    else
      []
    end
  end

  defp mtime_posix(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime
      {:error, _} -> 0
    end
  end

  defp relevant_path?(path, plans_dir, projects_dir) do
    String.ends_with?(path, ".md") and
      (plan_path?(path, plans_dir) or project_path?(path, projects_dir))
  end

  defp plan_path?(path, plans_dir) do
    is_binary(plans_dir) and String.starts_with?(path, plans_dir) and
      Path.dirname(path) == plans_dir
  end

  defp project_path?(_path, projects_dir) when not is_binary(projects_dir), do: false

  defp project_path?(path, projects_dir) do
    if String.starts_with?(path, projects_dir) do
      path
      |> Path.relative_to(projects_dir)
      |> Path.split()
      |> project_subpath?()
    else
      false
    end
  end

  defp project_subpath?([_project, "memory", _file]), do: true
  defp project_subpath?([_project, "CLAUDE.md"]), do: true
  defp project_subpath?(_), do: false

  defp classify_path(path, plans_dir, projects_dir) do
    cond do
      plan_path?(path, plans_dir) ->
        {:plan, nil, Path.basename(path)}

      is_binary(projects_dir) and String.starts_with?(path, projects_dir) ->
        classify_project_path(path, projects_dir)

      true ->
        nil
    end
  end

  defp classify_project_path(path, projects_dir) do
    path
    |> Path.relative_to(projects_dir)
    |> Path.split()
    |> classify_project_parts()
  end

  defp classify_project_parts([project, "memory", file]),
    do: {:project_memory, project, "memory/" <> file}

  defp classify_project_parts([project, "CLAUDE.md"]),
    do: {:project_config, project, "CLAUDE.md"}

  defp classify_project_parts(_), do: nil

  defp determine_action(path, known_files) do
    existed? = Map.has_key?(known_files, path)
    exists_now? = File.exists?(path)

    case {existed?, exists_now?} do
      {false, true} -> :created
      {true, false} -> :deleted
      {true, true} -> :updated
      {false, false} -> :deleted
    end
  end

  defp update_known_file(known_files, path) do
    Map.put(known_files, path, mtime_posix(path))
  end

  defp event_id(path, %DateTime{} = dt) do
    data = path <> DateTime.to_iso8601(dt)
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  defp display_name(path, :plan) do
    Path.basename(path, ".md")
  end

  defp display_name(path, _category) do
    Path.basename(path, ".md")
  end
end
