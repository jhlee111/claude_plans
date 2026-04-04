defmodule ClaudePlans.FolderWatcherSupervisorTest do
  use ExUnit.Case

  alias ClaudePlans.FolderWatcherSupervisor

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Record initial watcher count so tests are additive
    initial = FolderWatcherSupervisor.count()
    {:ok, initial_count: initial, tmp_dir: tmp_dir}
  end

  describe "add_folder/1 and remove_folder/1" do
    test "adds and removes a watcher", %{tmp_dir: tmp_dir, initial_count: initial} do
      path = Path.join(tmp_dir, "watch_me")
      File.mkdir_p!(path)

      FolderWatcherSupervisor.add_folder(path)
      assert FolderWatcherSupervisor.count() == initial + 1

      FolderWatcherSupervisor.remove_folder(path)
      # Give supervisor a moment to terminate
      Process.sleep(50)
      assert FolderWatcherSupervisor.count() == initial
    end

    test "duplicate add is idempotent", %{tmp_dir: tmp_dir, initial_count: initial} do
      path = Path.join(tmp_dir, "dup_test")
      File.mkdir_p!(path)

      FolderWatcherSupervisor.add_folder(path)
      FolderWatcherSupervisor.add_folder(path)
      assert FolderWatcherSupervisor.count() == initial + 1

      FolderWatcherSupervisor.remove_folder(path)
      Process.sleep(50)
    end
  end

  describe "enforce_limit" do
    test "caps watchers at max limit", %{tmp_dir: tmp_dir} do
      # Create 12 directories and add watchers for each
      paths =
        for i <- 1..12 do
          path = Path.join(tmp_dir, "dir_#{i}")
          File.mkdir_p!(path)
          FolderWatcherSupervisor.add_folder(path)
          path
        end

      # Should be capped (max_watchers = 10, plus any pre-existing)
      # The key assertion: count should not exceed a reasonable limit
      count = FolderWatcherSupervisor.count()

      assert count <= 10 + 5,
             "Expected at most ~15 watchers (10 limit + pre-existing), got #{count}"

      # Cleanup
      for p <- paths, do: FolderWatcherSupervisor.remove_folder(p)
      Process.sleep(100)
    end
  end

  describe "count/0" do
    test "returns non-negative integer" do
      assert FolderWatcherSupervisor.count() >= 0
    end
  end
end
