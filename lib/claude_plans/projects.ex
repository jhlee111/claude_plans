defmodule ClaudePlans.Projects do
  @moduledoc "Filesystem operations for Claude project directories."

  @type project_entry :: %{
          dir_name: String.t(),
          display_name: String.t(),
          has_memory?: boolean()
        }

  @type file_entry :: %{
          name: String.t(),
          dir: String.t() | nil,
          rel_path: String.t()
        }

  @spec list(String.t()) :: [project_entry()]
  def list(projects_dir) do
    projects_dir
    |> File.ls()
    |> case do
      {:ok, dirs} -> dirs
      {:error, _} -> []
    end
    |> Enum.filter(&File.dir?(Path.join(projects_dir, &1)))
    |> Enum.map(&build_entry(projects_dir, &1))
    |> Enum.filter(& &1.has_memory?)
    |> Enum.sort_by(& &1.display_name)
  end

  @spec display_name(String.t()) :: String.t()
  def display_name(dir_name) do
    candidate = "/" <> (dir_name |> String.trim_leading("-") |> String.replace("-", "/"))

    if File.dir?(candidate) do
      Path.relative_to(candidate, System.user_home!()) |> then(&"~/#{&1}")
    else
      dir_name |> String.trim_leading("-Users-#{System.get_env("USER", "user")}-")
    end
  end

  @spec list_files(String.t(), String.t()) :: [file_entry()]
  def list_files(projects_dir, dir_name) do
    project_path = Path.join(projects_dir, dir_name)
    root_files = list_md_files(project_path, nil)
    memory_files = list_md_files(Path.join(project_path, "memory"), "memory")
    (root_files ++ memory_files) |> Enum.sort_by(fn f -> {f.dir || "", f.name} end)
  end

  defp build_entry(projects_dir, dir_name) do
    %{
      dir_name: dir_name,
      display_name: display_name(dir_name),
      has_memory?: File.dir?(Path.join([projects_dir, dir_name, "memory"]))
    }
  end

  defp list_md_files(dir, subdir) do
    dir
    |> File.ls()
    |> case do
      {:ok, files} -> files
      {:error, _} -> []
    end
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(&md_file_entry(&1, subdir))
  end

  defp md_file_entry(name, nil), do: %{name: name, dir: nil, rel_path: name}

  defp md_file_entry(name, subdir),
    do: %{name: name, dir: subdir, rel_path: Path.join(subdir, name)}

  @doc "Generate a VersionStore key for a project file path."
  @spec version_key(String.t()) :: String.t()
  def version_key(full_path) do
    hash =
      :crypto.hash(:sha256, full_path)
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "project--#{hash}"
  end
end
