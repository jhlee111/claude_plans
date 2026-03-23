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

    font_size =
      if connected?(socket) do
        case get_connect_params(socket) do
          %{"font_size" => size} when is_integer(size) and size >= 10 and size <= 28 -> size
          _ -> 16
        end
      else
        16
      end

    plans = Watcher.list_plans()
    projects_dir = ClaudePlans.projects_dir()
    projects = list_projects(projects_dir)

    {:ok,
     assign(socket,
       active_tab: :plans,
       plans: plans,
       selected: nil,
       html: nil,
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
       font_size: font_size,
       activity_events: ActivityFeed.list_events(),
       unseen_activity_count: 0,
       unchecked_plan_files: VersionStore.unchecked_files(),
       inspector_mode: false,
       annotations: [],
       annotation_counter: 0,
       editing_annotation: nil,
       show_annotation_panel: false,
       has_file_annotations: false,
       selected_activity_index: nil,
       activity_diff_html: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = parse_tab(params["tab"])
    query = params["q"] || ""

    socket =
      socket
      |> apply_tab_switch(tab)
      |> apply_plan_selection(tab, params["plan"])
      |> apply_project_selection(tab, params["project"], params["file"])
      |> apply_search(query)
      |> apply_view_mode(tab, params["view"])

    {:noreply, socket}
  end

  defp apply_tab_switch(socket, tab) when tab == socket.assigns.active_tab, do: socket

  defp apply_tab_switch(socket, :projects) do
    socket = assign(socket, active_tab: :projects, content_highlight: nil)

    if is_nil(socket.assigns.selected_project) and socket.assigns.projects != [] do
      [first | _] = socket.assigns.projects
      load_project(socket, first.dir_name)
    else
      socket
    end
  end

  defp apply_tab_switch(socket, :activity) do
    assign(socket,
      active_tab: :activity,
      content_highlight: nil,
      unseen_activity_count: 0,
      selected_activity_index: nil,
      activity_diff_html: nil
    )
  end

  defp apply_tab_switch(socket, tab) do
    assign(socket, active_tab: tab, content_highlight: nil)
  end

  defp apply_plan_selection(socket, :plans, plan_param) do
    resolved_plan = resolve_plan(plan_param, socket)

    if resolved_plan && resolved_plan != socket.assigns.selected do
      load_plan_state(socket, resolved_plan)
    else
      socket
    end
  end

  defp apply_plan_selection(socket, _tab, _plan_param), do: socket

  defp apply_project_selection(socket, :projects, project, file) do
    socket = apply_project_change(socket, project)
    apply_file_change(socket, file)
  end

  defp apply_project_selection(socket, _tab, _project, _file), do: socket

  defp apply_project_change(socket, project)
       when is_binary(project) and project != "" do
    if project != socket.assigns.selected_project and
         Enum.any?(socket.assigns.projects, &(&1.dir_name == project)) do
      load_project(socket, project)
    else
      socket
    end
  end

  defp apply_project_change(socket, _project), do: socket

  defp apply_file_change(socket, file)
       when is_binary(file) and file != "" do
    if file != socket.assigns.selected_file and socket.assigns.selected_project do
      load_file_state(socket, file)
    else
      socket
    end
  end

  defp apply_file_change(socket, _file), do: socket

  defp apply_search(socket, query) when query == socket.assigns.search_query, do: socket

  defp apply_search(socket, ""),
    do: assign(socket, search_query: "", search_results: [], content_highlight: nil)

  defp apply_search(socket, query) do
    results = SearchIndex.search(query)
    prerender_search_results(results, socket.assigns.projects_dir)
    assign(socket, search_query: query, search_results: results, content_highlight: nil)
  end

  defp prerender_search_results([], _projects_dir), do: :ok

  defp prerender_search_results(results, projects_dir) do
    paths = search_result_paths(results, projects_dir)
    RenderCache.prerender(paths)
  end

  defp apply_view_mode(socket, :plans, "diff") do
    if socket.assigns.view_mode != :diff and length(socket.assigns.versions) >= 2 do
      [latest, previous | _] = socket.assigns.versions
      diff_html = VersionStore.diff(socket.assigns.selected, previous.id, latest.id)

      assign(socket,
        view_mode: :diff,
        diff_html: diff_html,
        diff_version_a: previous.id,
        diff_version_b: latest.id
      )
    else
      socket
    end
  end

  defp apply_view_mode(socket, _tab, _view), do: socket

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket, to: build_url_params(socket, %{tab: String.to_existing_atom(tab)}))}
  end

  def handle_event("select_plan", %{"filename" => filename}, socket) do
    {:noreply,
     push_patch(socket, to: build_url_params(socket, %{plan: filename, view: :rendered}))}
  end

  def handle_event("select_project", %{"project" => ""}, socket), do: {:noreply, socket}

  def handle_event("select_project", %{"project" => dir_name}, socket) do
    {:noreply,
     push_patch(socket,
       to: build_url_params(socket, %{tab: :projects, project: dir_name, file: nil})
     )}
  end

  def handle_event("select_file", %{"path" => rel_path}, socket) do
    {:noreply, push_patch(socket, to: build_url_params(socket, %{file: rel_path}))}
  end

  # --- Search ---

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     push_patch(socket, to: build_url_params(socket, %{q: String.trim(query)}), replace: true)}
  end

  def handle_event("confirm_search", _params, socket) do
    query = socket.assigns.search_query
    highlight = if query != "", do: query, else: nil
    {:noreply, assign(socket, content_highlight: highlight)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: build_url_params(socket, %{q: ""}))}
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
         socket
         |> assign(
           view_mode: :diff,
           diff_html: diff_html,
           diff_version_a: previous.id,
           diff_version_b: latest.id
         )
         |> push_patch(to: build_url_params(socket, %{view: :diff}), replace: true)}

      :diff ->
        {:noreply,
         socket
         |> assign(view_mode: :rendered)
         |> push_patch(to: build_url_params(socket, %{view: :rendered}), replace: true)}

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
    current = kb_current_index(socket)
    new_idx = kb_resolve_index(dir, current, max_idx, list)

    kb_apply_navigation(socket, list, new_idx)
  end

  def handle_event("kb_select", _params, socket) do
    if socket.assigns.active_tab == :activity and socket.assigns.search_query == "" do
      handle_event("goto_activity_file", %{}, socket)
    else
      kb_select_from_list(socket)
    end
  end

  def handle_event("kb_next_result", _params, socket) do
    navigate_search_result(socket, :next)
  end

  def handle_event("kb_prev_result", _params, socket) do
    navigate_search_result(socket, :prev)
  end

  def handle_event("kb_escape", _params, socket) do
    {:noreply, dismiss_topmost_layer(socket)}
  end

  def handle_event("kb_tab", %{"tab" => tab}, socket) do
    socket =
      assign(socket,
        search_query: "",
        search_results: [],
        content_highlight: nil,
        selected_activity_index: nil,
        activity_diff_html: nil
      )

    handle_event("switch_tab", %{"tab" => tab}, socket)
  end

  def handle_event("kb_help", _params, socket) do
    {:noreply, assign(socket, show_help: !socket.assigns.show_help)}
  end

  def handle_event("font_size", %{"dir" => "up"}, socket) do
    size = min(socket.assigns.font_size + 2, 28)

    {:noreply,
     socket |> assign(font_size: size) |> push_event("save_preferences", %{font_size: size})}
  end

  def handle_event("font_size", %{"dir" => "down"}, socket) do
    size = max(socket.assigns.font_size - 2, 10)

    {:noreply,
     socket |> assign(font_size: size) |> push_event("save_preferences", %{font_size: size})}
  end

  def handle_event("font_size", %{"dir" => "reset"}, socket) do
    {:noreply,
     socket |> assign(font_size: 16) |> push_event("save_preferences", %{font_size: 16})}
  end

  def handle_event("select_activity_event", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case Enum.at(socket.assigns.activity_events, idx) do
      nil ->
        {:noreply, socket}

      event ->
        diff_html = compute_activity_diff(event)

        {:noreply,
         assign(socket,
           selected_activity_index: idx,
           activity_diff_html: diff_html
         )}
    end
  end

  def handle_event("goto_activity_file_at", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    socket = assign(socket, selected_activity_index: idx)
    handle_event("goto_activity_file", %{}, socket)
  end

  def handle_event("goto_activity_file", _params, socket) do
    case Enum.at(socket.assigns.activity_events, socket.assigns.selected_activity_index || -1) do
      nil ->
        {:noreply, socket}

      %{category: :plan, filename: filename} ->
        socket = assign(socket, content_highlight: nil)
        navigate_to_plan_diff(socket, filename)

      %{category: cat, project: project, rel_path: rel_path}
      when cat in [:project_memory, :project_config] ->
        {:noreply,
         push_patch(socket,
           to: build_url_params(socket, %{tab: :projects, project: project, file: rel_path})
         )}

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

  def handle_event(
        "add_annotation",
        %{"block_path" => block_path, "block_index" => block_index},
        socket
      ) do
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
    {:noreply,
     assign(socket,
       annotations: [],
       annotation_counter: 0,
       inspector_mode: false,
       editing_annotation: nil
     )}
  end

  def handle_event("write_annotations_to_file", _params, socket) do
    path = Path.join(ClaudePlans.plans_dir(), socket.assigns.selected)
    annotations = socket.assigns.annotations

    case File.read(path) do
      {:ok, content} ->
        updated = inject_annotations(content, annotations)
        File.write!(path, updated)
        {:noreply, push_event(socket, "write_feedback", %{status: "ok"})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("strip_annotations_from_file", _params, socket) do
    path = Path.join(ClaudePlans.plans_dir(), socket.assigns.selected)

    case File.read(path) do
      {:ok, content} ->
        cleaned = strip_annotations(content)
        File.write!(path, cleaned <> "\n")
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # --- PubSub ---

  @impl true
  def handle_info({:plan_updated, _filename}, socket) do
    plans = Watcher.list_plans()
    {selected, html} = resolve_selected_plan(plans, socket.assigns.selected)
    has_annotations = check_annotations(selected)

    socket =
      socket
      |> assign(
        plans: plans,
        selected: selected,
        html: html,
        has_file_annotations: has_annotations
      )
      |> refresh_versions(selected)

    {:noreply, assign(socket, unchecked_plan_files: VersionStore.unchecked_files())}
  end

  def handle_info({:activity_event, event}, socket) do
    events = [event | socket.assigns.activity_events] |> Enum.take(100)

    unseen =
      if socket.assigns.active_tab == :activity do
        0
      else
        socket.assigns.unseen_activity_count + 1
      end

    unchecked =
      if event.category == :plan do
        VersionStore.unchecked_files()
      else
        socket.assigns.unchecked_plan_files
      end

    selected_idx =
      case socket.assigns.selected_activity_index do
        nil -> nil
        idx -> idx + 1
      end

    {:noreply,
     assign(socket,
       activity_events: events,
       unseen_activity_count: unseen,
       unchecked_plan_files: unchecked,
       selected_activity_index: selected_idx
     )}
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
          <button id="write-annotations" class="cb-annotation-write" phx-hook="WriteAnnotations" phx-click="write_annotations_to_file">
            Write to Plan File
          </button>
        </div>
        <div :if={@annotations == [] && @has_file_annotations} class="cb-annotation-footer">
          <button phx-click="strip_annotations_from_file" class="cb-annotation-strip">
            Strip Annotations from File
          </button>
        </div>
      </div>
      <div :if={@show_help} class="cb-help-overlay" phx-click="kb_help">
        <div class="cb-help-modal" phx-click="noop">
          <div class="cb-help-title">Keyboard Shortcuts</div>
          <dl class="cb-help-grid">
            <dt><kbd>j</kbd> <kbd>k</kbd></dt><dd>Navigate down / up</dd>
            <dt><kbd>gg</kbd> <kbd>G</kbd></dt><dd>Jump to top / bottom</dd>
            <dt><kbd>Enter</kbd> <kbd>l</kbd></dt><dd>Open selected / Go to file (activity)</dd>
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

  defp main_content(%{active_tab: :activity} = assigns) do
    selected_event =
      if assigns.selected_activity_index do
        Enum.at(assigns.activity_events, assigns.selected_activity_index)
      end

    assigns = assign(assigns, :selected_event, selected_event)

    ~H"""
    <div :if={@activity_diff_html && @selected_event} class="cb-content-wrap">
      <div class="cb-content-header">
        <div class="cb-file-header">{@selected_event.display_name}</div>
        <div class="cb-header-actions">
          <button phx-click="goto_activity_file" class="cb-action-btn" title="Go to file (Enter)">
            Go to file &rarr;
          </button>
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

  defp compute_activity_diff(%{category: :plan, filename: filename}) do
    VersionStore.snapshot(filename)
    versions = VersionStore.list_versions(filename)
    checked_id = VersionStore.get_checked_version(filename)

    case {checked_id, versions} do
      {nil, [latest, previous | _]} ->
        VersionStore.diff(filename, previous.id, latest.id)

      {cid, [latest | _]} when cid == latest.id and length(versions) >= 2 ->
        [_, previous | _] = versions
        VersionStore.diff(filename, previous.id, latest.id)

      {cid, [latest | _] = vers} when length(vers) >= 2 ->
        if Enum.any?(vers, &(&1.id == cid)) do
          VersionStore.diff(filename, cid, latest.id)
        else
          [_, previous | _] = vers
          VersionStore.diff(filename, previous.id, latest.id)
        end

      _ ->
        nil
    end
  end

  defp compute_activity_diff(%{category: cat, project: project, rel_path: rel_path})
       when cat in [:project_memory, :project_config] do
    full_path = Path.join([ClaudePlans.projects_dir(), project, rel_path])

    case File.read(full_path) do
      {:ok, content} -> RenderCache.render(content)
      {:error, _} -> nil
    end
  end

  defp compute_activity_diff(_event), do: nil

  defp navigate_to_plan_diff(socket, filename) do
    path = Path.join(ClaudePlans.plans_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        VersionStore.snapshot(filename)
        versions = VersionStore.list_versions(filename)
        checked_id = VersionStore.get_checked_version(filename)

        {view_mode, diff_html, diff_a, diff_b} =
          resolve_plan_diff_state(filename, checked_id, versions)

        VersionStore.mark_checked(filename)

        {:noreply,
         socket
         |> assign(
           active_tab: :plans,
           selected: filename,
           html: RenderCache.render(content),
           content_highlight: nil,
           versions: versions,
           view_mode: view_mode,
           diff_html: diff_html,
           diff_version_a: diff_a,
           diff_version_b: diff_b,
           show_versions: false,
           annotations: [],
           annotation_counter: 0,
           inspector_mode: false,
           show_annotation_panel: false,
           editing_annotation: nil,
           has_file_annotations: has_file_annotations?(content),
           unchecked_plan_files: VersionStore.unchecked_files()
         )
         |> push_patch(
           to: build_url_params(socket, %{tab: :plans, plan: filename, view: view_mode})
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp resolve_plan_diff_state(_filename, nil, _versions), do: {:rendered, nil, nil, nil}

  defp resolve_plan_diff_state(_filename, cid, [latest | _]) when cid == latest.id,
    do: {:rendered, nil, nil, nil}

  defp resolve_plan_diff_state(filename, cid, [latest | _] = vers) when length(vers) >= 2 do
    {diff_from, diff_to} = pick_diff_versions(cid, latest, vers)
    html = VersionStore.diff(filename, diff_from, diff_to)
    {:diff, html, diff_from, diff_to}
  end

  defp resolve_plan_diff_state(_filename, _checked_id, _versions), do: {:rendered, nil, nil, nil}

  defp pick_diff_versions(cid, latest, vers) do
    if Enum.any?(vers, &(&1.id == cid)) do
      {cid, latest.id}
    else
      [^latest, previous | _] = vers
      {previous.id, latest.id}
    end
  end

  @annotation_separator "\n---\n<!-- Annotations by developer -->\n"

  defp inject_annotations(content, annotations) do
    clean = strip_annotations(content)

    lines =
      Enum.map(annotations, fn ann ->
        direction = String.trim(ann.direction)

        if direction == "" do
          "<!-- #{ann.id} (#{ann.block_path}) -->"
        else
          "<!-- #{ann.id} (#{ann.block_path}): #{direction} -->"
        end
      end)

    clean <> @annotation_separator <> Enum.join(lines, "\n") <> "\n"
  end

  defp strip_annotations(content) do
    case String.split(content, "\n---\n<!-- Annotations by developer -->\n", parts: 2) do
      [clean, _rest] -> String.trim_trailing(clean)
      [_content] -> String.trim_trailing(content)
    end
  end

  defp has_file_annotations?(content) do
    String.contains?(content, "<!-- Annotations by developer -->")
  end

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

  defp dismiss_topmost_layer(
         %{assigns: %{active_tab: :activity, selected_activity_index: idx}} = socket
       )
       when not is_nil(idx) do
    assign(socket, selected_activity_index: nil, activity_diff_html: nil)
  end

  defp dismiss_topmost_layer(%{assigns: %{inspector_mode: true}} = socket),
    do: assign(socket, inspector_mode: false)

  defp dismiss_topmost_layer(%{assigns: %{show_annotation_panel: true}} = socket),
    do: assign(socket, show_annotation_panel: false)

  defp dismiss_topmost_layer(%{assigns: %{view_mode: :diff}} = socket),
    do: assign(socket, view_mode: :rendered)

  defp dismiss_topmost_layer(%{assigns: %{show_versions: true}} = socket),
    do: assign(socket, show_versions: false)

  defp dismiss_topmost_layer(%{assigns: %{show_help: true}} = socket),
    do: assign(socket, show_help: false)

  defp dismiss_topmost_layer(%{assigns: %{content_highlight: h}} = socket) when not is_nil(h),
    do: assign(socket, content_highlight: nil)

  defp dismiss_topmost_layer(%{assigns: %{search_query: q}} = socket) when q != "",
    do: assign(socket, search_query: "", search_results: [], content_highlight: nil)

  defp dismiss_topmost_layer(socket), do: socket

  defp kb_current_index(socket) do
    if socket.assigns.search_query != "" do
      current_search_result_index(socket)
    else
      current_selection_index(socket)
    end
  end

  defp kb_resolve_index(_dir, _current, _max_idx, []), do: nil
  defp kb_resolve_index("top", _current, _max_idx, _list), do: 0
  defp kb_resolve_index("bottom", _current, max_idx, _list), do: max_idx
  defp kb_resolve_index("down", nil, _max_idx, _list), do: 0
  defp kb_resolve_index("down", i, max_idx, _list) when i >= max_idx, do: max_idx
  defp kb_resolve_index("down", i, _max_idx, _list), do: i + 1
  defp kb_resolve_index("up", nil, max_idx, _list), do: max_idx
  defp kb_resolve_index("up", 0, _max_idx, _list), do: 0
  defp kb_resolve_index("up", i, _max_idx, _list), do: i - 1

  defp kb_apply_navigation(socket, _list, nil), do: {:noreply, socket}

  defp kb_apply_navigation(socket, list, new_idx) do
    case Enum.at(list, new_idx) do
      nil -> {:noreply, socket}
      item -> kb_select_item(socket, item)
    end
  end

  defp kb_select_from_list(socket) do
    list = visible_list(socket)
    idx = kb_current_index(socket)

    case Enum.at(list, idx || -1) do
      nil -> {:noreply, socket}
      item -> kb_select_item(socket, item)
    end
  end

  defp kb_select_item(socket, item) do
    if socket.assigns.search_query != "" do
      select_search_result(socket, item)
    else
      select_visible_item(socket, item)
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

      :activity ->
        socket.assigns.selected_activity_index

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
        diff_html = compute_activity_diff(item)

        {:noreply,
         assign(socket,
           selected_activity_index: idx,
           activity_diff_html: diff_html
         )}

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
         socket
         |> assign(
           active_tab: :plans,
           selected: result.filename,
           html: RenderCache.render(content),
           content_highlight: highlight,
           view_mode: :rendered
         )
         |> push_patch(
           to: build_url_params(socket, %{tab: :plans, plan: result.filename}),
           replace: true
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
         socket
         |> assign(
           active_tab: :projects,
           selected_file: rel,
           file_html: RenderCache.render(content),
           content_highlight: highlight
         )
         |> push_patch(
           to: build_url_params(socket, %{tab: :projects, project: proj, file: rel}),
           replace: true
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
    projects_dir
    |> File.ls()
    |> case do
      {:ok, dirs} -> dirs
      {:error, _} -> []
    end
    |> Enum.filter(&File.dir?(Path.join(projects_dir, &1)))
    |> Enum.map(&build_project_entry(projects_dir, &1))
    |> Enum.filter(& &1.has_memory?)
    |> Enum.sort_by(& &1.display_name)
  end

  defp build_project_entry(projects_dir, dir_name) do
    display = project_display_name(dir_name)
    has_memory? = File.dir?(Path.join([projects_dir, dir_name, "memory"]))
    %{dir_name: dir_name, display_name: display, has_memory?: has_memory?}
  end

  defp project_display_name(dir_name) do
    candidate = "/" <> (dir_name |> String.trim_leading("-") |> String.replace("-", "/"))

    if File.dir?(candidate) do
      Path.relative_to(candidate, System.user_home!()) |> then(&"~/#{&1}")
    else
      dir_name |> String.trim_leading("-Users-#{System.get_env("USER", "user")}-")
    end
  end

  defp list_project_files(projects_dir, dir_name) do
    project_path = Path.join(projects_dir, dir_name)
    root_files = list_md_files(project_path, nil)
    memory_files = list_md_files(Path.join(project_path, "memory"), "memory")
    (root_files ++ memory_files) |> Enum.sort_by(fn f -> {f.dir || "", f.name} end)
  end

  defp list_md_files(dir, subdir) do
    dir
    |> File.ls()
    |> case do
      {:ok, files} -> files
      {:error, _} -> []
    end
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(&md_file_entry(&1, subdir))
  end

  defp md_file_entry(name, nil), do: %{name: name, dir: nil, rel_path: name}

  defp md_file_entry(name, subdir),
    do: %{name: name, dir: subdir, rel_path: Path.join(subdir, name)}

  defp resolve_selected_plan(plans, current_selected) do
    found = if current_selected, do: Enum.find(plans, &(&1.filename == current_selected))

    case found do
      nil -> select_first_plan(plans)
      plan -> {plan.filename, RenderCache.render(File.read!(plan.path))}
    end
  end

  defp select_first_plan([first | _]),
    do: {first.filename, RenderCache.render(File.read!(first.path))}

  defp select_first_plan([]), do: {nil, nil}

  defp check_annotations(nil), do: false

  defp check_annotations(selected) do
    path = Path.join(ClaudePlans.plans_dir(), selected)

    case File.read(path) do
      {:ok, content} -> has_file_annotations?(content)
      _ -> false
    end
  end

  defp refresh_versions(socket, nil) do
    assign(socket, versions: [], view_mode: :rendered, diff_html: nil)
  end

  defp refresh_versions(socket, selected) do
    versions = VersionStore.list_versions(selected)
    socket = assign(socket, versions: versions)

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
  end

  defp format_time(posix_time) when is_integer(posix_time) do
    now = System.os_time(:second)
    diff = now - posix_time

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 86_400 * 30 -> "#{div(diff, 86_400)}d ago"
      true -> posix_time |> DateTime.from_unix!() |> Calendar.strftime("%b %d, %Y")
    end
  end

  defp format_version_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    if bytes >= 1024 do
      "#{Float.round(bytes / 1024, 1)} KB"
    else
      "#{bytes} B"
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

  # --- URL param helpers ---

  defp parse_tab("projects"), do: :projects
  defp parse_tab("activity"), do: :activity
  defp parse_tab(_), do: :plans

  defp resolve_plan(nil, socket) do
    case socket.assigns.plans do
      [first | _] -> first.filename
      [] -> nil
    end
  end

  defp resolve_plan(filename, socket) do
    if Enum.any?(socket.assigns.plans, &(&1.filename == filename)) do
      filename
    else
      resolve_plan(nil, socket)
    end
  end

  defp load_plan_state(socket, filename) do
    path = Path.join(ClaudePlans.plans_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        VersionStore.snapshot(filename)
        VersionStore.mark_checked(filename)
        versions = VersionStore.list_versions(filename)

        plans = socket.assigns.plans
        idx = Enum.find_index(plans, &(&1.filename == filename)) || 0
        nearby_paths = Enum.map(plans, & &1.path)
        RenderCache.prerender_nearby(nearby_paths, idx)

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
          editing_annotation: nil,
          has_file_annotations: has_file_annotations?(content),
          unchecked_plan_files: VersionStore.unchecked_files()
        )

      {:error, _} ->
        socket
    end
  end

  defp load_file_state(socket, rel_path) do
    full_path =
      Path.join([socket.assigns.projects_dir, socket.assigns.selected_project, rel_path])

    case File.read(full_path) do
      {:ok, content} ->
        project_files = socket.assigns.project_files
        idx = Enum.find_index(project_files, &(&1.rel_path == rel_path)) || 0
        base = Path.join(socket.assigns.projects_dir, socket.assigns.selected_project)
        nearby_paths = Enum.map(project_files, &Path.join(base, &1.rel_path))
        RenderCache.prerender_nearby(nearby_paths, idx)

        assign(socket,
          selected_file: rel_path,
          file_html: RenderCache.render(content),
          content_highlight: nil
        )

      {:error, _} ->
        socket
    end
  end

  defp build_url_params(socket, overrides) do
    tab = Map.get(overrides, :tab, socket.assigns.active_tab)
    plan = Map.get(overrides, :plan, socket.assigns.selected)
    project = Map.get(overrides, :project, socket.assigns.selected_project)
    file = Map.get(overrides, :file, socket.assigns.selected_file)
    query = Map.get(overrides, :q, socket.assigns.search_query)
    view = Map.get(overrides, :view, socket.assigns.view_mode)

    params =
      [
        url_param("tab", tab != :plans, fn -> Atom.to_string(tab) end),
        url_param("plan", not is_nil(plan), fn -> plan end),
        url_param("project", tab == :projects and not is_nil(project), fn -> project end),
        url_param("file", tab == :projects and not is_nil(file), fn -> file end),
        url_param("q", query != "", fn -> query end),
        url_param("view", view != :rendered, fn -> Atom.to_string(view) end)
      ]
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    if params == %{}, do: "/", else: "/?" <> URI.encode_query(params)
  end

  defp url_param(key, true, value_fn), do: {key, value_fn.()}
  defp url_param(_key, _false, _value_fn), do: nil
end
