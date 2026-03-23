defmodule ClaudePlans.Web.UrlParamsTest do
  use ExUnit.Case, async: true

  alias ClaudePlans.Web.UrlParams

  @default_assigns %{
    active_tab: :plans,
    selected: nil,
    selected_project: nil,
    selected_file: nil,
    search_query: "",
    view_mode: :rendered
  }

  describe "build/2" do
    test "returns / with default assigns and no overrides" do
      assert UrlParams.build(@default_assigns) == "/"
    end

    test "includes tab when not :plans" do
      assigns = %{@default_assigns | active_tab: :projects}
      url = UrlParams.build(assigns)
      assert url =~ "tab=projects"
    end

    test "includes plan when selected" do
      assigns = %{@default_assigns | selected: "my-plan.md"}
      url = UrlParams.build(assigns)
      assert url =~ "plan=my-plan.md"
    end

    test "includes project and file on projects tab" do
      assigns = %{
        @default_assigns
        | active_tab: :projects,
          selected_project: "my-project",
          selected_file: "memory/notes.md"
      }

      url = UrlParams.build(assigns)
      assert url =~ "tab=projects"
      assert url =~ "project=my-project"
      assert url =~ "file="
    end

    test "includes search query" do
      assigns = %{@default_assigns | search_query: "hello"}
      url = UrlParams.build(assigns)
      assert url =~ "q=hello"
    end

    test "includes view mode when diff" do
      assigns = %{@default_assigns | view_mode: :diff}
      url = UrlParams.build(assigns)
      assert url =~ "view=diff"
    end

    test "overrides take precedence over assigns" do
      assigns = %{@default_assigns | active_tab: :plans}
      url = UrlParams.build(assigns, %{tab: :activity})
      assert url =~ "tab=activity"
    end

    test "does not include project/file when not on projects tab" do
      assigns = %{@default_assigns | selected_project: "proj", selected_file: "file.md"}
      url = UrlParams.build(assigns)
      refute url =~ "project="
      refute url =~ "file="
    end
  end

  describe "parse_tab/1" do
    test "parses known tabs" do
      assert UrlParams.parse_tab("projects") == :projects
      assert UrlParams.parse_tab("activity") == :activity
    end

    test "defaults to :plans for unknown values" do
      assert UrlParams.parse_tab("plans") == :plans
      assert UrlParams.parse_tab(nil) == :plans
      assert UrlParams.parse_tab("bogus") == :plans
    end
  end
end
