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
        <div class="cb-search-source">
          {source_label(result)}
          <span :if={result.modified_at}>· {format_time(result.modified_at)}</span>
        </div>
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
          data-confirm={"Delete #{Path.basename(plan.path)}? This cannot be undone."}
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
          phx-target="#projects-viewer"
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
            data-confirm={"Delete #{file.rel_path}? This cannot be undone."}
            class="cb-action-btn cb-action-btn--danger"
            title="Delete file"
          ><.icon_trash size={12} /></button>
        </div>
      </div>
      <div :if={@project_files == []} class="cb-empty">No .md files</div>
    </div>
    """
  end

  def folders_sidebar(assigns) do
    ~H"""
    <%!-- Folder selector: dropdown + inline action icons, aligned to match cb-select height --%>
    <div style="display:flex;align-items:center;gap:0.25rem;margin-bottom:0.75rem">
      <form phx-change="select_custom_folder" style="flex:1;min-width:0">
        <select name="folder" class="cb-select" style="margin-bottom:0">
          <option :if={is_nil(@selected_custom_folder)} value="">Select folder...</option>
          <option
            :for={f <- @custom_folders}
            value={f.id}
            selected={@selected_custom_folder == f.id}
          >
            {f.name}
          </option>
        </select>
      </form>
      <button phx-click="show_add_folder" class="cb-action-btn" title="Add folder" style="padding:0.3rem">
        <.icon_folder_plus size={14} />
      </button>
      <button
        :if={@selected_custom_folder}
        phx-click="remove_folder"
        data-confirm="Remove this folder from the list?"
        class="cb-action-btn cb-action-btn--danger"
        title="Remove folder"
        style="padding:0.3rem"
      >
        <.icon_x size={12} />
      </button>
    </div>
    <%!-- Folder browser --%>
    <div :if={@adding_folder} style="margin-top:0.5rem">
      <div style="display:flex;align-items:center;gap:0.25rem;margin-bottom:0.375rem">
        <button phx-click="browse_up" class="cb-action-btn" title="Go up" style="padding:0.2rem 0.4rem;font-size:0.7rem">
          ..
        </button>
        <span class="cb-browse-path" style="flex:1;min-width:0" title={@browse_path}>
          {@browse_path}
        </span>
        <button phx-click="refresh_dir_index" class="cb-action-btn" title="Refresh index" style="padding:0.2rem">
          <.icon_refresh size={11} />
        </button>
      </div>
      <form phx-change="browse_filter" style="margin-bottom:0.375rem">
        <input
          name="filter"
          value={@browse_filter}
          placeholder="Filter folders..."
          autocomplete="off"
          phx-debounce="150"
          class="cb-search-input"
          style="font-size:0.7rem;padding:0.25rem 0.5rem"
        />
      </form>
      <div class="cb-browse-list">
        <div :if={@browse_dirs == []} style="padding:0.5rem;font-size:0.7rem;color:#94a3b8;text-align:center">
          No subdirectories
        </div>
        <button
          :for={entry <- @browse_dirs}
          phx-click="browse_into"
          phx-value-path={browse_entry_path(entry)}
          class="cb-browse-item"
        >
          <span style="opacity:0.5">📁</span>
          <span style="flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis">{highlight_match(entry)}</span>
          <span :if={browse_md_badge(entry)} style="font-size:0.55rem;color:#2563eb;background:#dbeafe;border-radius:0.25rem;padding:0 0.2rem;flex-shrink:0;white-space:nowrap">
            {browse_md_badge(entry)}
          </span>
        </button>
      </div>
      <div :if={@folder_path_error} style="color:#ef4444;font-size:0.65rem;margin-top:0.25rem">
        {@folder_path_error}
      </div>
      <div style="display:flex;gap:0.375rem;margin-top:0.375rem">
        <button phx-click="browse_select" class="cb-action-btn" style="flex:1">
          Select this folder
        </button>
        <button phx-click="cancel_add_folder" class="cb-action-btn">
          Cancel
        </button>
      </div>
    </div>
    <div :if={@selected_custom_folder && @folder_files != []}>
      <%
        folder_path = @folder_current_path || folder_path_for(@custom_folders, @selected_custom_folder)
        original_path = folder_path_for(@custom_folders, @selected_custom_folder)
        in_subfolder = @folder_current_path != nil && @folder_current_path != original_path
        dirs = Enum.filter(@folder_files, & &1.type == :dir)
        files = Enum.filter(@folder_files, & &1.type == :file)
        file_editor_urls = Map.new(files, fn f -> {f.rel_path, editor_url(f.full_path)} end)
      %>
      <%!-- Subfolder breadcrumb bar --%>
      <div :if={in_subfolder} class="cb-folder-breadcrumb">
        <button phx-click="navigate_folder_up" class="cb-folder-back-btn" title="Go to parent folder">
          <.icon_chevron_left size={14} />
        </button>
        <div class="cb-folder-breadcrumb-path">
          <.icon_folder size={12} />
          <span title={folder_path}>{Path.relative_to(folder_path, original_path)}</span>
        </div>
      </div>
      <%!-- Subdirectories --%>
      <div :if={dirs != []} style="margin-bottom:0.5rem">
        <div style="display:flex;align-items:center;justify-content:space-between;margin:0.5rem 0">
          <span class="cb-section-label">Folders</span>
          <span class="cb-count">{length(dirs)}</span>
        </div>
        <div :for={dir <- dirs} class="cb-file-row">
          <button
            phx-click="navigate_subfolder"
            phx-value-path={dir.full_path}
            class="cb-file-btn"
            style="color:#64748b"
          >
            <div class="cb-file-name" style="display:flex;align-items:center;gap:0.25rem">
              <span style="opacity:0.5">📁</span> {dir.name}
            </div>
          </button>
        </div>
      </div>
      <%!-- Markdown files --%>
      <div style="display:flex;align-items:center;justify-content:space-between;margin:0.5rem 0">
        <span class="cb-section-label">Files</span>
        <span class="cb-count">{length(files)}</span>
      </div>
      <div :for={file <- files} class="cb-file-row">
        <button
          phx-click="select_file"
          phx-target="#folders-viewer"
          phx-value-path={file.rel_path}
          phx-value-folder={folder_path}
          class={"cb-file-btn#{if @folder_nav_selected == file.rel_path, do: " cb-file-btn--active", else: ""}"}
        >
          <div class="cb-file-name">{file.name}</div>
        </button>
        <div class="cb-file-actions">
          <a
            :if={file_editor_urls[file.rel_path]}
            href={file_editor_urls[file.rel_path]}
            class="cb-action-btn"
            title="Open in editor"
          ><.icon_edit size={12} /></a>
          <span
            id={"copy-folder-file-#{file.rel_path}"}
            class="cb-action-btn"
            phx-hook="CopyPath"
            data-path={file.full_path}
            title={file.full_path}
          ><.icon_copy size={12} /></span>
        </div>
      </div>
      <div :if={files == []} class="cb-empty" style="font-size:0.7rem">No .md files in this folder</div>
    </div>
    <div :if={@selected_custom_folder && @folder_files == []}>
      <div :if={@folder_current_path} class="cb-folder-breadcrumb">
        <button phx-click="navigate_folder_up" class="cb-folder-back-btn" title="Go to parent folder">
          <.icon_chevron_left size={14} />
        </button>
        <div class="cb-folder-breadcrumb-path">
          <.icon_folder size={12} />
          <span>{Path.basename(@folder_current_path)}</span>
        </div>
      </div>
      <div class="cb-empty">Empty folder</div>
    </div>
    <div :if={is_nil(@selected_custom_folder) && @custom_folders == [] && !@adding_folder} class="cb-empty">
      No folders yet.
      <div class="cb-empty-hint">Click + to add a folder</div>
    </div>
    """
  end

  defp folder_path_for(folders, selected_id) do
    case Enum.find(folders, &(&1.id == selected_id)) do
      nil -> nil
      folder -> folder.path
    end
  end

  # Browse entry helpers — entries are plain strings, {path, indices}, or {path, indices, direct, sub}
  defp browse_entry_path({path, _indices, _direct, _sub}), do: path
  defp browse_entry_path({path, _indices}), do: path
  defp browse_entry_path(path) when is_binary(path), do: path

  defp browse_md_badge({_path, _indices, direct, sub}) do
    total = direct + sub

    if total > 0 do
      if sub > 0, do: "#{direct}+#{sub}", else: "#{direct}"
    end
  end

  defp browse_md_badge(_), do: nil

  defp highlight_match({path, indices, _direct, _sub}), do: highlight_match({path, indices})

  defp highlight_match({path, indices}) do
    idx_set = MapSet.new(indices)

    html =
      path
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.map(fn {char, idx} ->
        escaped = Phoenix.HTML.html_escape(char) |> Phoenix.HTML.safe_to_string()

        if MapSet.member?(idx_set, idx) do
          "<b style=\"color:#2563eb;background:#dbeafe;border-radius:1px\">#{escaped}</b>"
        else
          escaped
        end
      end)
      |> Enum.join()

    Phoenix.HTML.raw(html)
  end

  defp highlight_match(path) when is_binary(path), do: path

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
