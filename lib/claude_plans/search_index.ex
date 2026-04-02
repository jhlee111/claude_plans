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
          source: :plan | :project | :folder,
          project: String.t() | nil,
          folder_id: String.t() | nil,
          folder_name: String.t() | nil,
          filename: String.t(),
          display_name: String.t(),
          rel_path: String.t(),
          path: String.t(),
          modified_at: integer() | nil,
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
    {:ok, _} = Registry.register(ClaudePlans.Registry, :folder_updates, [])
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
      |> Enum.sort_by(& &1.modified_at, :desc)
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

  def handle_info({:folder_file_updated, _watched_path, file_path}, state) do
    {:noreply, %{state | entries: update_folder_entry(state.entries, file_path)}}
  end

  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, %{state | entries: build_index()}}
  end

  # --- Index Building ---

  defp build_index do
    entries = plan_entries() ++ project_entries() ++ folder_entries()
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
              modified_at: file_mtime(path),
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
              modified_at: file_mtime(path),
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
            modified_at: file_mtime(path),
            content: content
          }
        ]

      {:error, _} ->
        []
    end
  end

  defp folder_entries do
    ClaudePlans.Folders.list()
    |> Enum.flat_map(fn folder ->
      read_folder_files_recursive(folder.path, folder.path, folder.id, folder.name)
    end)
  end

  defp read_folder_files_recursive(scan_dir, root_path, folder_id, folder_name) do
    case File.ls(scan_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn name -> not String.starts_with?(name, ".") end)
        |> Enum.flat_map(fn name ->
          full = Path.join(scan_dir, name)

          cond do
            File.dir?(full) ->
              read_folder_files_recursive(full, root_path, folder_id, folder_name)

            String.ends_with?(name, ".md") ->
              rel_path = Path.relative_to(full, root_path)

              case File.read(full) do
                {:ok, content} ->
                  [
                    %{
                      source: :folder,
                      project: nil,
                      folder_id: folder_id,
                      folder_name: folder_name,
                      filename: name,
                      display_name: String.replace_trailing(name, ".md", ""),
                      rel_path: rel_path,
                      path: full,
                      modified_at: file_mtime(full),
                      content: content
                    }
                  ]

                {:error, _} ->
                  []
              end

            true ->
              []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp update_folder_entry(entries, file_path) do
    if String.ends_with?(file_path, ".md") and File.regular?(file_path) do
      folder = find_folder_for_path(file_path)

      case {folder, File.read(file_path)} do
        {{folder_id, folder_name, root_path}, {:ok, content}} ->
          rel_path = Path.relative_to(file_path, root_path)

          entry = %{
            source: :folder,
            project: nil,
            folder_id: folder_id,
            folder_name: folder_name,
            filename: Path.basename(file_path),
            display_name: String.replace_trailing(Path.basename(file_path), ".md", ""),
            rel_path: rel_path,
            path: file_path,
            modified_at: file_mtime(file_path),
            content: content
          }

          Map.put(entries, file_path, entry)

        _ ->
          Map.delete(entries, file_path)
      end
    else
      Map.delete(entries, file_path)
    end
  end

  defp find_folder_for_path(file_path) do
    Enum.find_value(ClaudePlans.Folders.list(), fn folder ->
      if String.starts_with?(file_path, folder.path <> "/") do
        {folder.id, folder.name, folder.path}
      end
    end)
  end

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      {:error, _} -> nil
    end
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
