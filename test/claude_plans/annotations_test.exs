defmodule ClaudePlans.AnnotationsTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.Annotations

  @separator "\n---\n<!-- Annotations by developer -->\n"

  describe "inject/2" do
    test "injects annotations into clean content" do
      content = "# My Plan\n\nSome content here."

      annotations = [
        %{id: "A1", block_path: "section-1", direction: "use Req instead"},
        %{id: "A2", block_path: "section-2", direction: ""}
      ]

      result = Annotations.inject(content, annotations)

      assert result =~ "# My Plan"
      assert result =~ "Some content here."
      assert result =~ @separator
      assert result =~ "<!-- A1 (section-1): use Req instead -->"
      assert result =~ "<!-- A2 (section-2) -->"
    end

    test "replaces existing annotations" do
      content = "# Plan" <> @separator <> "<!-- OLD (old-path): old direction -->\n"

      annotations = [
        %{id: "A1", block_path: "new-section", direction: "new direction"}
      ]

      result = Annotations.inject(content, annotations)

      refute result =~ "OLD"
      refute result =~ "old direction"
      assert result =~ "<!-- A1 (new-section): new direction -->"
    end

    test "trims whitespace from direction" do
      content = "content"

      annotations = [
        %{id: "A1", block_path: "s1", direction: "  trimmed  "}
      ]

      result = Annotations.inject(content, annotations)
      assert result =~ "<!-- A1 (s1): trimmed -->"
    end

    test "omits direction suffix when direction is empty" do
      content = "content"

      annotations = [
        %{id: "A1", block_path: "s1", direction: ""},
        %{id: "A2", block_path: "s2", direction: "   "}
      ]

      result = Annotations.inject(content, annotations)
      assert result =~ "<!-- A1 (s1) -->"
      assert result =~ "<!-- A2 (s2) -->"
      refute result =~ ": -->"
    end
  end

  describe "strip/1" do
    test "removes everything after the annotation separator" do
      content = "# Plan\n\nContent" <> @separator <> "<!-- A1 (s1): direction -->\n"

      result = Annotations.strip(content)
      assert result == "# Plan\n\nContent"
    end

    test "returns content unchanged when no annotations present" do
      content = "# Plan\n\nJust content"
      assert Annotations.strip(content) == "# Plan\n\nJust content"
    end

    test "trims trailing whitespace" do
      content = "# Plan\n\n  "
      assert Annotations.strip(content) == "# Plan"
    end
  end

  describe "present?/1" do
    test "returns true when annotation marker is present" do
      content = "# Plan" <> @separator <> "<!-- A1 -->\n"
      assert Annotations.present?(content)
    end

    test "returns false when no annotation marker" do
      refute Annotations.present?("# Plan\n\nJust content")
    end

    test "returns true for marker even without separator formatting" do
      assert Annotations.present?("text <!-- Annotations by developer --> more text")
    end
  end
end
