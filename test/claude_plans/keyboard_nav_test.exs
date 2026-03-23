defmodule ClaudePlans.KeyboardNavTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.KeyboardNav

  @items [:a, :b, :c, :d, :e]
  @max_idx 4

  describe "resolve_index/4" do
    test "returns nil for empty list" do
      assert KeyboardNav.resolve_index("down", nil, 0, []) == nil
      assert KeyboardNav.resolve_index("up", 0, 0, []) == nil
      assert KeyboardNav.resolve_index("top", nil, 0, []) == nil
      assert KeyboardNav.resolve_index("bottom", nil, 0, []) == nil
    end

    test "top always returns 0" do
      assert KeyboardNav.resolve_index("top", nil, @max_idx, @items) == 0
      assert KeyboardNav.resolve_index("top", 3, @max_idx, @items) == 0
    end

    test "bottom always returns max_idx" do
      assert KeyboardNav.resolve_index("bottom", nil, @max_idx, @items) == @max_idx
      assert KeyboardNav.resolve_index("bottom", 0, @max_idx, @items) == @max_idx
    end

    test "down from nil starts at 0" do
      assert KeyboardNav.resolve_index("down", nil, @max_idx, @items) == 0
    end

    test "down increments index" do
      assert KeyboardNav.resolve_index("down", 0, @max_idx, @items) == 1
      assert KeyboardNav.resolve_index("down", 2, @max_idx, @items) == 3
    end

    test "down clamps at max_idx" do
      assert KeyboardNav.resolve_index("down", @max_idx, @max_idx, @items) == @max_idx
      assert KeyboardNav.resolve_index("down", @max_idx + 1, @max_idx, @items) == @max_idx
    end

    test "up from nil starts at max_idx" do
      assert KeyboardNav.resolve_index("up", nil, @max_idx, @items) == @max_idx
    end

    test "up decrements index" do
      assert KeyboardNav.resolve_index("up", 3, @max_idx, @items) == 2
      assert KeyboardNav.resolve_index("up", 1, @max_idx, @items) == 0
    end

    test "up clamps at 0" do
      assert KeyboardNav.resolve_index("up", 0, @max_idx, @items) == 0
    end
  end
end
