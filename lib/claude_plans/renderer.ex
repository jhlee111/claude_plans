defmodule ClaudePlans.Renderer do
  @moduledoc false

  def to_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: [
        table: true,
        strikethrough: true,
        tasklist: true,
        autolink: true
      ],
      parse: [smart: true],
      render: [unsafe_: true],
      syntax_highlight: [
        formatter: {:html_inline, [theme: "github_light"]}
      ],
      plugins: [{MDExMermex, class: "mermaid"}]
    )
  end

  def to_html(nil), do: ""
end
