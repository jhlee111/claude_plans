defmodule ClaudePlans.Web.BrowserLive do
  use Phoenix.LiveView

  import ClaudePlans.Web.Icons
  import ClaudePlans.Web.Components.Helpers, only: [editor_url: 1]
  import ClaudePlans.Web.UrlParams, only: [parse_tab: 1]

  alias ClaudePlans.Web.UrlParams

  alias ClaudePlans.ActivityFeed
  alias ClaudePlans.Annotations
  alias ClaudePlans.KeyboardNav
  alias ClaudePlans.Projects
  alias ClaudePlans.RenderCache
  alias ClaudePlans.SearchIndex
  alias ClaudePlans.VersionStore
  alias ClaudePlans.Watcher
  alias ClaudePlans.Web.Components.{AnnotationComponents, ContentComponents, SidebarComponents}

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
    projects = Projects.list(projects_dir)

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
  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ~w(plans projects activity) do
    {:noreply,
     push_patch(socket, to: UrlParams.build(socket.assigns, %{tab: String.to_existing_atom(tab)}))}
  end

  def handle_event("select_plan", %{"filename" => filename}, socket) do
    {:noreply,
     push_patch(socket, to: UrlParams.build(socket.assigns, %{plan: filename, view: :rendered}))}
  end

  def handle_event("select_project", %{"project" => ""}, socket), do: {:noreply, socket}

  def handle_event("select_project", %{"project" => dir_name}, socket) do
    {:noreply,
     push_patch(socket,
       to: UrlParams.build(socket.assigns, %{tab: :projects, project: dir_name, file: nil})
     )}
  end

  def handle_event("select_file", %{"path" => rel_path}, socket) do
    {:noreply, push_patch(socket, to: UrlParams.build(socket.assigns, %{file: rel_path}))}
  end

  # --- Search ---

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to: UrlParams.build(socket.assigns, %{q: String.trim(query)}),
       replace: true
     )}
  end

  def handle_event("confirm_search", _params, socket) do
    query = socket.assigns.search_query
    highlight = if query != "", do: query, else: nil
    {:noreply, assign(socket, content_highlight: highlight)}
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply, push_patch(socket, to: UrlParams.build(socket.assigns, %{q: ""}))}
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
         |> push_patch(to: UrlParams.build(socket.assigns, %{view: :diff}), replace: true)}

      :diff ->
        {:noreply,
         socket
         |> assign(view_mode: :rendered)
         |> push_patch(to: UrlParams.build(socket.assigns, %{view: :rendered}), replace: true)}

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
    new_idx = KeyboardNav.resolve_index(dir, current, max_idx, list)

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
           to:
             UrlParams.build(socket.assigns, %{tab: :projects, project: project, file: rel_path})
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
    {:noreply, after_delete(socket.assigns.active_tab, socket)}
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
        updated = Annotations.inject(content, annotations)
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
        cleaned = Annotations.strip(content)
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
            <SidebarComponents.search_results {assigns} />
          <% else %>
            <%= case @active_tab do %>
              <% :plans -> %><SidebarComponents.plans_sidebar {assigns} />
              <% :projects -> %><SidebarComponents.projects_sidebar {assigns} />
              <% :activity -> %><SidebarComponents.activity_sidebar {assigns} />
            <% end %>
          <% end %>
        </div>
      </div>
      <div class="cb-main">
        <%= case @active_tab do %>
          <% :plans -> %><ContentComponents.plans_content {assigns} />
          <% :projects -> %><ContentComponents.projects_content {assigns} />
          <% :activity -> %><ContentComponents.activity_content {assigns} />
        <% end %>
      </div>
      <AnnotationComponents.annotation_panel {assigns} />
      <AnnotationComponents.help_modal {assigns} />
    </div>
    """
  end

  # --- Helpers ---

  defp compute_activity_diff(%{category: :plan, filename: filename}) do
    {diff_html, _versions, _checked_id} = VersionStore.diff_since_checked(filename)
    diff_html
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
          VersionStore.resolve_diff_state(filename, checked_id, versions)

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
           unchecked_plan_files: VersionStore.unchecked_files()
         )
         |> reset_annotation_assigns(content)
         |> push_patch(
           to: UrlParams.build(socket.assigns, %{tab: :plans, plan: filename, view: view_mode})
         )}

      {:error, _} ->
        {:noreply, socket}
    end
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
        {:noreply,
         push_patch(socket,
           to: UrlParams.build(socket.assigns, %{plan: item.filename, view: :rendered})
         )}

      :projects ->
        {:noreply,
         push_patch(socket, to: UrlParams.build(socket.assigns, %{file: item.rel_path}))}

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
           to: UrlParams.build(socket.assigns, %{tab: :plans, plan: result.filename}),
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
           to: UrlParams.build(socket.assigns, %{tab: :projects, project: proj, file: rel}),
           replace: true
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

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
    files = Projects.list_files(projects_dir, dir_name)
    {selected_file, file_html} = load_first_file(projects_dir, dir_name, files)

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

  defp resolve_selected_plan(plans, current_selected) do
    found = if current_selected, do: Enum.find(plans, &(&1.filename == current_selected))

    case found do
      nil -> select_first_plan(plans)
      plan -> render_plan_entry(plan)
    end
  end

  defp select_first_plan([first | _]), do: render_plan_entry(first)
  defp select_first_plan([]), do: {nil, nil}

  defp render_plan_entry(plan) do
    case File.read(plan.path) do
      {:ok, content} -> {plan.filename, RenderCache.render(content)}
      {:error, _} -> {plan.filename, nil}
    end
  end

  defp after_delete(:plans, socket) do
    plans = Watcher.list_plans()
    {selected, html} = resolve_selected_plan(plans, nil)
    assign(socket, plans: plans, selected: selected, html: html)
  end

  defp after_delete(:projects, socket) do
    %{projects_dir: dir, selected_project: project} = socket.assigns
    files = Projects.list_files(dir, project)
    {selected_file, file_html} = load_first_file(dir, project, files)
    assign(socket, project_files: files, selected_file: selected_file, file_html: file_html)
  end

  defp after_delete(_tab, socket), do: socket

  defp load_first_file(_projects_dir, _project, []), do: {nil, nil}

  defp load_first_file(projects_dir, project, [first | _]) do
    full = Path.join([projects_dir, project, first.rel_path])

    case File.read(full) do
      {:ok, content} -> {first.rel_path, RenderCache.render(content)}
      {:error, _} -> {first.rel_path, nil}
    end
  end

  defp reset_annotation_assigns(socket, content) do
    assign(socket,
      annotations: [],
      annotation_counter: 0,
      inspector_mode: false,
      show_annotation_panel: false,
      editing_annotation: nil,
      has_file_annotations: Annotations.present?(content)
    )
  end

  defp check_annotations(nil), do: false

  defp check_annotations(selected) do
    path = Path.join(ClaudePlans.plans_dir(), selected)

    case File.read(path) do
      {:ok, content} -> Annotations.present?(content)
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

  # --- URL param helpers ---

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

        socket
        |> assign(
          selected: filename,
          html: RenderCache.render(content),
          content_highlight: nil,
          versions: versions,
          view_mode: :rendered,
          diff_html: nil,
          diff_version_a: nil,
          diff_version_b: nil,
          show_versions: false,
          unchecked_plan_files: VersionStore.unchecked_files()
        )
        |> reset_annotation_assigns(content)

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
end
