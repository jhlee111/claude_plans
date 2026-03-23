defmodule ClaudePlans.VersionStoreTest do
  use ExUnit.Case

  alias ClaudePlans.VersionStore

  describe "resolve_diff_state/3" do
    test "returns :rendered when checked_id is nil" do
      assert {:rendered, nil, nil, nil} =
               VersionStore.resolve_diff_state("plan.md", nil, [%{id: "abc"}])
    end

    test "returns :rendered when checked_id matches latest version" do
      versions = [%{id: "v2"}, %{id: "v1"}]

      assert {:rendered, nil, nil, nil} =
               VersionStore.resolve_diff_state("plan.md", "v2", versions)
    end

    test "returns :rendered when fewer than 2 versions" do
      assert {:rendered, nil, nil, nil} =
               VersionStore.resolve_diff_state("plan.md", "old", [%{id: "v1"}])
    end

    test "returns :diff with checked version as base when it exists in versions" do
      # We need the VersionStore GenServer running for the diff call.
      # Since it's already started by the application, snapshot a test file first.
      filename = "test-resolve-diff-#{System.unique_integer([:positive])}.md"
      plans_dir = ClaudePlans.plans_dir()
      path = Path.join(plans_dir, filename)

      # Write two versions
      File.write!(path, "version 1 content")
      VersionStore.snapshot(filename)
      Process.sleep(10)

      File.write!(path, "version 2 content")
      VersionStore.snapshot(filename)
      Process.sleep(10)

      versions = VersionStore.list_versions(filename)
      assert length(versions) >= 2

      [latest, previous | _] = versions

      # Use previous.id as checked — should diff from previous to latest
      {mode, html, from, to} =
        VersionStore.resolve_diff_state(filename, previous.id, versions)

      assert mode == :diff
      assert is_binary(html)
      assert from == previous.id
      assert to == latest.id

      # Cleanup
      File.rm(path)
    end

    test "returns :diff with fallback versions when checked_id not in list" do
      filename = "test-resolve-fallback-#{System.unique_integer([:positive])}.md"
      plans_dir = ClaudePlans.plans_dir()
      path = Path.join(plans_dir, filename)

      File.write!(path, "first version")
      VersionStore.snapshot(filename)
      Process.sleep(10)

      File.write!(path, "second version")
      VersionStore.snapshot(filename)
      Process.sleep(10)

      versions = VersionStore.list_versions(filename)
      [latest, previous | _] = versions

      # Use a non-existent checked_id — should fall back to previous vs latest
      {mode, html, from, to} =
        VersionStore.resolve_diff_state(filename, "nonexistent-id", versions)

      assert mode == :diff
      assert is_binary(html)
      assert from == previous.id
      assert to == latest.id

      File.rm(path)
    end
  end
end
