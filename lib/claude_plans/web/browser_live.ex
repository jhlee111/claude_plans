defmodule ClaudePlans.Web.BrowserLive do
  use Phoenix.LiveView

  import ClaudePlans.Web.Icons

  alias ClaudePlans.Watcher
  alias ClaudePlans.RenderCache
  alias ClaudePlans.SearchIndex
  alias ClaudePlans.VersionStore
  alias ClaudePlans.ActivityFeed

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Watcher.subscribe()
      ActivityFeed.subscribe()
    end

    plans = Watcher.list_plans()
    projects_dir = ClaudePlans.projects_dir()
    projects = list_projects(projects_dir)

    {selected, html} =
      case plans do
        [first | _] -> {first.filename, RenderCache.render(File.read!(first.path))}
        [] -> {nil, nil}
      end

    {:ok,
     assign(socket,
       active_tab: :plans,
       plans: plans,
       selected: selected,
       html: html,
       projects: projects,
       selected_project: nil,
       project_files: [],
       selected_file: nil,
       file_html: nil,
       projects_dir: projects_dir,
       search_query: "",
       search_results: [],
       content_highlight: nil,
       show_help: false,
       view_mode: :rendered,
       diff_html: nil,
       versions: [],
       diff_version_a: nil,
       diff_version_b: nil,
       show_versions: false,
       font_size: 16,
       activity_events: ActivityFeed.list_events(),
       unseen_activity_count: 0,
       inspector_mode: false,
       annotations: [],
       annotation_counter: 0,
       editing_annotation: nil,
       show_annotation_panel: false
     )}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      case tab do
        :projects
        when is_nil(socket.assigns.selected_project) and socket.assigns.projects != [] ->
          [first | _] = socket.assigns.projects
          load_project(socket, first.dir_name)

        _ ->
          socket
      end

    socket =
      if tab == :activity do
        assign(socket, unseen_activity_count: 0)
      else
        socket
      end

    {:noreply, assign(socket, active_tab: tab, content_highlight: nil)}
  end

  def handle_event("select_plan", %{"filename" => filename}, socket) do
    path = Path.join(ClaudePlans.plans_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        VersionStore.snapshot(filename)
        versions = VersionStore.list_versions(filename)

        # Pre-render nearby plans in background
        plans = socket.assigns.plans
        idx = Enum.find_index(plans, &(&1.filename == filename)) || 0
        nearby_paths = Enum.map(plans, & &1.path)
        RenderCache.prerender_nearby(nearby_paths, idx)

        {:noreply,
         assign(socket,
           selected: filename,
           html: RenderCache.render(content),
           content_highlight: nil,
           versions: versions,
           view_mode: :rendered,
           diff_html: nil,
           diff_version_a: nil,
           diff_version_b: nil,
           show_versions: false,
           annotations: [],
           annotation_counter: 0,
           inspector_mode: false,
           show_annotation_panel: false,
           editing_annotation: nil
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("select_project", %{"project" => ""}, socket), do: {:noreply, socket}

  def handle_event("select_project", %{"project" => dir_name}, socket) do
    {:noreply, load_project(socket, dir_name)}
  end

  def handle_event("select_file", %{"path" => rel_path}, socket) do
    full_path =
      Path.join([socket.assigns.projects_dir, socket.assigns.selected_project, rel_path])

    case File.read(full_path) do
      {:ok, content} ->
        # Pre-render nearby project files in background
        project_files = socket.assigns.project_files
        idx = Enum.find_index(project_files, &(&1.rel_path == rel_path)) || 0
        base = Path.join(socket.assigns.projects_dir, socket.assigns.selected_project)
        nearby_paths = Enum.map(project_files, &Path.join(base, &1.rel_path))
        RenderCache.prerender_nearby(nearby_paths, idx)

        {:noreply,
         assign(socket,
           selected_file: rel_path,
           file_html: RenderCache.render(content),
           content_highlight: nil
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # --- Search ---

  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    results = if query == "", do: [], else: SearchIndex.search(query)

    # Pre-render search result files in background
    if results != [] do
      paths = search_result_paths(results, socket.assigns.projects_dir)
      RenderCache.prerender(paths)
    end

    {:noreply,
     assign(socket,
       search_query: query,
       search_results: results,
       content_highlight: nil
     )}
  end

  def handle_event("confirm_search", _params, socket) do
    query = socket.assigns.search_query
    highlight = if query != "", do: query, else: nil
    {:noreply, assign(socket, content_highlight: highlight)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     assign(socket,
       search_query: "",
       search_results: [],
       content_highlight: nil
     )}
  end

  def handle_event("select_search_result", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case Enum.at(socket.assigns.search_results, idx) do
      nil -> {:noreply, socket}
      result -> select_search_result(socket, result)
    end
  end

  # --- Diff / Version History ---

  def handle_event("toggle_diff", _params, socket) do
    case socket.assigns.view_mode do
      :rendered when length(socket.assigns.versions) >= 2 ->
        [latest, previous | _] = socket.assigns.versions
        diff_html = VersionStore.diff(socket.assigns.selected, previous.id, latest.id)

        {:noreply,
         assign(socket,
           view_mode: :diff,
           diff_html: diff_html,
           diff_version_a: previous.id,
           diff_version_b: latest.id
         )}

      :diff ->
        {:noreply, assign(socket, view_mode: :rendered)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_versions", _params, socket) do
    {:noreply, assign(socket, show_versions: !socket.assigns.show_versions)}
  end

  def handle_event("select_diff_versions", %{"version_a" => id_a, "version_b" => id_b}, socket) do
    diff_html = VersionStore.diff(socket.assigns.selected, id_a, id_b)

    {:noreply,
     assign(socket,
       diff_html: diff_html,
       diff_version_a: id_a,
       diff_version_b: id_b
     )}
  end

  # --- Keyboard Navigation ---

  def handle_event("kb_navigate", %{"direction" => dir}, socket) do
    list = visible_list(socket)
    max_idx = max(length(list) - 1, 0)

    current =
      if socket.assigns.search_query != "" do
        current_search_result_index(socket)
      else
        current_selection_index(socket)
      end

    new_idx =
      case {dir, current} do
        {_, _} when list == [] -> nil
        {"top", _} -> 0
        {"bottom", _} -> max_idx
        {"down", nil} -> 0
        {"down", i} when i >= max_idx -> max_idx
        {"down", i} -> i + 1
        {"up", nil} -> max_idx
        {"up", 0} -> 0
        {"up", i} -> i - 1
      end

    if new_idx != nil do
      case Enum.at(list, new_idx) do
        nil ->
          {:noreply, socket}

        item ->
          if socket.assigns.search_query != "" do
            select_search_result(socket, item)
          else
            select_visible_item(socket, item)
          end
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("kb_select", _params, socket) do
    list = visible_list(socket)

    idx =
      if socket.assigns.search_query != "" do
        current_search_result_index(socket)
      else
        current_selection_index(socket)
      end

    case Enum.at(list, idx || -1) do
      nil ->
        {:noreply, socket}

      item ->
        if socket.assigns.search_query != "" do
          select_search_result(socket, item)
        else
          select_visible_item(socket, item)
        end
    end
  end

  def handle_event("kb_next_result", _params, socket) do
    navigate_search_result(socket, :next)
  end

  def handle_event("kb_prev_result", _params, socket) do
    navigate_search_result(socket, :prev)
  end

  def handle_event("kb_escape", _params, socket) do
    socket =
      cond do
        socket.assigns.inspector_mode ->
          assign(socket, inspector_mode: false)

        socket.assigns.show_annotation_panel ->
          assign(socket, show_annotation_panel: false)

        socket.assigns.view_mode == :diff ->
          assign(socket, view_mode: :rendered)

        socket.assigns.show_versions ->
          assign(socket, show_versions: false)

        socket.assigns.show_help ->
          assign(socket, show_help: false)

        socket.assigns.content_highlight != nil ->
          assign(socket, content_highlight: nil)

        socket.assigns.search_query != "" ->
          assign(socket,
            search_query: "",
            search_results: [],
            content_highlight: nil
          )

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("kb_tab", %{"tab" => tab}, socket) do
    socket =
      assign(socket,
        search_query: "",
        search_results: [],
        content_highlight: nil
      )

    handle_event("switch_tab", %{"tab" => tab}, socket)
  end

  def handle_event("kb_help", _params, socket) do
    {:noreply, assign(socket, show_help: !socket.assigns.show_help)}
  end

  def handle_event("font_size", %{"dir" => "up"}, socket) do
    {:noreply, assign(socket, font_size: min(socket.assigns.font_size + 2, 28))}
  end

  def handle_event("font_size", %{"dir" => "down"}, socket) do
    {:noreply, assign(socket, font_size: max(socket.assigns.font_size - 2, 10))}
  end

  def handle_event("font_size", %{"dir" => "reset"}, socket) do
    {:noreply, assign(socket, font_size: 16)}
  end

  def handle_event("select_activity_event", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case Enum.at(socket.assigns.activity_events, idx) do
      nil ->
        {:noreply, socket}

      %{category: :plan, filename: filename} ->
        socket = assign(socket, content_highlight: nil)

        handle_event("switch_tab", %{"tab" => "plans"}, socket)
        |> then(fn {:noreply, socket} ->
          handle_event("select_plan", %{"filename" => filename}, socket)
        end)

      %{category: cat, project: project, rel_path: rel_path}
      when cat in [:project_memory, :project_config] ->
        socket =
          socket
          |> assign(content_highlight: nil)
          |> load_project(project)
          |> assign(active_tab: :projects)

        handle_event("select_file", %{"path" => rel_path}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("kb_delete", _params, socket) do
    case selected_file_path(socket) do
      nil -> {:noreply, socket}
      path -> {:noreply, push_event(socket, "confirm_delete", %{path: path})}
    end
  end

  def handle_event("kb_edit", _params, socket) do
    case selected_file_path(socket) do
      nil ->
        {:noreply, socket}

      path ->
        case editor_url(path) do
          nil -> {:noreply, socket}
          url -> {:noreply, push_event(socket, "open_editor", %{url: url})}
        end
    end
  end

  def handle_event("delete_file", %{"path" => path}, socket) do
    File.rm(path)

    socket =
      case socket.assigns.active_tab do
        :plans ->
          plans = Watcher.list_plans()

          {selected, html} =
            case plans do
              [first | _] -> {first.filename, RenderCache.render(File.read!(first.path))}
              [] -> {nil, nil}
            end

          assign(socket, plans: plans, selected: selected, html: html)

        :projects ->
          files =
            list_project_files(socket.assigns.projects_dir, socket.assigns.selected_project)

          {selected_file, file_html} =
            case files do
              [first | _] ->
                full =
                  Path.join([
                    socket.assigns.projects_dir,
                    socket.assigns.selected_project,
                    first.rel_path
                  ])

                {first.rel_path, RenderCache.render(File.read!(full))}

              [] ->
                {nil, nil}
            end

          assign(socket,
            project_files: files,
            selected_file: selected_file,
            file_html: file_html
          )

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # --- Annotations ---

  def handle_event("toggle_inspector", _params, socket) do
    showing = !socket.assigns.show_annotation_panel

    {:noreply,
     assign(socket,
       show_annotation_panel: showing,
       inspector_mode: showing
     )}
  end

  def handle_event("add_annotation", %{"block_path" => block_path, "block_index" => block_index}, socket) do
    counter = socket.assigns.annotation_counter + 1
    id = "A#{counter}"

    annotation = %{
      id: id,
      block_path: block_path,
      block_index: block_index,
      direction: ""
    }

    {:noreply,
     assign(socket,
       annotations: socket.assigns.annotations ++ [annotation],
       annotation_counter: counter,
       editing_annotation: id
     )}
  end

  def handle_event("update_annotation", %{"id" => id, "direction" => direction}, socket) do
    annotations =
      Enum.map(socket.assigns.annotations, fn ann ->
        if ann.id == id, do: %{ann | direction: direction}, else: ann
      end)

    {:noreply, assign(socket, annotations: annotations)}
  end

  def handle_event("save_annotation", %{"id" => id}, socket) do
    # Direction is already saved via phx-change; this just exits edit mode
    _ = id
    {:noreply, assign(socket, editing_annotation: nil)}
  end

  def handle_event("edit_annotation", %{"id" => id}, socket) do
    {:noreply, assign(socket, editing_annotation: id)}
  end

  def handle_event("remove_annotation", %{"id" => id}, socket) do
    annotations = Enum.reject(socket.assigns.annotations, &(&1.id == id))
    {:noreply, assign(socket, annotations: annotations, editing_annotation: nil)}
  end

  def handle_event("clear_annotations", _params, socket) do
    {:noreply, assign(socket, annotations: [], annotation_counter: 0, inspector_mode: false, editing_annotation: nil)}
  end

  # --- PubSub ---

  @impl true
  def handle_info({:plan_updated, _filename}, socket) do
    plans = Watcher.list_plans()

    {selected, html} =
      if socket.assigns.selected do
        case Enum.find(plans, &(&1.filename == socket.assigns.selected)) do
          nil ->
            case plans do
              [first | _] -> {first.filename, RenderCache.render(File.read!(first.path))}
              [] -> {nil, nil}
            end

          plan ->
            {plan.filename, RenderCache.render(File.read!(plan.path))}
        end
      else
        case plans do
          [first | _] -> {first.filename, RenderCache.render(File.read!(first.path))}
          [] -> {nil, nil}
        end
      end

    socket = assign(socket, plans: plans, selected: selected, html: html)

    # Refresh versions for selected plan
    socket =
      if selected do
        versions = VersionStore.list_versions(selected)
        socket = assign(socket, versions: versions)

        # If in diff mode, recompute diff with current selections
        if socket.assigns.view_mode == :diff && socket.assigns.diff_version_a &&
             socket.assigns.diff_version_b do
          diff_html =
            VersionStore.diff(
              selected,
              socket.assigns.diff_version_a,
              socket.assigns.diff_version_b
            )

          assign(socket, diff_html: diff_html)
        else
          socket
        end
      else
        assign(socket, versions: [], view_mode: :rendered, diff_html: nil)
      end

    {:noreply, socket}
  end

  def handle_info({:activity_event, event}, socket) do
    events = [event | socket.assigns.activity_events] |> Enum.take(100)

    unseen =
      if socket.assigns.active_tab == :activity do
        0
      else
        socket.assigns.unseen_activity_count + 1
      end

    {:noreply, assign(socket, activity_events: events, unseen_activity_count: unseen)}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div id="kb-nav" class="cb-layout" phx-hook="KeyboardNav">
      <div class="cb-sidebar">
        <div class="cb-tabs">
          <button
            :for={{id, label} <- [{:plans, "Plans"}, {:projects, "Projects"}, {:activity, "Activity"}]}
            phx-click="switch_tab"
            phx-value-tab={id}
            class={"cb-tab#{if @active_tab == id, do: " cb-tab--active", else: ""}"}
          >
            {label}
            <span :if={id == :activity && @unseen_activity_count > 0} class="cb-badge">
              {@unseen_activity_count}
            </span>
          </button>
          <button phx-click="kb_help" class="cb-help-btn" title="Keyboard shortcuts"><.icon_help size={14} /></button>
          <button id="theme-toggle" class="cb-theme-toggle" phx-hook="ThemeToggle" phx-update="ignore"><.icon_moon size={14} /></button>
          <button phx-click="font_size" phx-value-dir="down" class="cb-font-size-btn cb-font-size-btn--sm" title={"Smaller (current: #{@font_size}px)"}>A</button>
          <span class="cb-font-size-sep">/</span>
          <button phx-click="font_size" phx-value-dir="up" class="cb-font-size-btn cb-font-size-btn--lg" title={"Larger (current: #{@font_size}px)"}>A</button>
        </div>
        <div class="cb-sidebar-body">
          <div class="cb-search-wrap">
            <form phx-change="search" phx-submit="search">
              <input
                id="search-input"
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search files... (press /)"
                autocomplete="off"
                phx-debounce="300"
                class="cb-search-input"
              />
            </form>
            <button :if={@search_query != ""} phx-click="clear_search" class="cb-search-clear" title="Clear search (Esc)"><.icon_x size={12} /></button>
          </div>
          <%= if @search_query != "" do %>
            {search_results_content(assigns)}
          <% else %>
            {sidebar_content(assigns)}
          <% end %>
        </div>
      </div>
      <div class="cb-main">
        {main_content(assigns)}
      </div>
      <div :if={@active_tab == :plans && @show_annotation_panel} class="cb-annotation-panel">
        <div class="cb-annotation-header">
          <span class="cb-section-label">Annotations</span>
          <span :if={@annotations != []} class="cb-count">({length(@annotations)})</span>
          <button :if={@annotations != []} phx-click="clear_annotations" class="cb-annotation-clear">Clear all</button>
        </div>
        <div class="cb-annotation-body">
          <div :if={@annotations == []} class="cb-annotation-empty">
            Click any block in the plan to annotate it
          </div>
          <div :for={ann <- @annotations} class="cb-annotation-card" id={"ann-#{ann.id}"}>
            <div class="cb-annotation-card-header">
              <span class="cb-annotation-label">{ann.id}</span>
              <button phx-click="remove_annotation" phx-value-id={ann.id} class="cb-annotation-remove" title="Remove">&times;</button>
            </div>
            <div class="cb-annotation-ref">{ann.block_path}</div>
            <%= if @editing_annotation == ann.id do %>
              <form phx-change="update_annotation" phx-value-id={ann.id}>
                <textarea
                  id={"ann-input-#{ann.id}"}
                  name="direction"
                  class="cb-annotation-input"
                  placeholder="What should change?"
                  rows="2"
                  phx-debounce="300"
                >{ann.direction}</textarea>
              </form>
              <button phx-click="save_annotation" phx-value-id={ann.id} class="cb-annotation-save">Save</button>
            <% else %>
              <div
                phx-click="edit_annotation"
                phx-value-id={ann.id}
                class={"cb-annotation-display#{if ann.direction == "", do: " cb-annotation-display--empty", else: ""}"}
              >
                {if ann.direction == "", do: "Click to add direction...", else: ann.direction}
              </div>
            <% end %>
          </div>
        </div>
        <div :if={@annotations != []} class="cb-annotation-footer">
          <button id="copy-annotations" class="cb-annotation-copy" phx-hook="CopyAnnotations" data-filename={@selected} data-annotations={Jason.encode!(@annotations)}>
            Copy All Annotations
          </button>
        </div>
      </div>
      <div :if={@show_help} class="cb-help-overlay" phx-click="kb_help">
        <div class="cb-help-modal" phx-click="noop">
          <div class="cb-help-title">Keyboard Shortcuts</div>
          <dl class="cb-help-grid">
            <dt><kbd>j</kbd> <kbd>k</kbd></dt><dd>Navigate down / up</dd>
            <dt><kbd>gg</kbd> <kbd>G</kbd></dt><dd>Jump to top / bottom</dd>
            <dt><kbd>Enter</kbd> <kbd>l</kbd></dt><dd>Open selected item</dd>
            <dt><kbd>/</kbd></dt><dd>Focus search</dd>
            <dt><kbd>Esc</kbd></dt><dd>Exit input → clear highlight → clear search</dd>
            <dt><kbd>n</kbd> <kbd>N</kbd></dt><dd>Next / prev match in doc</dd>
            <dt><kbd>]</kbd> <kbd>[</kbd></dt><dd>Next / prev search result</dd>
            <dt><kbd>Ctrl+d</kbd> <kbd>Ctrl+u</kbd></dt><dd>Scroll content down / up</dd>
            <dt><kbd>d</kbd></dt><dd>Toggle diff view</dd>
            <dt><kbd>v</kbd></dt><dd>Toggle version history</dd>
            <dt><kbd>i</kbd></dt><dd>Toggle annotation inspector</dd>
            <dt><kbd>e</kbd></dt><dd>Open in editor (PLUG_EDITOR)</dd>
            <dt><kbd>x</kbd></dt><dd>Delete selected file</dd>
            <dt><kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd></dt><dd>Plans / Projects / Activity tab</dd>
            <dt><kbd>?</kbd></dt><dd>Toggle this help</dd>
          </dl>
        </div>
      </div>
    </div>
    """
  end

  defp search_results_content(assigns) do
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

  defp sidebar_content(%{active_tab: :plans} = assigns) do
    ~H"""
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.75rem">
      <span class="cb-section-label">Plans</span>
      <span class="cb-count">{length(@plans)}</span>
    </div>
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
        <a :if={editor_url(plan.path)} href={editor_url(plan.path)} class="cb-action-btn" title="Open in editor"><.icon_edit size={12} /></a>
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

  defp sidebar_content(%{active_tab: :projects} = assigns) do
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
            :if={editor_url(Path.join([@projects_dir, @selected_project, file.rel_path]))}
            href={editor_url(Path.join([@projects_dir, @selected_project, file.rel_path]))}
            class="cb-action-btn"
            title="Open in editor"
          ><.icon_edit size={12} /></a>
          <span
            id={"copy-file-#{file.rel_path}"}
            class="cb-action-btn"
            phx-hook="CopyPath"
            data-path={Path.join([@projects_dir, @selected_project, file.rel_path])}
            title={Path.join([@projects_dir, @selected_project, file.rel_path])}
          ><.icon_copy size={12} /></span>
          <button
            phx-click="delete_file"
            phx-value-path={Path.join([@projects_dir, @selected_project, file.rel_path])}
            data-confirm={"Delete #{Path.join([@projects_dir, @selected_project, file.rel_path])}?"}
            class="cb-action-btn cb-action-btn--danger"
            title="Delete file"
          ><.icon_trash size={12} /></button>
        </div>
      </div>
      <div :if={@project_files == []} class="cb-empty">No .md files</div>
    </div>
    """
  end

  defp sidebar_content(%{active_tab: :activity} = assigns) do
    ~H"""
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:0.75rem">
      <span class="cb-section-label">Activity</span>
      <span class="cb-count">{length(@activity_events)}</span>
    </div>
    <div :for={{event, idx} <- Enum.with_index(@activity_events)}>
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
      </button>
    </div>
    <div :if={@activity_events == []} class="cb-empty">
      No activity yet.
      <div class="cb-empty-hint">File changes will appear here in real-time</div>
    </div>
    """
  end

  defp main_content(%{active_tab: :activity} = assigns) do
    ~H"""
    <div class="cb-placeholder">
      <div class="cb-placeholder-inner">
        <div class="cb-placeholder-title">Activity Feed</div>
        <div class="cb-placeholder-hint">Click an event to view the file</div>
      </div>
    </div>
    """
  end

  defp main_content(%{active_tab: :plans} = assigns) do
    ~H"""
    <div :if={@html} class="cb-content-wrap">
      <div class="cb-content-header">
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
        Click any block to annotate &middot; Press <kbd>i</kbd> or <kbd>Esc</kbd> to exit
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

  defp main_content(%{active_tab: :projects} = assigns) do
    ~H"""
    <div :if={@file_html} class="cb-content-wrap">
      <div class="cb-file-header">{@selected_file}</div>
      <div id="project-file-content" class="cp-content" phx-hook="PlanContent" phx-update="replace" data-highlight={@content_highlight} style={"font-size: #{@font_size}px"}>
        {Phoenix.HTML.raw(@file_html)}
      </div>
    </div>
    <div :if={is_nil(@file_html)} class="cb-placeholder">
      <div class="cb-placeholder-inner">
        <div :if={is_nil(@selected_project)} class="cb-placeholder-title">Select a project</div>
        <div :if={@selected_project && is_nil(@selected_file)} class="cb-placeholder-title">Select a file</div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp navigate_search_result(socket, direction) do
    results = socket.assigns.search_results

    if results == [] do
      {:noreply, socket}
    else
      max_idx = length(results) - 1
      current = current_search_result_index(socket) || -1

      new_idx =
        case direction do
          :next -> min(current + 1, max_idx)
          :prev -> max(current - 1, 0)
        end

      case Enum.at(results, new_idx) do
        nil -> {:noreply, socket}
        result -> select_search_result(socket, result)
      end
    end
  end

  defp current_search_result_index(socket) do
    Enum.find_index(socket.assigns.search_results, fn
      %{source: :plan, filename: f} ->
        socket.assigns.selected == f

      %{source: :project, project: p, rel_path: r} ->
        socket.assigns.selected_project == p && socket.assigns.selected_file == r
    end)
  end

  defp search_result_active?(result, assigns) do
    case result do
      %{source: :plan, filename: f} ->
        assigns.selected == f

      %{source: :project, project: p, rel_path: r} ->
        assigns.selected_project == p && assigns.selected_file == r
    end
  end

  defp current_selection_index(socket) do
    case socket.assigns.active_tab do
      :plans ->
        Enum.find_index(socket.assigns.plans, &(&1.filename == socket.assigns.selected))

      :projects ->
        Enum.find_index(
          socket.assigns.project_files,
          &(&1.rel_path == socket.assigns.selected_file)
        )

      _ ->
        nil
    end
  end

  defp visible_list(socket) do
    cond do
      socket.assigns.search_query != "" -> socket.assigns.search_results
      socket.assigns.active_tab == :plans -> socket.assigns.plans
      socket.assigns.active_tab == :projects -> socket.assigns.project_files
      socket.assigns.active_tab == :activity -> socket.assigns.activity_events
      true -> []
    end
  end

  defp select_visible_item(socket, item) do
    case socket.assigns.active_tab do
      :plans ->
        handle_event("select_plan", %{"filename" => item.filename}, socket)

      :projects ->
        handle_event("select_file", %{"path" => item.rel_path}, socket)

      :activity ->
        idx = Enum.find_index(socket.assigns.activity_events, &(&1.id == item.id)) || 0
        handle_event("select_activity_event", %{"index" => to_string(idx)}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  defp select_search_result(socket, %{source: :plan} = result) do
    path = Path.join(ClaudePlans.plans_dir(), result.filename)
    highlight = socket.assigns.search_query

    case File.read(path) do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           active_tab: :plans,
           selected: result.filename,
           html: RenderCache.render(content),
           content_highlight: highlight
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp select_search_result(socket, %{source: :project, project: proj, rel_path: rel}) do
    highlight = socket.assigns.search_query

    socket =
      if socket.assigns.selected_project != proj do
        load_project(socket, proj)
      else
        socket
      end

    full_path = Path.join([socket.assigns.projects_dir, proj, rel])

    case File.read(full_path) do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           active_tab: :projects,
           selected_file: rel,
           file_html: RenderCache.render(content),
           content_highlight: highlight
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp source_label(%{source: :plan}), do: "plan"
  defp source_label(%{source: :project, project: proj}), do: "project: #{proj}"

  defp search_result_paths(results, projects_dir) do
    Enum.map(results, fn
      %{source: :plan, filename: filename} ->
        Path.join(ClaudePlans.plans_dir(), filename)

      %{source: :project, project: proj, rel_path: rel} ->
        Path.join([projects_dir, proj, rel])
    end)
  end

  defp load_project(socket, dir_name) do
    projects_dir = socket.assigns.projects_dir
    files = list_project_files(projects_dir, dir_name)

    {selected_file, file_html} =
      case files do
        [first | _] ->
          path = Path.join([projects_dir, dir_name, first.rel_path])
          {first.rel_path, RenderCache.render(File.read!(path))}

        [] ->
          {nil, nil}
      end

    # Pre-render all project files in background
    all_paths = Enum.map(files, &Path.join([projects_dir, dir_name, &1.rel_path]))
    RenderCache.prerender(all_paths)

    assign(socket,
      selected_project: dir_name,
      project_files: files,
      selected_file: selected_file,
      file_html: file_html
    )
  end

  defp list_projects(projects_dir) do
    case File.ls(projects_dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(&File.dir?(Path.join(projects_dir, &1)))
        |> Enum.map(fn dir_name ->
          candidate = "/" <> (dir_name |> String.trim_leading("-") |> String.replace("-", "/"))

          display =
            if File.dir?(candidate) do
              Path.relative_to(candidate, System.user_home!()) |> then(&"~/#{&1}")
            else
              dir_name |> String.trim_leading("-Users-#{System.get_env("USER", "user")}-")
            end

          has_memory? = File.dir?(Path.join([projects_dir, dir_name, "memory"]))
          %{dir_name: dir_name, display_name: display, has_memory?: has_memory?}
        end)
        |> Enum.filter(& &1.has_memory?)
        |> Enum.sort_by(& &1.display_name)

      {:error, _} ->
        []
    end
  end

  defp list_project_files(projects_dir, dir_name) do
    project_path = Path.join(projects_dir, dir_name)
    root_files = list_md_files(project_path, nil)
    memory_files = list_md_files(Path.join(project_path, "memory"), "memory")
    (root_files ++ memory_files) |> Enum.sort_by(fn f -> {f.dir || "", f.name} end)
  end

  defp list_md_files(dir, subdir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn name ->
          rel_path = if subdir, do: Path.join(subdir, name), else: name
          %{name: name, dir: subdir, rel_path: rel_path}
        end)

      {:error, _} ->
        []
    end
  end

  defp format_time(posix_time) when is_integer(posix_time) do
    now = System.os_time(:second)
    diff = now - posix_time

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 86400 * 30 -> "#{div(diff, 86400)}d ago"
      true -> posix_time |> DateTime.from_unix!() |> Calendar.strftime("%b %d, %Y")
    end
  end

  defp format_version_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      true -> "#{bytes} B"
    end
  end

  defp selected_file_path(socket) do
    case socket.assigns.active_tab do
      :plans ->
        case Enum.find(socket.assigns.plans, &(&1.filename == socket.assigns.selected)) do
          nil -> nil
          plan -> plan.path
        end

      :projects ->
        if socket.assigns.selected_project && socket.assigns.selected_file do
          Path.join([
            socket.assigns.projects_dir,
            socket.assigns.selected_project,
            socket.assigns.selected_file
          ])
        end

      _ ->
        nil
    end
  end

  defp action_icon(:created), do: "+"
  defp action_icon(:updated), do: "~"
  defp action_icon(:deleted), do: "-"

  defp category_label(:plan), do: "plan"
  defp category_label(:project_memory), do: "memory"
  defp category_label(:project_config), do: "config"

  defp format_project_name(dir_name) do
    candidate = "/" <> (dir_name |> String.trim_leading("-") |> String.replace("-", "/"))

    if File.dir?(candidate) do
      Path.relative_to(candidate, System.user_home!()) |> then(&"~/#{&1}")
    else
      dir_name |> String.trim_leading("-Users-#{System.get_env("USER", "user")}-")
    end
  end

  defp editor_url(file_path) do
    case System.get_env("PLUG_EDITOR") do
      nil ->
        nil

      template ->
        template
        |> String.replace("__FILE__", URI.encode(file_path))
        |> String.replace("__LINE__", "1")
    end
  end
end
