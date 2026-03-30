defmodule ClaudePlans.Web.Components.ContentComponents do
  @moduledoc "Main content area components for each tab (plans, projects, activity)."
  use Phoenix.Component

  import ClaudePlans.Web.Components.Helpers
  import ClaudePlans.Web.Icons

  def activity_content(assigns) do
    selected_event =
      if assigns.selected_activity_index do
        Enum.at(assigns.activity_events, assigns.selected_activity_index)
      end

    assigns = assign(assigns, :selected_event, selected_event)

    ~H"""
    <div :if={@activity_diff_html && @selected_event} class={"cb-content-wrap#{if @content_width == "narrow", do: " cb-content-wrap--narrow", else: ""}"}>
      <div class="cb-content-toolbar">
        <div class="cb-toolbar-left">
          <div class="cb-file-header">{@selected_event.display_name}</div>
          <div class="cb-header-actions">
            <button phx-click="goto_activity_file" class="cb-action-btn" title="Go to file (Enter)">
              Go to file &rarr;
            </button>
          </div>
        </div>
        <div class="cb-display-controls">
          <button phx-click="toggle_width" class={"cb-width-toggle#{if @content_width == "narrow", do: " cb-width-toggle--active", else: ""}"} title={"Content width: #{@content_width}"}><.icon_columns size={14} /></button>
          <button id="theme-toggle-activity" class="cb-theme-toggle" phx-hook="ThemeToggle" phx-update="ignore"><.icon_moon size={14} /></button>
          <button phx-click="font_size" phx-value-dir="down" class="cb-font-size-btn cb-font-size-btn--sm" title={"Smaller (#{@font_size}px)"}>A</button>
          <span class="cb-font-size-sep">/</span>
          <button phx-click="font_size" phx-value-dir="up" class="cb-font-size-btn cb-font-size-btn--lg" title={"Larger (#{@font_size}px)"}>A</button>
        </div>
      </div>
      <div class={if @selected_event.category == :plan, do: "cb-diff-view", else: "cp-content"}>
        {Phoenix.HTML.raw(@activity_diff_html)}
      </div>
    </div>
    <div :if={is_nil(@activity_diff_html) || is_nil(@selected_event)} class="cb-placeholder">
      <div class="cb-placeholder-inner">
        <div class="cb-placeholder-title">Activity Feed</div>
        <div class="cb-placeholder-hint">Navigate with j/k, press Enter to go to file</div>
      </div>
    </div>
    """
  end

  def plans_content(assigns) do
    ~H"""
    <div :if={@html} class={"cb-content-wrap#{if @content_width == "narrow", do: " cb-content-wrap--narrow", else: ""}"}>
      <div class="cb-content-toolbar">
        <div class="cb-toolbar-left">
          <div class="cb-file-header">{@selected}</div>
          <div class="cb-header-actions">
            <button
              :if={length(@versions) >= 2}
              phx-click="toggle_diff"
              class={"cb-action-btn#{if @view_mode == :diff, do: " cb-action-btn--active", else: ""}"}
            >
              Diff
            </button>
            <button
              :if={@versions != []}
              phx-click="toggle_versions"
              class={"cb-action-btn#{if @show_versions, do: " cb-action-btn--active", else: ""}"}
            >
              History ({length(@versions)})
            </button>
            <button
              :if={@view_mode == :rendered}
              phx-click="toggle_inspector"
              class={"cb-action-btn#{if @show_annotation_panel, do: " cb-action-btn--active", else: ""}"}
            >
              Annotate
            </button>
          </div>
        </div>
        <div class="cb-display-controls">
          <button phx-click="toggle_width" class={"cb-width-toggle#{if @content_width == "narrow", do: " cb-width-toggle--active", else: ""}"} title={"Content width: #{@content_width}"}><.icon_columns size={14} /></button>
          <button id="theme-toggle-plans" class="cb-theme-toggle" phx-hook="ThemeToggle" phx-update="ignore"><.icon_moon size={14} /></button>
          <button phx-click="font_size" phx-value-dir="down" class="cb-font-size-btn cb-font-size-btn--sm" title={"Smaller (#{@font_size}px)"}>A</button>
          <span class="cb-font-size-sep">/</span>
          <button phx-click="font_size" phx-value-dir="up" class="cb-font-size-btn cb-font-size-btn--lg" title={"Larger (#{@font_size}px)"}>A</button>
        </div>
      </div>
      <div :if={@show_versions} class="cb-version-panel">
        <div :for={{v, idx} <- Enum.with_index(@versions)} class="cb-version-item">
          <span class="cb-version-time">v{length(@versions) - idx}</span>
          <span class="cb-version-time">{format_version_time(v.timestamp)}</span>
          <span class="cb-version-size">{format_bytes(v.byte_size)}</span>
          <span class="cb-version-id">{v.id}</span>
        </div>
      </div>
      <div :if={@view_mode == :diff} class="cb-diff-controls">
        <form phx-change="select_diff_versions">
          <span>Compare</span>
          <select name="version_a">
            <option
              :for={{v, idx} <- Enum.with_index(@versions)}
              value={v.id}
              selected={@diff_version_a == v.id}
            >
              v{length(@versions) - idx} ({v.id})
            </option>
          </select>
          <span>vs</span>
          <select name="version_b">
            <option
              :for={{v, idx} <- Enum.with_index(@versions)}
              value={v.id}
              selected={@diff_version_b == v.id}
            >
              v{length(@versions) - idx} ({v.id})
            </option>
          </select>
        </form>
      </div>
      <div :if={@view_mode == :diff && @diff_html} class="cb-diff-view">
        {Phoenix.HTML.raw(@diff_html)}
      </div>
      <div :if={@view_mode == :rendered && @inspector_mode} class="cb-inspector-banner">
        Click any block to annotate &middot; Press <kbd>a</kbd> or <kbd>Esc</kbd> to exit
      </div>
      <div :if={@view_mode == :rendered} id="plan-content" class={"cp-content#{if @inspector_mode, do: " cb-inspector-active", else: ""}"} phx-hook="PlanContent" phx-update="replace" data-highlight={@content_highlight} data-inspector={to_string(@inspector_mode)} data-annotations={Jason.encode!(Enum.map(@annotations, & &1.block_index))} style={"font-size: #{@font_size}px"}>
        {Phoenix.HTML.raw(@html)}
      </div>
    </div>
    <div :if={is_nil(@html)} class="cb-placeholder">
      <div class="cb-placeholder-inner">
        <div class="cb-placeholder-title">No plan selected</div>
        <div class="cb-placeholder-hint">Select a plan from the sidebar</div>
      </div>
    </div>
    """
  end
end
