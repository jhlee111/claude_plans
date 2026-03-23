defmodule ClaudePlans.RendererTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.Renderer

  describe "mermaid code blocks" do
    test "preserves language-mermaid class without syntax highlighting" do
      markdown = """
      ```mermaid
      graph TD
        A --> B
      ```
      """

      html = Renderer.to_html(markdown)

      assert html =~ ~s(class="language-mermaid")
      assert html =~ "graph TD"
      assert html =~ "A --&gt; B"
    end

    test "does not apply syntax highlighting spans to mermaid blocks" do
      markdown = """
      ```mermaid
      sequenceDiagram
        Alice->>Bob: Hello
      ```
      """

      html = Renderer.to_html(markdown)

      # Syntax highlighted code gets wrapped in <span style="..."> elements
      # Mermaid blocks should NOT have these
      refute html =~ ~r/<code class="language-mermaid">.*<span style=/s
    end

    test "renders mermaid inside pre>code structure for JS hook" do
      markdown = """
      ```mermaid
      pie title Pets
        "Dogs" : 386
        "Cats" : 85
      ```
      """

      html = Renderer.to_html(markdown)

      assert html =~ ~r/<pre><code class="language-mermaid">.*<\/code><\/pre>/s
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

      # Regular code blocks should have syntax highlighting spans
      assert html =~ "<span style="
    end

    test "does not add language-mermaid class to non-mermaid blocks" do
      markdown = """
      ```javascript
      console.log("hello")
      ```
      """

      html = Renderer.to_html(markdown)

      refute html =~ "language-mermaid"
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

      # Mermaid block: plain code with language-mermaid class
      assert html =~ ~s(class="language-mermaid")
      assert html =~ "graph LR"

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

      assert html =~ ~s(class="language-mermaid")
    end
  end
end
