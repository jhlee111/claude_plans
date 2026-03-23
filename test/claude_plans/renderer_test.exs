defmodule ClaudePlans.RendererTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.Renderer

  describe "mermaid code blocks" do
    test "renders mermaid via MDExMermex plugin as mdex-mermex div" do
      markdown = """
      ```mermaid
      graph TD
        A --> B
      ```
      """

      html = Renderer.to_html(markdown)

      assert html =~ ~s(class="mdex-mermex mermaid")
      assert html =~ "data:image/svg+xml;base64,"
    end

    test "does not apply syntax highlighting spans to mermaid blocks" do
      markdown = """
      ```mermaid
      sequenceDiagram
        Alice->>Bob: Hello
      ```
      """

      html = Renderer.to_html(markdown)

      refute html =~ ~r/<code class="language-mermaid">.*<span style=/s
    end

    test "renders mermaid as img with base64 SVG" do
      markdown = """
      ```mermaid
      pie title Pets
        "Dogs" : 386
        "Cats" : 85
      ```
      """

      html = Renderer.to_html(markdown)

      assert html =~ ~r/<img src="data:image\/svg\+xml;base64,/
      assert html =~ "mdex-mermex"
    end
  end

  describe "non-mermaid code blocks" do
    test "applies syntax highlighting to regular code blocks" do
      markdown = """
      ```elixir
      def hello, do: :world
      ```
      """

      html = Renderer.to_html(markdown)

      assert html =~ "<span style="
    end

    test "does not wrap non-mermaid blocks in mermaid div" do
      markdown = """
      ```javascript
      console.log("hello")
      ```
      """

      html = Renderer.to_html(markdown)

      refute html =~ ~s(class="mdex-mermex mermaid" tabindex)
      assert html =~ "language-javascript"
    end
  end

  describe "mixed content" do
    test "mermaid and regular code blocks coexist correctly" do
      markdown = """
      # Plan

      ```mermaid
      graph LR
        A --> B
      ```

      Some text.

      ```elixir
      IO.puts("hello")
      ```
      """

      html = Renderer.to_html(markdown)

      # Mermaid block: rendered by MDExMermex
      assert html =~ ~s(class="mdex-mermex mermaid")

      # Elixir block: syntax highlighted
      assert html =~ "<span style="
    end
  end

  describe "to_html/1 edge cases" do
    test "returns empty string for nil" do
      assert Renderer.to_html(nil) == ""
    end

    test "handles empty mermaid block" do
      markdown = """
      ```mermaid
      ```
      """

      html = Renderer.to_html(markdown)

      assert html =~ "mdex-mermex" or html =~ "<pre>"
    end
  end
end
