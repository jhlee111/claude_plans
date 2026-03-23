defmodule ClaudePlans.KeyboardNav do
  @moduledoc "Pure helpers for keyboard navigation index resolution."

  @spec resolve_index(String.t(), integer() | nil, non_neg_integer(), list()) ::
          non_neg_integer() | nil
  def resolve_index(direction, current, max_idx, list)

  def resolve_index(_dir, _current, _max_idx, []), do: nil
  def resolve_index("top", _current, _max_idx, _list), do: 0
  def resolve_index("bottom", _current, max_idx, _list), do: max_idx
  def resolve_index("down", nil, _max_idx, _list), do: 0
  def resolve_index("down", i, max_idx, _list) when i >= max_idx, do: max_idx
  def resolve_index("down", i, _max_idx, _list), do: i + 1
  def resolve_index("up", nil, max_idx, _list), do: max_idx
  def resolve_index("up", 0, _max_idx, _list), do: 0
  def resolve_index("up", i, _max_idx, _list), do: i - 1
end
