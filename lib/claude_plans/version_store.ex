defmodule ClaudePlans.VersionStore do
  @moduledoc false
  use GenServer
  require Logger

  @type version_meta :: %{
          id: String.t(),
          hash: binary(),
          timestamp: DateTime.t(),
          byte_size: non_neg_integer()
        }

  @type version_entry :: %{
          id: String.t(),
          content: String.t(),
          hash: binary(),
          timestamp: DateTime.t(),
          byte_size: non_neg_integer()
        }

  @max_versions 50

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "List versions for a plan (no content — keeps messages small)."
  @spec list_versions(String.t()) :: [version_meta()]
  def list_versions(filename) do
    GenServer.call(__MODULE__, {:list_versions, filename})
  end

  @doc "Get a full version entry including content."
  @spec get_version(String.t(), String.t()) :: version_entry() | nil
  def get_version(filename, id) do
    GenServer.call(__MODULE__, {:get_version, filename, id})
  end

  @doc "Compute diff HTML between two versions of a plan."
  @spec diff(String.t(), String.t(), String.t()) :: String.t() | nil
  def diff(filename, id_a, id_b) do
    GenServer.call(__MODULE__, {:diff, filename, id_a, id_b})
  end

  @doc "Force-capture a snapshot of the current file."
  @spec snapshot(String.t()) :: :ok
  def snapshot(filename) do
    GenServer.cast(__MODULE__, {:snapshot, filename})
  end

  @doc "Snapshot an arbitrary file under a given version key."
  @spec snapshot_file(String.t(), String.t()) :: :ok
  def snapshot_file(version_key, file_path) do
    GenServer.cast(__MODULE__, {:snapshot_file, version_key, file_path})
  end

  @doc "Get the last-checked version id for a file, or nil."
  @spec get_checked_version(String.t()) :: String.t() | nil
  def get_checked_version(filename) do
    GenServer.call(__MODULE__, {:get_checked_version, filename})
  end

  @doc "Mark a file as checked at its latest version."
  @spec mark_checked(String.t()) :: :ok
  def mark_checked(filename) do
    GenServer.cast(__MODULE__, {:mark_checked, filename})
  end

  @doc "Returns a MapSet of filenames with unchecked changes."
  @spec unchecked_files() :: MapSet.t(String.t())
  def unchecked_files do
    GenServer.call(__MODULE__, :unchecked_files)
  end

  @doc """
  Snapshot the file, compute diff from the checked version (or previous version),
  and return `{diff_html, versions, checked_id}` in a single call.

  This avoids multiple sequential GenServer round-trips from LiveView event handlers.
  """
  @spec diff_since_checked(String.t()) :: {String.t() | nil, [version_meta()], String.t() | nil}
  def diff_since_checked(filename) do
    GenServer.call(__MODULE__, {:diff_since_checked, filename})
  end

  @doc """
  Given a checked version ID and version list, determine whether to show
  rendered or diff view, and compute the diff HTML if needed.

  Returns `{view_mode, diff_html, diff_version_a, diff_version_b}`.
  """
  @spec resolve_diff_state(String.t(), String.t() | nil, [version_meta()]) ::
          {:rendered | :diff, String.t() | nil, String.t() | nil, String.t() | nil}
  def resolve_diff_state(_filename, nil, _versions), do: {:rendered, nil, nil, nil}

  def resolve_diff_state(_filename, cid, [latest | _]) when cid == latest.id,
    do: {:rendered, nil, nil, nil}

  def resolve_diff_state(filename, cid, [latest | _] = vers) when length(vers) >= 2 do
    {diff_from, diff_to} = pick_diff_versions(cid, latest, vers)
    html = diff(filename, diff_from, diff_to)
    {:diff, html, diff_from, diff_to}
  end

  def resolve_diff_state(_filename, _checked_id, _versions), do: {:rendered, nil, nil, nil}

  defp pick_diff_versions(cid, latest, vers) do
    if Enum.any?(vers, &(&1.id == cid)) do
      {cid, latest.id}
    else
      [^latest, previous | _] = vers
      {previous.id, latest.id}
    end
  end

  # --- Server ---

  @impl true
  def init(_) do
    {:ok, _} = Registry.register(ClaudePlans.Registry, :plan_updates, [])

    versions = load_all_history()
    checked = load_checked_versions()

    # Snapshot all existing plans
    for plan <- ClaudePlans.Watcher.list_plans() do
      send(self(), {:snapshot_initial, plan.filename})
    end

    {:ok, %{versions: versions, checked_versions: checked}}
  end

  @impl true
  def handle_call({:list_versions, filename}, _from, state) do
    entries =
      state.versions
      |> Map.get(filename, [])
      |> Enum.map(fn v -> Map.drop(v, [:content]) end)

    {:reply, entries, state}
  end

  def handle_call({:get_version, filename, id}, _from, state) do
    entry =
      state.versions
      |> Map.get(filename, [])
      |> Enum.find(&(&1.id == id))

    {:reply, entry, state}
  end

  def handle_call({:diff, filename, id_a, id_b}, _from, state) do
    file_versions = Map.get(state.versions, filename, [])
    va = Enum.find(file_versions, &(&1.id == id_a))
    vb = Enum.find(file_versions, &(&1.id == id_b))

    html =
      if va && vb do
        ClaudePlans.Diff.compute(va.content, vb.content)
        |> ClaudePlans.Diff.to_html()
      else
        nil
      end

    {:reply, html, state}
  end

  def handle_call({:get_checked_version, filename}, _from, state) do
    {:reply, Map.get(state.checked_versions, filename), state}
  end

  def handle_call({:diff_since_checked, filename}, _from, state) do
    # Snapshot first (in-process, no extra GenServer call)
    path = Path.join(ClaudePlans.plans_dir(), filename)
    state = do_snapshot(state, filename, path)
    versions = Map.get(state.versions, filename, [])
    checked_id = Map.get(state.checked_versions, filename)

    versions_meta = Enum.map(versions, &Map.drop(&1, [:content]))

    diff_html =
      case {checked_id, versions} do
        {nil, [_latest, previous | _]} ->
          [latest | _] = versions
          do_diff(versions, previous.id, latest.id)

        {cid, [latest | _]} when cid == latest.id and length(versions) >= 2 ->
          [_, previous | _] = versions
          do_diff(versions, previous.id, latest.id)

        {cid, [latest | _]} when length(versions) >= 2 ->
          if Enum.any?(versions, &(&1.id == cid)) do
            do_diff(versions, cid, latest.id)
          else
            [_, previous | _] = versions
            do_diff(versions, previous.id, latest.id)
          end

        _ ->
          nil
      end

    {:reply, {diff_html, versions_meta, checked_id}, state}
  end

  def handle_call(:unchecked_files, _from, state) do
    unchecked =
      state.versions
      |> Enum.reduce(MapSet.new(), fn {filename, [latest | _]}, acc ->
        checked_id = Map.get(state.checked_versions, filename)

        if checked_id != latest.id do
          MapSet.put(acc, filename)
        else
          acc
        end
      end)

    {:reply, unchecked, state}
  end

  @impl true
  def handle_cast({:snapshot, filename}, state) do
    path = Path.join(ClaudePlans.plans_dir(), filename)
    {:noreply, do_snapshot(state, filename, path)}
  end

  def handle_cast({:snapshot_file, key, path}, state) do
    {:noreply, do_snapshot(state, key, path)}
  end

  def handle_cast({:mark_checked, filename}, state) do
    case Map.get(state.versions, filename, []) do
      [latest | _] ->
        checked = Map.put(state.checked_versions, filename, latest.id)
        persist_checked_versions(checked)
        {:noreply, %{state | checked_versions: checked}}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:plan_updated, filename}, state) do
    path = Path.join(ClaudePlans.plans_dir(), filename)
    {:noreply, do_snapshot(state, filename, path)}
  end

  @impl true
  def handle_info({:snapshot_initial, filename}, state) do
    path = Path.join(ClaudePlans.plans_dir(), filename)
    {:noreply, do_snapshot(state, filename, path)}
  end

  # --- Internal ---

  defp do_diff(versions, id_a, id_b) do
    va = Enum.find(versions, &(&1.id == id_a))
    vb = Enum.find(versions, &(&1.id == id_b))

    if va && vb do
      ClaudePlans.Diff.compute(va.content, vb.content)
      |> ClaudePlans.Diff.to_html()
    end
  end

  defp do_snapshot(state, key, path) do
    case File.read(path) do
      {:ok, content} ->
        hash = :crypto.hash(:sha256, content)
        existing = Map.get(state.versions, key, [])

        if existing != [] && hd(existing).hash == hash do
          state
        else
          id = hash |> Base.encode16(case: :lower) |> binary_part(0, 8)

          entry = %{
            id: id,
            content: content,
            hash: hash,
            timestamp: DateTime.utc_now(),
            byte_size: byte_size(content)
          }

          updated = [entry | existing] |> Enum.take(@max_versions)
          new_versions = Map.put(state.versions, key, updated)
          persist_history(key, updated)
          %{state | versions: new_versions}
        end

      {:error, _} ->
        state
    end
  end

  # --- Persistence ---

  defp history_dir do
    Path.join(ClaudePlans.plans_dir(), ".history")
  end

  defp history_path(filename) do
    Path.join(history_dir(), "#{filename}.history.json")
  end

  defp persist_history(filename, versions) do
    dir = history_dir()
    File.mkdir_p!(dir)

    data =
      Enum.map(versions, fn v ->
        %{
          "id" => v.id,
          "content" => v.content,
          "timestamp" => DateTime.to_iso8601(v.timestamp),
          "byte_size" => v.byte_size
        }
      end)

    File.write!(history_path(filename), Jason.encode!(data))
  rescue
    e in [File.Error, Jason.EncodeError] ->
      Logger.warning("[VersionStore] Failed to persist history for #{filename}: #{inspect(e)}")
  end

  defp load_all_history do
    dir = history_dir()

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".history.json"))
        |> Map.new(&load_history_entry(dir, &1))
        |> Map.reject(fn {_k, v} -> v == :error end)

      {:error, _} ->
        %{}
    end
  end

  defp load_history_entry(dir, file) do
    filename = String.replace_trailing(file, ".history.json", "")
    path = Path.join(dir, file)

    case load_history_file(path) do
      {:ok, versions} -> {filename, versions}
      :error -> {filename, :error}
    end
  end

  defp load_history_file(path) do
    with {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json) do
      versions =
        Enum.map(data, fn entry ->
          content = entry["content"]
          hash = :crypto.hash(:sha256, content)

          %{
            id: entry["id"],
            content: content,
            hash: hash,
            timestamp: parse_timestamp(entry["timestamp"]),
            byte_size: entry["byte_size"]
          }
        end)

      {:ok, versions}
    else
      _ -> :error
    end
  end

  defp parse_timestamp(iso_str) do
    case DateTime.from_iso8601(iso_str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp checked_versions_path do
    Path.join(history_dir(), ".checked_versions.json")
  end

  defp persist_checked_versions(checked) do
    dir = history_dir()
    File.mkdir_p!(dir)
    File.write!(checked_versions_path(), Jason.encode!(checked))
  rescue
    e in [File.Error, Jason.EncodeError] ->
      Logger.warning("[VersionStore] Failed to persist checked versions: #{inspect(e)}")
  end

  defp load_checked_versions do
    path = checked_versions_path()

    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end
end
