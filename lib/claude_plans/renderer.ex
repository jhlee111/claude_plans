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
      codefence_renderers: %{
        "mermaid" => fn _lang, _meta, code ->
          escaped = code |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
          ~s(<pre><code class="language-mermaid">#{escaped}</code></pre>)
        end
      }
    )
  end

  def to_html(nil), do: ""
end
