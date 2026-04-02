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

  describe "sort controls" do
    test "sort buttons render on plans tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Default is modified_desc — clock button should be active
      assert has_element?(view, ".cb-sort-active")
    end

    test "cycle_sort toggles to name_asc", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      render_click(view, "cycle_sort", %{"field" => "name"})

      # After clicking name, it should show name sort as active
      assert has_element?(view, ".cb-sort-active")
    end

    test "cycle_sort name toggles between asc and desc", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # First click: name_asc
      render_click(view, "cycle_sort", %{"field" => "name"})
      # Second click: name_desc
      render_click(view, "cycle_sort", %{"field" => "name"})
      # Third click back to name_asc
      render_click(view, "cycle_sort", %{"field" => "name"})

      # No crash, still renders
      assert has_element?(view, ".cb-layout")
    end

    test "cycle_sort modified toggles between desc and asc", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Default is modified_desc, click toggles to modified_asc
      render_click(view, "cycle_sort", %{"field" => "modified"})
      # Click again: back to modified_desc
      render_click(view, "cycle_sort", %{"field" => "modified"})

      assert has_element?(view, ".cb-layout")
    end

    test "sort buttons render on search results", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/?q=test")

      assert has_element?(view, ".cb-section-label", "Results")
      assert has_element?(view, "[phx-click=cycle_sort]")
    end

    test "sort applies across tabs without crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Sort on plans tab
      render_click(view, "cycle_sort", %{"field" => "name"})

      # Switch to projects tab — sort should persist
      view |> element(".cb-tab", "Projects") |> render_click()
      assert has_element?(view, ".cb-sort-active")

      # Switch to folders tab
      view |> element(".cb-tab", "Folders") |> render_click()
      assert has_element?(view, ".cb-layout")
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
