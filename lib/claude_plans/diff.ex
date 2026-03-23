defmodule ClaudePlans.Diff do
  @moduledoc false

  @context_lines 3
  @collapse_threshold 6

  @doc "Compute myers diff between two strings, returns list of {:eq|:ins|:del, [lines]}."
  def compute(old, new) when is_binary(old) and is_binary(new) do
    List.myers_difference(String.split(old, "\n"), String.split(new, "\n"))
  end

  @doc "Convert diff ops to an HTML string with line numbers and hunk collapsing."
  def to_html(diff_ops) do
    diff_ops
    |> flatten_lines()
    |> collapse_equal_runs()
    |> render_html()
  end

  # Flatten ops into tagged lines with line number counters
  defp flatten_lines(ops) do
    {lines, _old_ln, _new_ln} =
      Enum.reduce(ops, {[], 1, 1}, fn {op, texts}, {acc, old_ln, new_ln} ->
        Enum.reduce(texts, {acc, old_ln, new_ln}, fn text, {acc2, o, n} ->
          tag_line(op, text, acc2, o, n)
        end)
      end)

    Enum.reverse(lines)
  end

  defp tag_line(:eq, text, acc, old_ln, new_ln),
    do: {[{:eq, old_ln, new_ln, text} | acc], old_ln + 1, new_ln + 1}

  defp tag_line(:del, text, acc, old_ln, new_ln),
    do: {[{:del, old_ln, nil, text} | acc], old_ln + 1, new_ln}

  defp tag_line(:ins, text, acc, old_ln, new_ln),
    do: {[{:ins, nil, new_ln, text} | acc], old_ln, new_ln + 1}

  # Collapse long equal runs into context + hunk separator + context
  defp collapse_equal_runs(lines) do
    lines
    |> chunk_by_type()
    |> Enum.flat_map(fn
      {:eq, eq_lines} when length(eq_lines) > @collapse_threshold ->
        before = Enum.take(eq_lines, @context_lines)
        after_lines = Enum.take(eq_lines, -@context_lines)
        hidden = length(eq_lines) - @context_lines * 2

        if hidden > 0 do
          before ++ [{:hunk, hidden}] ++ after_lines
        else
          eq_lines
        end

      {_type, chunk_lines} ->
        chunk_lines
    end)
  end

  defp chunk_by_type(lines) do
    lines
    |> Enum.chunk_by(fn
      {:hunk, _} -> :hunk
      {type, _, _, _} -> type
    end)
    |> Enum.map(fn chunk ->
      case hd(chunk) do
        {:hunk, _} -> {:hunk, chunk}
        {type, _, _, _} -> {type, chunk}
      end
    end)
  end

  defp render_html(lines) do
    inner =
      Enum.map_join(lines, "\n", fn
        {:hunk, count} ->
          ~s(<div class="cb-diff-hunk">... #{count} unchanged lines ...</div>)

        {type, old_ln, new_ln, text} ->
          type_class = Atom.to_string(type)
          old_str = if old_ln, do: Integer.to_string(old_ln), else: ""
          new_str = if new_ln, do: Integer.to_string(new_ln), else: ""
          escaped = escape_html(text)

          ~s(<div class="cb-diff-line cb-diff-#{type_class}">) <>
            ~s(<span class="cb-diff-ln">#{old_str}</span>) <>
            ~s(<span class="cb-diff-ln">#{new_str}</span>) <>
            ~s(<span class="cb-diff-text">#{escaped}</span>) <>
            ~s(</div>)
      end)

    ~s(<div class="cb-diff">#{inner}</div>)
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
