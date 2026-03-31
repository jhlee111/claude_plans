defmodule ClaudePlans.Web.ProjectsViewerComponent do
  @moduledoc "LiveComponent for viewing project files with diff, history, and annotations."
  use Phoenix.LiveComponent

  import ClaudePlans.Web.Components.Helpers, only: [format_version_time: 1, format_bytes: 1]
  import ClaudePlans.Web.Icons

  alias ClaudePlans.{Annotations, Projects, RenderCache, VersionStore, ViewerState}

  # --- Lifecycle ---

  def mount(socket) do
    {:ok,
     assign(socket,
       viewer: %ViewerState{},
       font_size: 16,
       content_width: "wide",
       content_highlight: nil,
       project_path: nil
     )}
  end

  def update(new_assigns, socket) do
    old = socket.assigns

    socket =
      socket
      |> assign(Map.take(new_assigns, [:id, :font_size, :content_width, :content_highlight]))
      # Step 1: project_path change → reset viewer
      |> then(fn s ->
        if changed?(new_assigns, old, :project_path) do
          assign(s, project_path: new_assigns.project_path, viewer: %ViewerState{})
        else
          s
        end
      end)
      # Step 2: initial_file
      |> then(fn s ->
        file = new_assigns[:initial_file]

        if is_binary(file) and file != "" and
             s.assigns.viewer.selected != file do
          load_file(s, file)
        else
          s
        end
      end)
      # Step 3: one-time event — file_updated (bridge from BrowserLive)
      |> then(fn s ->
        case new_assigns do
          %{file_updated: {project_path, rel_path}} when not is_nil(project_path) ->
            s =
              if s.assigns.project_path == project_path and
                   (s.assigns.viewer.selected || "") == rel_path do
                refresh_current_file(s)
              else
                s
              end

            assign(s, file_updated: nil)

          _ ->
            s
        end
      end)
      # Step 4: keyboard_event delegation
      |> then(fn s ->
        case new_assigns do
          %{keyboard_event: {event, params}} when not is_nil(event) ->
            s = handle_keyboard(s, event, params)
            assign(s, keyboard_event: nil)

          _ ->
            s
        end
      end)

    {:ok, socket}
  end

  defp changed?(new_assigns, old, key) do
    Map.has_key?(new_assigns, key) and Map.get(new_assigns, key) != Map.get(old, key)
  end

  # --- Events ---

  def handle_event("select_file", %{"path" => rel_path}, socket) do
    socket = load_file(socket, rel_path)
    send(self(), {:projects_nav_state, rel_path})
    {:noreply, socket}
  end

  def handle_event("toggle_diff", _params, socket) do
    {:noreply, update_viewer(socket, &ViewerState.toggle_diff/1)}
  end

  def handle_event("toggle_versions", _params, socket) do
    {:noreply, update_viewer(socket, &ViewerState.toggle_versions/1)}
  end

  def handle_event("select_diff_versions", %{"version_a" => a, "version_b" => b}, socket) do
    {:noreply, update_viewer(socket, &ViewerState.select_diff_versions(&1, a, b))}
  end

  def handle_event("toggle_inspector", _params, socket) do
    {:noreply, update_viewer(socket, &ViewerState.toggle_inspector/1)}
  end

  def handle_event(
        "add_annotation",
        %{"block_path" => block_path, "block_index" => block_index},
        socket
      ) do
    {:noreply, update_viewer(socket, &ViewerState.add_annotation(&1, block_path, block_index))}
  end

  def handle_event("update_annotation", %{"id" => id, "direction" => direction}, socket) do
    {:noreply, update_viewer(socket, &ViewerState.update_annotation(&1, id, direction))}
  end

  def handle_event("save_annotation", %{"id" => id}, socket) do
    {:noreply, update_viewer(socket, &ViewerState.save_annotation(&1, id))}
  end

  def handle_event("edit_annotation", %{"id" => id}, socket) do
    {:noreply, update_viewer(socket, &ViewerState.edit_annotation(&1, id))}
  end

  def handle_event("remove_annotation", %{"id" => id}, socket) do
    {:noreply, update_viewer(socket, &ViewerState.remove_annotation(&1, id))}
  end

  def handle_event("clear_annotations", _params, socket) do
    {:noreply, update_viewer(socket, &ViewerState.clear_annotations/1)}
  end

  def handle_event("write_annotations", _params, socket) do
    case ViewerState.write_annotations(socket.assigns.viewer) do
      :ok -> {:noreply, push_event(socket, "write_feedback", %{status: "ok"})}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("strip_annotations", _params, socket) do
    ViewerState.strip_annotations(socket.assigns.viewer)
    {:noreply, socket}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  # --- Render ---

  def render(assigns) do
    ~H"""
    <div id="projects-viewer">
      <div :if={is_nil(@viewer.html)} class="cb-placeholder">
        <div class="cb-placeholder-inner">
          <div class="cb-placeholder-title">Select a file</div>
          <div class="cb-placeholder-hint">Choose a file from the sidebar</div>
        </div>
      </div>

      <div :if={@viewer.html} class={"cb-content-wrap#{if @content_width == "narrow", do: " cb-content-wrap--narrow", else: ""}"}>
        <div class="cb-content-toolbar">
          <div class="cb-toolbar-left">
            <div class="cb-file-header">{@viewer.selected}</div>
            <div class="cb-header-actions">
              <button
                :if={length(@viewer.versions) >= 2}
                phx-click="toggle_diff"
                phx-target={@myself}
                class={"cb-action-btn#{if @viewer.view_mode == :diff, do: " cb-action-btn--active", else: ""}"}
              >
                Diff
              </button>
              <button
                :if={@viewer.versions != []}
                phx-click="toggle_versions"
                phx-target={@myself}
                class={"cb-action-btn#{if @viewer.show_versions, do: " cb-action-btn--active", else: ""}"}
              >
                History ({length(@viewer.versions)})
              </button>
              <button
                :if={@viewer.view_mode == :rendered}
                phx-click="toggle_inspector"
                phx-target={@myself}
                class={"cb-action-btn#{if @viewer.show_annotation_panel, do: " cb-action-btn--active", else: ""}"}
              >
                Annotate
              </button>
            </div>
          </div>
          <div class="cb-display-controls">
            <button phx-click="toggle_width" class={"cb-width-toggle#{if @content_width == "narrow", do: " cb-width-toggle--active", else: ""}"} title={"Content width: #{@content_width}"}><.icon_columns size={14} /></button>
            <button id="theme-toggle-projects" class="cb-theme-toggle" phx-hook="ThemeToggle" phx-update="ignore"><.icon_moon size={14} /></button>
            <button phx-click="font_size" phx-value-dir="down" class="cb-font-size-btn cb-font-size-btn--sm" title={"Smaller (#{@font_size}px)"}>A</button>
            <span class="cb-font-size-sep">/</span>
            <button phx-click="font_size" phx-value-dir="up" class="cb-font-size-btn cb-font-size-btn--lg" title={"Larger (#{@font_size}px)"}>A</button>
          </div>
        </div>

        <div :if={@viewer.show_versions} class="cb-version-panel">
          <div :for={{v, idx} <- Enum.with_index(@viewer.versions)} class="cb-version-item">
            <span class="cb-version-time">v{length(@viewer.versions) - idx}</span>
            <span class="cb-version-time">{format_version_time(v.timestamp)}</span>
            <span class="cb-version-size">{format_bytes(v.byte_size)}</span>
            <span class="cb-version-id">{v.id}</span>
          </div>
        </div>

        <div :if={@viewer.view_mode == :diff} class="cb-diff-controls">
          <form phx-change="select_diff_versions" phx-target={@myself}>
            <span>Compare</span>
            <select name="version_a">
              <option
                :for={{v, idx} <- Enum.with_index(@viewer.versions)}
                value={v.id}
                selected={@viewer.diff_version_a == v.id}
              >
                v{length(@viewer.versions) - idx} ({v.id})
              </option>
            </select>
            <span>vs</span>
            <select name="version_b">
              <option
                :for={{v, idx} <- Enum.with_index(@viewer.versions)}
                value={v.id}
                selected={@viewer.diff_version_b == v.id}
              >
                v{length(@viewer.versions) - idx} ({v.id})
              </option>
            </select>
          </form>
        </div>

        <div :if={@viewer.view_mode == :diff && @viewer.diff_html} class="cb-diff-view">
          {Phoenix.HTML.raw(@viewer.diff_html)}
        </div>

        <div :if={@viewer.view_mode == :rendered && @viewer.inspector_mode} class="cb-inspector-banner">
          Click any block to annotate &middot; Press <kbd>a</kbd> or <kbd>Esc</kbd> to exit
        </div>

        <div
          :if={@viewer.view_mode == :rendered}
          id="project-file-content"
          class={"cp-content#{if @viewer.inspector_mode, do: " cb-inspector-active", else: ""}"}
          phx-hook="PlanContent"
          phx-update="replace"
          phx-target={@myself}
          data-highlight={@content_highlight}
          data-inspector={to_string(@viewer.inspector_mode)}
          data-annotations={Jason.encode!(Enum.map(@viewer.annotations, & &1.block_index))}
          style={"font-size: #{@font_size}px"}
        >
          {Phoenix.HTML.raw(@viewer.html)}
        </div>
      </div>
    </div>
    """
  end

  # --- Internal ---

  defp load_file(%{assigns: %{project_path: nil}} = socket, _rel_path), do: socket

  defp load_file(socket, rel_path) do
    project_path = socket.assigns.project_path
    full_path = Path.join(project_path, rel_path)
    version_key = Projects.version_key(full_path)

    case File.read(full_path) do
      {:ok, content} ->
        VersionStore.snapshot_file(version_key, full_path)
        VersionStore.mark_checked(version_key)

        viewer =
          ViewerState.load_file(%ViewerState{}, rel_path, full_path, version_key)
          |> Map.put(:html, RenderCache.render(content))
          |> Map.put(:versions, VersionStore.list_versions(version_key))
          |> Map.put(:has_file_annotations, Annotations.present?(content))

        assign(socket, viewer: viewer)

      {:error, _} ->
        socket
    end
  end

  defp refresh_current_file(socket) do
    update_viewer(socket, &ViewerState.refresh_on_file_change/1)
  end

  defp update_viewer(socket, fun) do
    viewer = fun.(socket.assigns.viewer)
    notify_annotation_state(socket.assigns.viewer, viewer)
    assign(socket, viewer: viewer)
  end

  defp notify_annotation_state(old_viewer, new_viewer) do
    if annotation_state_changed?(old_viewer, new_viewer) do
      send(
        self(),
        {:projects_annotation_state,
         %{
           show_annotation_panel: new_viewer.show_annotation_panel,
           inspector_mode: new_viewer.inspector_mode,
           annotations: new_viewer.annotations,
           annotation_counter: new_viewer.annotation_counter,
           editing_annotation: new_viewer.editing_annotation,
           has_file_annotations: new_viewer.has_file_annotations,
           selected: new_viewer.selected
         }}
      )
    end
  end

  defp annotation_state_changed?(old, new) do
    old.show_annotation_panel != new.show_annotation_panel or
      old.annotations != new.annotations or
      old.editing_annotation != new.editing_annotation or
      old.inspector_mode != new.inspector_mode or
      old.has_file_annotations != new.has_file_annotations
  end

  defp handle_keyboard(socket, "toggle_diff", _params),
    do: update_viewer(socket, &ViewerState.toggle_diff/1)

  defp handle_keyboard(socket, "toggle_versions", _params),
    do: update_viewer(socket, &ViewerState.toggle_versions/1)

  defp handle_keyboard(socket, "toggle_inspector", _params),
    do: update_viewer(socket, &ViewerState.toggle_inspector/1)

  defp handle_keyboard(socket, _event, _params), do: socket
end
