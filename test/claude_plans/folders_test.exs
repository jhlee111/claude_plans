defmodule ClaudePlans.FoldersTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.Folders

  @moduletag :tmp_dir

  describe "list_files/1" do
    test "returns dirs first then .md files", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "subdir"))
      File.write!(Path.join(tmp_dir, "notes.md"), "notes")
      File.write!(Path.join(tmp_dir, "skip.txt"), "skip")

      files = Folders.list_files(tmp_dir)

      types = Enum.map(files, & &1.type)
      assert types == [:dir, :file]

      names = Enum.map(files, & &1.name)
      assert "subdir" in names
      assert "notes.md" in names
      refute "skip.txt" in names
    end

    test "file entries include modified timestamp", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "test.md"), "content")

      [file] = Folders.list_files(tmp_dir)
      assert is_integer(file.modified)
      assert file.modified > 0
    end

    test "dir entries include modified timestamp", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "sub"))

      [dir] = Folders.list_files(tmp_dir)
      assert is_integer(dir.modified)
      assert dir.modified > 0
    end

    test "hidden files are excluded", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, ".hidden.md"), "secret")
      File.write!(Path.join(tmp_dir, "visible.md"), "ok")

      files = Folders.list_files(tmp_dir)
      names = Enum.map(files, & &1.name)
      refute ".hidden.md" in names
      assert "visible.md" in names
    end
  end

  describe "sort_files/2" do
    setup %{tmp_dir: tmp_dir} do
      # Create files with known modification order
      File.mkdir_p!(Path.join(tmp_dir, "dir_b"))
      File.mkdir_p!(Path.join(tmp_dir, "dir_a"))
      File.write!(Path.join(tmp_dir, "beta.md"), "b")
      Process.sleep(1100)
      File.write!(Path.join(tmp_dir, "alpha.md"), "a")

      {:ok, files: Folders.list_files(tmp_dir)}
    end

    test "name_asc sorts alphabetically, dirs first", %{files: files} do
      sorted = Folders.sort_files(files, :name_asc)
      {dirs, mds} = Enum.split_with(sorted, &(&1.type == :dir))

      assert Enum.map(dirs, & &1.name) == ["dir_a", "dir_b"]
      assert Enum.map(mds, & &1.name) == ["alpha.md", "beta.md"]
    end

    test "name_desc sorts reverse alphabetically, dirs first", %{files: files} do
      sorted = Folders.sort_files(files, :name_desc)
      {dirs, mds} = Enum.split_with(sorted, &(&1.type == :dir))

      assert Enum.map(dirs, & &1.name) == ["dir_b", "dir_a"]
      assert Enum.map(mds, & &1.name) == ["beta.md", "alpha.md"]
    end

    test "modified_desc sorts newest first, dirs first", %{files: files} do
      sorted = Folders.sort_files(files, :modified_desc)
      mds = Enum.filter(sorted, &(&1.type == :file))

      # alpha.md was created after beta.md
      assert hd(mds).name == "alpha.md"
    end

    test "modified_asc sorts oldest first", %{files: files} do
      sorted = Folders.sort_files(files, :modified_asc)
      mds = Enum.filter(sorted, &(&1.type == :file))

      assert hd(mds).name == "beta.md"
    end
  end
end
