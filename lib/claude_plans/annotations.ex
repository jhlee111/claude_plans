defmodule ClaudePlans.Annotations do
  @moduledoc "Pure functions for annotation text manipulation in plan files."

  @separator "\n---\n<!-- Annotations by developer -->\n"

  @spec inject(String.t(), [map()]) :: String.t()
  def inject(content, annotations) do
    clean = strip(content)

    lines =
      Enum.map(annotations, fn ann ->
        direction = String.trim(ann.direction)

        if direction == "" do
          "<!-- #{ann.id} (#{ann.block_path}) -->"
        else
          "<!-- #{ann.id} (#{ann.block_path}): #{direction} -->"
        end
      end)

    clean <> @separator <> Enum.join(lines, "\n") <> "\n"
  end

  @spec strip(String.t()) :: String.t()
  def strip(content) do
    case String.split(content, "\n---\n<!-- Annotations by developer -->\n", parts: 2) do
      [clean, _rest] -> String.trim_trailing(clean)
      [_content] -> String.trim_trailing(content)
    end
  end

  @spec present?(String.t()) :: boolean()
  def present?(content) do
    String.contains?(content, "<!-- Annotations by developer -->")
  end
end
