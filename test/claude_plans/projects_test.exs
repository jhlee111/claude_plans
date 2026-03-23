defmodule ClaudePlans.ProjectsTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.Projects

  @moduletag :tmp_dir

  describe "list/1" do
    test "returns projects that have a memory directory", %{tmp_dir: tmp_dir} do
      # Project with memory dir
      File.mkdir_p!(Path.join([tmp_dir, "project-a", "memory"]))
      # Project without memory dir
      File.mkdir_p!(Path.join(tmp_dir, "project-b"))
      # A regular file, not a dir
      File.write!(Path.join(tmp_dir, "not-a-project.txt"), "")

      results = Projects.list(tmp_dir)

      assert length(results) == 1
      assert hd(results).dir_name == "project-a"
      assert hd(results).has_memory? == true
    end

    test "returns sorted by display_name", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join([tmp_dir, "zzz-project", "memory"]))
      File.mkdir_p!(Path.join([tmp_dir, "aaa-project", "memory"]))

      results = Projects.list(tmp_dir)
      names = Enum.map(results, & &1.display_name)

      assert names == Enum.sort(names)
    end

    test "returns empty list for missing directory" do
      assert Projects.list("/nonexistent/path/#{System.unique_integer()}") == []
    end
  end

  describe "list_files/2" do
    test "returns root and memory .md files sorted", %{tmp_dir: tmp_dir} do
      project = "my-project"
      project_dir = Path.join(tmp_dir, project)
      memory_dir = Path.join(project_dir, "memory")
      File.mkdir_p!(memory_dir)

      File.write!(Path.join(project_dir, "CLAUDE.md"), "config")
      File.write!(Path.join(project_dir, "README.md"), "readme")
      File.write!(Path.join(project_dir, "not-md.txt"), "skip")
      File.write!(Path.join(memory_dir, "notes.md"), "notes")
      File.write!(Path.join(memory_dir, "tasks.md"), "tasks")

      files = Projects.list_files(tmp_dir, project)

      names = Enum.map(files, & &1.name)
      assert "CLAUDE.md" in names
      assert "README.md" in names
      assert "notes.md" in names
      assert "tasks.md" in names
      refute "not-md.txt" in names

      # Memory files have dir set
      memory_files = Enum.filter(files, &(&1.dir == "memory"))
      assert length(memory_files) == 2

      # Root files have nil dir
      root_files = Enum.filter(files, &is_nil(&1.dir))
      assert length(root_files) == 2
    end

    test "returns empty list when project dir doesn't exist", %{tmp_dir: tmp_dir} do
      assert Projects.list_files(tmp_dir, "nonexistent") == []
    end
  end

  describe "display_name/1" do
    test "strips user prefix from directory name" do
      user = System.get_env("USER", "user")
      dir_name = "-Users-#{user}-Dev-my-project"

      result = Projects.display_name(dir_name)
      assert result == "Dev-my-project"
    end
  end
end
