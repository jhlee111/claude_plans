defmodule ClaudePlans.Web.Components.SidebarComponents do
  @moduledoc "Sidebar content components for each tab (plans, projects, activity) and search results."
  use Phoenix.Component

  import ClaudePlans.Web.Icons
  import ClaudePlans.Web.Components.Helpers

  def search_results(assigns) do
    ~H"""
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.75rem">
      <span class="cb-section-label">Results</span>
      <span class="cb-count">{length(@search_results)}</span>
    </div>
    <div :for={{result, idx} <- Enum.with_index(@search_results)} class="cb-file-row">
      <button
        phx-click="select_search_result"
        phx-value-index={idx}
        class={"cb-file-btn#{if search_result_active?(result, assigns), do: " cb-file-btn--active", else: ""}"}
      >
        <div class="cb-file-name">{result.display_name}</div>
        <div class="cb-search-source">{source_label(result)}</div>
        <div :for={match <- Enum.take(result.matches, 2)} class="cb-search-match">
          <span class="cb-match-line">L{match.line_number}:</span> {match.line_text}
        </div>
      </button>
    </div>
    <div :if={@search_results == []} class="cb-empty">No matches found</div>
    """
  end

  def plans_sidebar(assigns) do
    ~H"""
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.75rem">
      <span class="cb-section-label">Plans</span>
      <span class="cb-count">{length(@plans)}</span>
    </div>
    <% plan_editor_urls = Map.new(@plans, fn p -> {p.filename, editor_url(p.path)} end) %>
    <div :for={plan <- @plans} class="cb-file-row">
      <button
        phx-click="select_plan"
        phx-value-filename={plan.filename}
        class={"cb-file-btn#{if @selected == plan.filename, do: " cb-file-btn--active", else: ""}"}
      >
        <div class="cb-file-name">{plan.display_name}</div>
        <div class="cb-file-time">{format_time(plan.modified)}</div>
      </button>
      <div class="cb-file-actions">
        <a :if={plan_editor_urls[plan.filename]} href={plan_editor_urls[plan.filename]} class="cb-action-btn" title="Open in editor"><.icon_edit size={12} /></a>
        <span
          id={"copy-plan-#{plan.filename}"}
          class="cb-action-btn"
          phx-hook="CopyPath"
          data-path={plan.path}
          title={plan.path}
        ><.icon_copy size={12} /></span>
        <button
          phx-click="delete_file"
          phx-value-path={plan.path}
          data-confirm={"Delete #{plan.path}?"}
          class="cb-action-btn cb-action-btn--danger"
          title="Delete file"
        ><.icon_trash size={12} /></button>
      </div>
    </div>
    <div :if={@plans == []} class="cb-empty">
      No plan files yet.
      <div class="cb-empty-hint">Use /plan in Claude Code</div>
    </div>
    """
  end

  def projects_sidebar(assigns) do
    ~H"""
    <form phx-change="select_project">
      <select name="project" class="cb-select">
        <option :if={is_nil(@selected_project)} value="">Select project...</option>
        <option
          :for={proj <- @projects}
          value={proj.dir_name}
          selected={@selected_project == proj.dir_name}
        >
          {proj.display_name}
        </option>
      </select>
    </form>
    <div :if={@selected_project}>
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.5rem">
        <span class="cb-section-label">Files</span>
        <span class="cb-count">{length(@project_files)}</span>
      </div>
      <%
        file_paths = Map.new(@project_files, fn f ->
          {f.rel_path, Path.join([@projects_dir, @selected_project, f.rel_path])}
        end)
        file_editor_urls = Map.new(file_paths, fn {rel, full} -> {rel, editor_url(full)} end)
      %>
      <div :for={file <- @project_files} class="cb-file-row">
        <button
          phx-click="select_file"
          phx-value-path={file.rel_path}
          class={"cb-file-btn#{if @selected_file == file.rel_path, do: " cb-file-btn--active", else: ""}"}
        >
          <div class="cb-file-name">
            <span :if={file.dir} class="cb-file-dir">{file.dir}/</span>{file.name}
          </div>
        </button>
        <div class="cb-file-actions">
          <a
            :if={file_editor_urls[file.rel_path]}
            href={file_editor_urls[file.rel_path]}
            class="cb-action-btn"
            title="Open in editor"
          ><.icon_edit size={12} /></a>
          <span
            id={"copy-file-#{file.rel_path}"}
            class="cb-action-btn"
            phx-hook="CopyPath"
            data-path={file_paths[file.rel_path]}
            title={file_paths[file.rel_path]}
          ><.icon_copy size={12} /></span>
          <button
            phx-click="delete_file"
            phx-value-path={file_paths[file.rel_path]}
            data-confirm={"Delete #{file_paths[file.rel_path]}?"}
            class="cb-action-btn cb-action-btn--danger"
            title="Delete file"
          ><.icon_trash size={12} /></button>
        </div>
      </div>
      <div :if={@project_files == []} class="cb-empty">No .md files</div>
    </div>
    """
  end

  def activity_sidebar(assigns) do
    ~H"""
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.75rem">
      <span class="cb-section-label">Activity</span>
      <span class="cb-count">{length(@activity_events)}</span>
    </div>
    <div :for={{event, idx} <- Enum.with_index(@activity_events)} class={"cb-activity-row-wrap#{if idx == @selected_activity_index, do: " cb-activity-row--active", else: ""}#{if event.category == :plan and event.filename in @unchecked_plan_files, do: " cb-activity-row--unread", else: ""}"}>
      <button
        phx-click="select_activity_event"
        phx-value-index={idx}
        class="cb-activity-row"
      >
        <span class={"cb-activity-icon cb-activity-icon--#{event.action}"}>
          {action_icon(event.action)}
        </span>
        <div class="cb-activity-info">
          <div class="cb-activity-name">{event.display_name}</div>
          <div class="cb-activity-meta">
            <span class="cb-activity-category">{category_label(event.category)}</span>
            <span :if={event.project} class="cb-activity-project">{format_project_name(event.project)}</span>
            <span class="cb-activity-time" id={"time-#{event.id}"} phx-hook="TimeAgo" data-timestamp={DateTime.to_iso8601(event.timestamp)}></span>
          </div>
        </div>
        <span
          :if={event.category == :plan and event.filename in @unchecked_plan_files}
          class="cb-activity-unread"
        ></span>
      </button>
      <button
        :if={event.action != :deleted}
        phx-click="goto_activity_file_at"
        phx-value-index={idx}
        class="cb-activity-goto"
        title="Go to file"
      >&rsaquo;</button>
    </div>
    <div :if={@activity_events == []} class="cb-empty">
      No activity yet.
      <div class="cb-empty-hint">File changes will appear here in real-time</div>
    </div>
    """
  end
end
