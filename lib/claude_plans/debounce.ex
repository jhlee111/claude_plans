defmodule ClaudePlans.Debounce do
  @moduledoc """
  Shared debounce helpers for GenServers that receive file system events.

  Manages a map of `path => timer_ref` in the caller's state, cancelling
  previous timers before scheduling new ones.
  """

  @doc """
  Debounce a message for a given path. Cancels any existing timer for
  that path, then schedules `message` to be sent after `delay_ms`.

  Returns the updated timers map.
  """
  @spec debounce(map(), String.t(), term(), non_neg_integer()) :: map()
  def debounce(timers, path, message, delay_ms) do
    cancel(timers, path)
    ref = Process.send_after(self(), message, delay_ms)
    Map.put(timers, path, ref)
  end

  @doc "Remove a path from the timers map (after the debounced message fires)."
  @spec clear(map(), String.t()) :: map()
  def clear(timers, path) do
    Map.delete(timers, path)
  end

  defp cancel(timers, path) do
    case Map.get(timers, path) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end
  end
end
