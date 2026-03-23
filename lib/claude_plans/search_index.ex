defmodule ClaudePlans.SearchIndex do
  @moduledoc false
  use GenServer

  @refresh_interval :timer.seconds(30)
  @max_matches_per_file 3
  @max_results 20

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @type search_result :: %{
          source: :plan | :project,
          project: String.t() | nil,
          filename: String.t(),
          display_name: String.t(),
          rel_path: String.t(),
          path: String.t(),
          matches: [%{line_number: pos_integer(), line_text: String.t()}]
        }

  @doc "Search all indexed files for a case-insensitive substring match."
  @spec search(String.t()) :: [search_result()]
  def search(query) when is_binary(query) and byte_size(query) > 0 do
    GenServer.call(__MODULE__, {:search, query})
  end

  @spec search(any()) :: []
  def search(_), do: []

  # --- Server ---

  @impl true
  def init(_) do
    {:ok, _} = Registry.register(ClaudePlans.Registry, :plan_updates, [])
    Process.send_after(self(), :rebuild, 0)
    schedule_refresh()
    {:ok, %{entries: %{}}}
  end

  @impl true
  def handle_call({:search, query}, _from, state) do
    down_query = String.downcase(query)

    results =
      state.entries
      |> Map.values()
      |> Enum.reduce([], fn entry, acc ->
        matches =
          entry.content
          |> String.split("\n")
          |> Enum.with_index(1)
          |> Enum.filter(fn {line, _num} ->
            String.contains?(String.downcase(line), down_query)
          end)
          |> Enum.take(@max_matches_per_file)
          |> Enum.map(fn {line, num} ->
            %{line_number: num, line_text: String.trim(line) |> String.slice(0, 120)}
          end)

        if matches != [] do
          [Map.put(Map.delete(entry, :content), :matches, matches) | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()
      |> Enum.take(@max_results)

    {:reply, results, state}
  end

  @impl true
  def handle_info(:rebuild, _state) do
    {:noreply, %{entries: build_index()}}
  end

  def handle_info({:plan_updated, filename}, state) do
    {:noreply, %{state | entries: update_plan_entry(state.entries, filename)}}
  end

  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, %{state | entries: build_index()}}
  end

  # --- Index Building ---

  defp build_index do
    entries = plan_entries() ++ project_entries()
    Map.new(entries, fn entry -> {entry.path, entry} end)
  end

  defp update_plan_entry(entries, filename) do
    dir = ClaudePlans.plans_dir()
    path = if dir, do: Path.join(dir, filename), else: nil

    cond do
      is_nil(path) ->
        entries

      File.regular?(path) ->
        case File.read(path) do
          {:ok, content} ->
            entry = %{
              source: :plan,
              project: nil,
              filename: filename,
              display_name: String.replace_trailing(filename, ".md", ""),
              rel_path: filename,
              path: path,
              content: content
            }

            Map.put(entries, path, entry)

          {:error, _} ->
            Map.delete(entries, path)
        end

      true ->
        Map.delete(entries, path)
    end
  end

  defp plan_entries do
    dir = ClaudePlans.plans_dir()
    if dir && File.dir?(dir), do: read_plan_files(dir), else: []
  end

  defp read_plan_files(dir) do
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.flat_map(fn filename ->
      path = Path.join(dir, filename)

      case File.read(path) do
        {:ok, content} ->
          [
            %{
              source: :plan,
              project: nil,
              filename: filename,
              display_name: String.replace_trailing(filename, ".md", ""),
              rel_path: filename,
              path: path,
              content: content
            }
          ]

        {:error, _} ->
          []
      end
    end)
  end

  defp project_entries do
    dir = ClaudePlans.projects_dir()
    if dir && File.dir?(dir), do: read_project_dirs(dir), else: []
  end

  defp read_project_dirs(dir) do
    case File.ls(dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(fn d ->
          File.dir?(Path.join(dir, d)) and File.dir?(Path.join([dir, d, "memory"]))
        end)
        |> Enum.flat_map(fn proj_dir ->
          project_path = Path.join(dir, proj_dir)

          md_entries(project_path, proj_dir, nil) ++
            md_entries(Path.join(project_path, "memory"), proj_dir, "memory")
        end)

      {:error, _} ->
        []
    end
  end

  defp md_entries(scan_dir, proj_dir, subdir) do
    case File.ls(scan_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.flat_map(&read_md_entry(scan_dir, proj_dir, subdir, &1))

      {:error, _} ->
        []
    end
  end

  defp read_md_entry(scan_dir, proj_dir, subdir, filename) do
    rel_path = if subdir, do: Path.join(subdir, filename), else: filename
    path = Path.join(scan_dir, filename)

    case File.read(path) do
      {:ok, content} ->
        [
          %{
            source: :project,
            project: proj_dir,
            filename: filename,
            display_name: String.replace_trailing(filename, ".md", ""),
            rel_path: rel_path,
            path: path,
            content: content
          }
        ]

      {:error, _} ->
        []
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
