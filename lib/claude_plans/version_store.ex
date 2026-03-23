defmodule ClaudePlans.VersionStore do
  @moduledoc false
  use GenServer
  require Logger

  @max_versions 50

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "List versions for a plan (no content — keeps messages small)."
  def list_versions(filename) do
    GenServer.call(__MODULE__, {:list_versions, filename})
  end

  @doc "Get a full version entry including content."
  def get_version(filename, id) do
    GenServer.call(__MODULE__, {:get_version, filename, id})
  end

  @doc "Compute diff HTML between two versions of a plan."
  def diff(filename, id_a, id_b) do
    GenServer.call(__MODULE__, {:diff, filename, id_a, id_b})
  end

  @doc "Force-capture a snapshot of the current file."
  def snapshot(filename) do
    GenServer.cast(__MODULE__, {:snapshot, filename})
  end

  @doc "Get the last-checked version id for a file, or nil."
  def get_checked_version(filename) do
    GenServer.call(__MODULE__, {:get_checked_version, filename})
  end

  @doc "Mark a file as checked at its latest version."
  def mark_checked(filename) do
    GenServer.cast(__MODULE__, {:mark_checked, filename})
  end

  @doc "Returns a MapSet of filenames with unchecked changes."
  def unchecked_files do
    GenServer.call(__MODULE__, :unchecked_files)
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
    {:noreply, do_snapshot(state, filename)}
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
    {:noreply, do_snapshot(state, filename)}
  end

  def handle_info({:snapshot_initial, filename}, state) do
    {:noreply, do_snapshot(state, filename)}
  end

  # --- Internal ---

  defp do_snapshot(state, filename) do
    path = Path.join(ClaudePlans.plans_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        hash = :crypto.hash(:sha256, content)
        existing = Map.get(state.versions, filename, [])

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
          new_versions = Map.put(state.versions, filename, updated)
          persist_history(filename, updated)
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
    e ->
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
    e ->
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
