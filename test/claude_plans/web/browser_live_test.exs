defmodule ClaudePlans.Web.BrowserLiveTest do
  use ExUnit.Case

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint ClaudePlans.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  describe "mount" do
    test "renders the plans tab by default", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "Plans"
      assert html =~ "Projects"
      assert html =~ "Activity"
      assert has_element?(view, ".cb-tab--active", "Plans")
    end

    test "renders with tab param", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?tab=activity")
      assert has_element?(view, ".cb-tab--active", "Activity")
    end
  end

  describe "tab switching" do
    test "switching tabs updates the active tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element(".cb-tab", "Projects") |> render_click()
      assert has_element?(view, ".cb-tab--active", "Projects")

      view |> element(".cb-tab", "Activity") |> render_click()
      assert has_element?(view, ".cb-tab--active", "Activity")

      view |> element(".cb-tab", "Plans") |> render_click()
      assert has_element?(view, ".cb-tab--active", "Plans")
    end
  end

  describe "search" do
    test "search input renders", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "#search-input")
    end

    test "search with query shows results section", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?q=test")
      assert has_element?(view, ".cb-section-label", "Results")
    end
  end

  describe "keyboard shortcuts" do
    test "help modal toggles", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      refute has_element?(view, ".cb-help-overlay")

      render_click(view, "kb_help")
      assert has_element?(view, ".cb-help-overlay")

      render_click(view, "kb_help")
      refute has_element?(view, ".cb-help-overlay")
    end

    test "escape dismisses help modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_click(view, "kb_help")
      assert has_element?(view, ".cb-help-overlay")

      render_click(view, "kb_escape")
      refute has_element?(view, ".cb-help-overlay")
    end
  end

  describe "font size" do
    test "font size increases and decreases", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Increase
      render_click(view, "font_size", %{"dir" => "up"})
      # Decrease
      render_click(view, "font_size", %{"dir" => "down"})
      # Reset
      render_click(view, "font_size", %{"dir" => "reset"})
      # Just verify no crashes
      assert has_element?(view, ".cb-layout")
    end
  end
end
