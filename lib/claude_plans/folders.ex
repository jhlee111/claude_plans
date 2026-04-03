defmodule ClaudePlans.Folders do
  @moduledoc "Config management and file listing for custom folder directories."

  require Logger

  @type folder :: %{id: String.t(), path: String.t(), name: String.t()}
  @type file_entry :: %{
          name: String.t(),
          rel_path: String.t(),
          full_path: String.t(),
          modified: integer()
        }

  @doc "List all configured folders, filtering out deleted/inaccessible ones."
  @spec list() :: [folder()]
  def list do
    case load_config() do
      {:ok, folders} ->
        Enum.filter(folders, fn f -> File.dir?(f.path) end)

      :error ->
        []
    end
  end

  @doc "Add a new folder to the config."
  @spec add(String.t()) :: {:ok, folder()} | {:error, atom()}
  def add(path) do
    path = Path.expand(path)

    with :ok <- validate_exists(path),
         :ok <- validate_directory(path),
         :ok <- validate_readable(path),
         :ok <- validate_not_duplicate(path) do
      folder = %{
        id: generate_id(path),
        path: path,
        name: display_name(path)
      }

      folders = list() ++ [folder]
      persist_config(folders)
      {:ok, folder}
    end
  end

  @doc "Remove a folder from the config by id."
  @spec remove(String.t()) :: :ok
  def remove(id) do
    folders = list() |> Enum.reject(&(&1.id == id))
    persist_config(folders)
  end

  @doc "List subdirectories and .md files in a folder (non-recursive). Dirs first, then files."
  @spec list_files(String.t()) :: [file_entry()]
  def list_files(folder_path) do
    case File.ls(folder_path) do
      {:ok, entries} ->
        {dirs, files} =
          entries
          |> Enum.filter(fn name -> not String.starts_with?(name, ".") end)
          |> Enum.sort()
          |> Enum.split_with(fn name -> File.dir?(Path.join(folder_path, name)) end)

        dir_entries =
          dirs
          |> Enum.map(fn name ->
            full = Path.join(folder_path, name)
            %{name: name, rel_path: name, full_path: full, type: :dir, modified: file_mtime(full)}
          end)

        file_entries =
          files
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.map(fn name ->
            full = Path.join(folder_path, name)

            %{
              name: name,
              rel_path: name,
              full_path: full,
              type: :file,
              modified: file_mtime(full)
            }
          end)

        dir_entries ++ file_entries

      {:error, _} ->
        []
    end
  end

  @doc "Generate a VersionStore key for a file path."
  @spec version_key(String.t()) :: String.t()
  def version_key(full_path) do
    hash =
      :crypto.hash(:sha256, full_path)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "folder--#{hash}"
  end

  @doc "Validate a path for the add folder form (phx-change)."
  @spec validate_path(String.t()) :: :ok | {:error, String.t()}
  def validate_path(path) do
    path = Path.expand(path)

    cond do
      path == "" -> {:error, "Path is required"}
      not File.exists?(path) -> {:error, "Directory not found"}
      not File.dir?(path) -> {:error, "Not a directory"}
      not readable?(path) -> {:error, "No read permission"}
      duplicate?(path) -> {:error, "Already added"}
      true -> :ok
    end
  end

  @doc "Generate a display name for a path."
  @spec display_name_for(String.t()) :: String.t()
  def display_name_for(path), do: display_name(path)

  # --- Internal ---

  defp config_dir do
    Path.join(ClaudePlans.plans_dir(), ".config")
  end

  defp config_path do
    Path.join(config_dir(), "custom_folders.json")
  end

  defp load_config do
    case File.read(config_path()) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, list} when is_list(list) ->
            folders =
              Enum.map(list, fn entry ->
                %{
                  id: entry["id"],
                  path: entry["path"],
                  name: entry["name"]
                }
              end)

            {:ok, folders}

          _ ->
            :error
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, _} ->
        :error
    end
  end

  defp persist_config(folders) do
    dir = config_dir()
    File.mkdir_p!(dir)

    data =
      Enum.map(folders, fn f ->
        %{"id" => f.id, "path" => f.path, "name" => f.name}
      end)

    File.write!(config_path(), Jason.encode!(data, pretty: true))
  rescue
    e ->
      Logger.warning("[Folders] Failed to persist config: #{inspect(e)}")
  end

  defp generate_id(path) do
    :crypto.hash(:sha256, path)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  defp file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  @doc "Sort file entries by the given mode. Directories always come first."
  @spec sort_files([file_entry()], atom()) :: [file_entry()]
  def sort_files(entries, mode) do
    {dirs, files} = Enum.split_with(entries, &(&1.type == :dir))
    sorted_dirs = do_sort(dirs, mode)
    sorted_files = do_sort(files, mode)
    sorted_dirs ++ sorted_files
  end

  defp do_sort(entries, :name_asc), do: Enum.sort_by(entries, & &1.name)
  defp do_sort(entries, :name_desc), do: Enum.sort_by(entries, & &1.name, :desc)
  defp do_sort(entries, :modified_desc), do: Enum.sort_by(entries, & &1.modified, :desc)
  defp do_sort(entries, :modified_asc), do: Enum.sort_by(entries, & &1.modified, :asc)
  defp do_sort(entries, _), do: entries

  defp display_name(path) do
    home = System.user_home!()

    rel =
      if String.starts_with?(path, home) do
        Path.relative_to(path, home)
      else
        path
      end

    # Show last 2 path components for readability in dropdown
    parts = Path.split(rel)

    case parts do
      [] -> Path.basename(path)
      [single] -> single
      _ -> Enum.take(parts, -2) |> Path.join()
    end
  end

  defp validate_exists(path) do
    if File.exists?(path), do: :ok, else: {:error, :not_found}
  end

  defp validate_directory(path) do
    if File.dir?(path), do: :ok, else: {:error, :not_directory}
  end

  defp validate_readable(path) do
    if readable?(path), do: :ok, else: {:error, :no_permission}
  end

  defp validate_not_duplicate(path) do
    if duplicate?(path), do: {:error, :already_added}, else: :ok
  end

  defp readable?(path) do
    case File.stat(path) do
      {:ok, %{access: access}} when access in [:read, :read_write] -> true
      _ -> false
    end
  end

  defp duplicate?(path) do
    Enum.any?(list(), fn f -> f.path == path end)
  end
end
