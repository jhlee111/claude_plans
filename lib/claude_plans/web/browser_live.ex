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
  alias ClaudePlans.Folders
  alias ClaudePlans.FolderWatcherSupervisor
  alias ClaudePlans.Web.Components.{AnnotationComponents, ContentComponents, SidebarComponents}
  alias ClaudePlans.Web.FoldersViewerComponent
  alias ClaudePlans.Web.ProjectsViewerComponent

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Watcher.subscribe()
      ActivityFeed.subscribe()
      {:ok, _} = Registry.register(ClaudePlans.Registry, :folder_updates, [])
    end

    {font_size, content_width} =
      if connected?(socket) do
        params = get_connect_params(socket)

        fs =
          case params do
            %{"font_size" => size} when is_integer(size) and size >= 10 and size <= 28 -> size
            _ -> 16
          end

        cw =
          case params do
            %{"content_width" => w} when w in ["narrow", "wide"] -> w
            _ -> "wide"
          end

        {fs, cw}
      else
        {16, "wide"}
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
       url_project_file: nil,
       projects_dir: projects_dir,
       project_annotation_state: nil,
       search_query: "",
       search_results: [],
       search_flat_matches: [],
       search_match_cursor: -1,
       content_highlight: nil,
       content_highlight_line: nil,
       show_help: false,
       view_mode: :rendered,
       diff_html: nil,
       versions: [],
       diff_version_a: nil,
       diff_version_b: nil,
       show_versions: false,
       font_size: font_size,
       content_width: content_width,
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
       activity_diff_html: nil,
       custom_folders: Folders.list(),
       selected_custom_folder: nil,
       folder_files: [],
       folder_nav_selected: nil,
       folder_current_path: nil,
       adding_folder: false,
       new_folder_path: "",
       folder_path_error: nil,
       browse_path: System.user_home!(),
       browse_dirs: list_subdirs(System.user_home!()),
       browse_filter: "",
       url_folder_file: nil,
       folder_annotation_state: nil,
       sort_mode: :modified_desc
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
      |> apply_folder_params(tab, params)
      |> apply_search(query)
      |> apply_view_mode(tab, params["view"])

    {:noreply, socket}
  end

  defp apply_tab_switch(socket, tab) when tab == socket.assigns.active_tab, do: socket

  defp apply_tab_switch(socket, :projects) do
    socket =
      assign(socket, active_tab: :projects, content_highlight: nil, content_highlight_line: nil)

    if is_nil(socket.assigns.selected_project) and socket.assigns.projects != [] do
      [first | _] = socket.assigns.projects
      load_project(socket, first.dir_name)
    else
      socket
    end
  end

  defp apply_tab_switch(socket, :folders) do
    assign(socket, active_tab: :folders, content_highlight: nil, content_highlight_line: nil)
  end

  defp apply_tab_switch(socket, :activity) do
    assign(socket,
      active_tab: :activity,
      content_highlight: nil,
      content_highlight_line: nil,
      unseen_activity_count: 0,
      selected_activity_index: nil,
      activity_diff_html: nil
    )
  end

  defp apply_tab_switch(socket, tab) do
    assign(socket, active_tab: tab, content_highlight: nil, content_highlight_line: nil)
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
      assign(socket, selected_file: file, url_project_file: file)
    else
      socket
    end
  end

  defp apply_file_change(socket, _file), do: socket

  defp apply_folder_params(socket, :folders, params) do
    socket = maybe_select_custom_folder(socket, params["folder"])
    assign(socket, url_folder_file: params["folder_file"])
  end

  defp apply_folder_params(socket, _tab, _params), do: socket

  defp maybe_select_custom_folder(socket, nil), do: socket
  defp maybe_select_custom_folder(socket, ""), do: socket

  defp maybe_select_custom_folder(socket, folder_id) do
    if folder_id != socket.assigns.selected_custom_folder and
         Enum.any?(socket.assigns.custom_folders, &(&1.id == folder_id)) do
      load_custom_folder(socket, folder_id)
    else
      socket
    end
  end

  defp apply_search(socket, query) when query == socket.assigns.search_query, do: socket

  defp apply_search(socket, ""),
    do:
      assign(socket,
        search_query: "",
        search_results: [],
        search_flat_matches: [],
        search_match_cursor: -1,
        content_highlight: nil,
        content_highlight_line: nil
      )

  defp apply_search(socket, query) do
    results = SearchIndex.search(query)
    sorted = sort_search_results_by_mode(results, socket.assigns.sort_mode)
    prerender_search_results(sorted, socket.assigns.projects_dir)
    flat_matches = build_flat_matches(sorted)

    assign(socket,
      search_query: query,
      search_results: sorted,
      search_flat_matches: flat_matches,
      search_match_cursor: -1,
      content_highlight: nil,
      content_highlight_line: nil
    )
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
      when tab in ~w(plans projects folders activity) do
    {:noreply,
     push_patch(socket, to: UrlParams.build(socket.assigns, %{tab: String.to_existing_atom(tab)}))}
  end

  def handle_event("cycle_sort", %{"field" => field}, socket) do
    current = socket.assigns.sort_mode
    new_mode = next_sort_mode(field, current)

    socket =
      socket
      |> assign(sort_mode: new_mode)
      |> apply_sort()

    {:noreply, socket}
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
      nil ->
        {:noreply, socket}

      result ->
        socket = sync_flat_cursor_to_result(socket, result)
        select_search_result(socket, result)
    end
  end

  # --- Diff / Version History ---

  # Forward toggle events to the active component when not on Plans tab
  def handle_event(event, _params, socket)
      when event in ["toggle_diff", "toggle_versions", "toggle_inspector"] and
             socket.assigns.active_tab in [:projects, :folders] do
    component =
      case socket.assigns.active_tab do
        :projects -> {ClaudePlans.Web.ProjectsViewerComponent, "projects-viewer"}
        :folders -> {ClaudePlans.Web.FoldersViewerComponent, "folders-viewer"}
      end

    {module, id} = component
    send_update(module, id: id, keyboard_event: {event, %{}})
    {:noreply, socket}
  end

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

  def handle_event("kb_next_match", _params, socket) do
    navigate_flat_match(socket, :next)
  end

  def handle_event("kb_prev_match", _params, socket) do
    navigate_flat_match(socket, :prev)
  end

  def handle_event("kb_escape", _params, socket) do
    {:noreply, dismiss_topmost_layer(socket)}
  end

  def handle_event("kb_tab", %{"tab" => tab}, socket) do
    socket =
      assign(socket,
        search_query: "",
        search_results: [],
        search_flat_matches: [],
        search_match_cursor: -1,
        content_highlight: nil,
        content_highlight_line: nil,
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

  def handle_event("toggle_width", _params, socket) do
    new_width = if socket.assigns.content_width == "wide", do: "narrow", else: "wide"

    {:noreply,
     socket
     |> assign(content_width: new_width)
     |> push_event("save_preferences", %{content_width: new_width})}
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
        socket = assign(socket, content_highlight: nil, content_highlight_line: nil)
        navigate_to_plan_diff(socket, filename)

      %{category: cat, project: project, rel_path: rel_path}
      when cat in [:project_memory, :project_config] ->
        {:noreply,
         push_patch(socket,
           to:
             UrlParams.build(socket.assigns, %{tab: :projects, project: project, file: rel_path})
         )}

      %{category: :folder, path: file_path} ->
        case find_folder_for_path(socket.assigns.custom_folders, file_path) do
          {folder, rel} ->
            {:noreply,
             push_patch(socket,
               to:
                 UrlParams.build(socket.assigns, %{
                   tab: :folders,
                   folder: folder.id,
                   folder_file: rel
                 })
             )}

          nil ->
            {:noreply, socket}
        end

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

  # --- Custom Folders ---

  def handle_event("select_custom_folder", %{"folder" => ""}, socket), do: {:noreply, socket}

  def handle_event("select_custom_folder", %{"folder" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to: UrlParams.build(socket.assigns, %{tab: :folders, folder: id, folder_file: nil})
     )}
  end

  def handle_event("show_add_folder", _params, socket) do
    {:noreply, assign(socket, adding_folder: true, new_folder_path: "", folder_path_error: nil)}
  end

  def handle_event("validate_folder_path", %{"path" => path}, socket) do
    error =
      case Folders.validate_path(path) do
        :ok -> nil
        {:error, msg} -> msg
      end

    {:noreply, assign(socket, new_folder_path: path, folder_path_error: error)}
  end

  def handle_event("add_folder", %{"path" => path}, socket) do
    case Folders.add(path) do
      {:ok, folder} ->
        ClaudePlans.FolderWatcherSupervisor.add_folder(folder.path)

        socket =
          socket
          |> assign(
            custom_folders: Folders.list(),
            adding_folder: false,
            new_folder_path: "",
            folder_path_error: nil
          )
          |> load_custom_folder(folder.id)

        {:noreply,
         push_patch(socket,
           to: UrlParams.build(socket.assigns, %{tab: :folders, folder: folder.id})
         )}

      {:error, _reason} ->
        {:noreply, assign(socket, folder_path_error: "Failed to add folder")}
    end
  end

  def handle_event("remove_folder", _params, socket) do
    case socket.assigns.selected_custom_folder do
      nil ->
        {:noreply, socket}

      id ->
        folder = Enum.find(socket.assigns.custom_folders, &(&1.id == id))
        Folders.remove(id)
        if folder, do: ClaudePlans.FolderWatcherSupervisor.remove_folder(folder.path)

        folders = Folders.list()

        socket =
          assign(socket,
            custom_folders: folders,
            selected_custom_folder: nil,
            folder_files: [],
            folder_nav_selected: nil
          )

        {:noreply,
         push_patch(socket,
           to: UrlParams.build(socket.assigns, %{tab: :folders, folder: nil, folder_file: nil})
         )}
    end
  end

  def handle_event("cancel_add_folder", _params, socket) do
    {:noreply, assign(socket, adding_folder: false, new_folder_path: "", folder_path_error: nil)}
  end

  def handle_event("navigate_subfolder", %{"path" => path}, socket) do
    if File.dir?(path) do
      files = Folders.sort_files(Folders.list_files(path), socket.assigns.sort_mode)

      {:noreply,
       assign(socket,
         folder_files: files,
         folder_current_path: path,
         folder_nav_selected: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("navigate_folder_up", _params, socket) do
    current = socket.assigns.folder_current_path
    original = folder_original_path(socket.assigns)

    if current && current != original do
      parent = Path.dirname(current)
      # Don't go above the original folder path
      target = if String.starts_with?(parent, original), do: parent, else: original
      files = Folders.sort_files(Folders.list_files(target), socket.assigns.sort_mode)

      {:noreply,
       assign(socket,
         folder_files: files,
         folder_current_path: if(target == original, do: nil, else: target),
         folder_nav_selected: nil
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("refresh_dir_index", _params, socket) do
    ClaudePlans.DirIndex.reindex()
    {:noreply, socket}
  end

  def handle_event("browse_into", %{"path" => path}, socket) do
    # path may be absolute, or relative to browse_path (direct browse)
    # or relative to home (from DirIndex search)
    full =
      cond do
        Path.type(path) == :absolute ->
          path

        File.dir?(Path.join(socket.assigns.browse_path, path)) ->
          Path.join(socket.assigns.browse_path, path)

        true ->
          # Relative to home (from DirIndex)
          Path.join(System.user_home!(), path)
      end
      |> Path.expand()

    if File.dir?(full) do
      {:noreply,
       assign(socket,
         browse_path: full,
         browse_dirs: list_subdirs(full),
         new_folder_path: full,
         folder_path_error: nil,
         browse_filter: ""
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("browse_up", _params, socket) do
    parent = Path.dirname(socket.assigns.browse_path)

    {:noreply,
     assign(socket,
       browse_path: parent,
       browse_dirs: list_subdirs(parent),
       new_folder_path: parent,
       folder_path_error: nil,
       browse_filter: ""
     )}
  end

  def handle_event("browse_filter", %{"filter" => query}, socket) do
    if query == "" do
      base = socket.assigns.browse_path
      {:noreply, assign(socket, browse_dirs: list_subdirs(base), browse_filter: "")}
    else
      # Instant search from pre-built index — returns [{path, match_indices}]
      results = ClaudePlans.DirIndex.search(query, 30)
      {:noreply, assign(socket, browse_dirs: results, browse_filter: query)}
    end
  end

  def handle_event("browse_select", _params, socket) do
    path = socket.assigns.browse_path

    case Folders.add(path) do
      {:ok, folder} ->
        ClaudePlans.FolderWatcherSupervisor.add_folder(folder.path)

        socket =
          socket
          |> assign(
            custom_folders: Folders.list(),
            adding_folder: false,
            new_folder_path: "",
            folder_path_error: nil
          )
          |> load_custom_folder(folder.id)

        {:noreply,
         push_patch(socket,
           to: UrlParams.build(socket.assigns, %{tab: :folders, folder: folder.id})
         )}

      {:error, :already_added} ->
        {:noreply, assign(socket, folder_path_error: "Already added")}

      {:error, _} ->
        {:noreply, assign(socket, folder_path_error: "Cannot add this folder")}
    end
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
      |> sort_plans(socket.assigns.sort_mode)
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

  # --- Folders bridge ---

  def handle_info({:folders_nav_state, selected}, socket) do
    {:noreply, assign(socket, folder_nav_selected: selected)}
  end

  def handle_info({:folders_annotation_state, state}, socket) do
    {:noreply, assign(socket, folder_annotation_state: state)}
  end

  def handle_info({:projects_nav_state, selected}, socket) do
    {:noreply, assign(socket, selected_file: selected, url_project_file: selected)}
  end

  def handle_info({:projects_annotation_state, state}, socket) do
    {:noreply, assign(socket, project_annotation_state: state)}
  end

  def handle_info({:folder_file_updated, watched_path, full_file_path}, socket) do
    rel = Path.relative_to(full_file_path, watched_path)

    # Forward to Folders tab component
    send_update(FoldersViewerComponent,
      id: "folders-viewer",
      file_updated: {watched_path, rel}
    )

    # Forward to Projects tab component and refresh project file list if the watched path matches
    project_path = current_project_path(socket.assigns)

    socket =
      if project_path && watched_path == project_path do
        send_update(ProjectsViewerComponent,
          id: "projects-viewer",
          file_updated: {watched_path, rel}
        )

        files = Projects.list_files(socket.assigns.projects_dir, socket.assigns.selected_project)
        assign(socket, project_files: Projects.sort_files(files, socket.assigns.sort_mode))
      else
        socket
      end

    # Refresh sidebar file list if the change is within the currently visible folder
    socket =
      case {folder_original_path(socket.assigns), current_folder_path(socket.assigns)} do
        {^watched_path, visible_path} when is_binary(visible_path) ->
          file_dir = Path.dirname(full_file_path)

          if file_dir == visible_path do
            assign(socket,
              folder_files:
                Folders.sort_files(Folders.list_files(visible_path), socket.assigns.sort_mode)
            )
          else
            socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div id="kb-nav" class="cb-layout" phx-hook="KeyboardNav">
      <div class="cb-sidebar">
        <div class="cb-tabs">
          <button
            :for={{id, label} <- [{:plans, "Plans"}, {:projects, "Projects"}, {:folders, "Folders"}, {:activity, "Activity"}]}
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
              <% :folders -> %><SidebarComponents.folders_sidebar {assigns} />
              <% :activity -> %><SidebarComponents.activity_sidebar {assigns} />
            <% end %>
          <% end %>
        </div>
      </div>
      <div class="cb-main">
        <%= case @active_tab do %>
          <% :plans -> %><ContentComponents.plans_content {assigns} />
          <% :projects -> %>
            <.live_component
              module={ProjectsViewerComponent}
              id="projects-viewer"
              font_size={@font_size}
              content_width={@content_width}
              content_highlight={@content_highlight}
              content_highlight_line={@content_highlight_line}
              project_path={current_project_path(assigns)}
              initial_file={@url_project_file}
            />
          <% :folders -> %>
            <.live_component
              module={FoldersViewerComponent}
              id="folders-viewer"
              font_size={@font_size}
              content_width={@content_width}
              content_highlight={@content_highlight}
              content_highlight_line={@content_highlight_line}
              folder_path={current_folder_path(assigns)}
              initial_file={@url_folder_file}
            />
          <% :activity -> %><ContentComponents.activity_content {assigns} />
        <% end %>
      </div>
      <AnnotationComponents.annotation_panel :if={@active_tab == :plans} {assigns} />
      <%= if @active_tab == :folders && @folder_annotation_state && @folder_annotation_state.show_annotation_panel do %>
        <.component_annotation_panel state={@folder_annotation_state} target="#folders-viewer" prefix="folder" />
      <% end %>
      <%= if @active_tab == :projects && @project_annotation_state && @project_annotation_state.show_annotation_panel do %>
        <.component_annotation_panel state={@project_annotation_state} target="#projects-viewer" prefix="project" />
      <% end %>
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
           content_highlight_line: nil,
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

  defp navigate_flat_match(socket, direction) do
    flat = socket.assigns.search_flat_matches

    if flat == [] do
      {:noreply, socket}
    else
      cursor = socket.assigns.search_match_cursor
      max_cursor = length(flat) - 1

      new_cursor =
        case direction do
          :next -> min(cursor + 1, max_cursor)
          :prev -> max(cursor - 1, 0)
        end

      {result_idx, _line_number} = Enum.at(flat, new_cursor)
      result = Enum.at(socket.assigns.search_results, result_idx)

      # Count how many matches for the same result come before this cursor position
      match_idx_in_doc =
        flat
        |> Enum.take(new_cursor)
        |> Enum.count(fn {ridx, _} -> ridx == result_idx end)

      socket =
        assign(socket,
          search_match_cursor: new_cursor,
          content_highlight_line: match_idx_in_doc
        )

      select_search_result(socket, result)
    end
  end

  defp sync_flat_cursor_to_result(socket, result) do
    result_idx = Enum.find_index(socket.assigns.search_results, &(&1.path == result.path))

    cursor =
      Enum.find_index(socket.assigns.search_flat_matches, fn {ridx, _} ->
        ridx == result_idx
      end) || -1

    assign(socket, search_match_cursor: cursor, content_highlight_line: nil)
  end

  defp build_flat_matches(results) do
    results
    |> Enum.with_index()
    |> Enum.flat_map(fn {result, result_idx} ->
      Enum.map(result.matches, fn match ->
        {result_idx, match.line_number}
      end)
    end)
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
    do: assign(socket, content_highlight: nil, content_highlight_line: nil)

  defp dismiss_topmost_layer(%{assigns: %{search_query: q}} = socket) when q != "",
    do:
      assign(socket,
        search_query: "",
        search_results: [],
        search_flat_matches: [],
        search_match_cursor: -1,
        content_highlight: nil,
        content_highlight_line: nil
      )

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
      socket = sync_flat_cursor_to_result(socket, item)
      select_search_result(socket, item)
    else
      select_visible_item(socket, item)
    end
  end

  defp current_search_result_index(socket) do
    tab = socket.assigns.active_tab

    Enum.find_index(socket.assigns.search_results, fn
      %{source: :plan, filename: f} ->
        tab == :plans && socket.assigns.selected == f

      %{source: :project, project: p, rel_path: r} ->
        tab == :projects && socket.assigns.selected_project == p &&
          socket.assigns.selected_file == r

      %{source: :folder, folder_id: fid, rel_path: r} ->
        tab == :folders && socket.assigns.selected_custom_folder == fid &&
          socket.assigns.folder_nav_selected == r
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

      :folders ->
        Enum.find_index(
          socket.assigns.folder_files,
          &(&1.rel_path == socket.assigns.folder_nav_selected)
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
      socket.assigns.active_tab == :folders -> socket.assigns.folder_files
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
        send_update(ProjectsViewerComponent,
          id: "projects-viewer",
          initial_file: item.rel_path
        )

        {:noreply, assign(socket, selected_file: item.rel_path)}

      :folders ->
        # Send file selection to the LiveComponent via send_update
        send_update(FoldersViewerComponent,
          id: "folders-viewer",
          initial_file: item.rel_path
        )

        {:noreply, assign(socket, folder_nav_selected: item.rel_path)}

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

    {:noreply,
     socket
     |> assign(
       active_tab: :projects,
       selected_file: rel,
       url_project_file: rel,
       content_highlight: highlight
     )
     |> push_patch(
       to: UrlParams.build(socket.assigns, %{tab: :projects, project: proj, file: rel}),
       replace: true
     )}
  end

  defp select_search_result(socket, %{source: :folder, folder_id: fid, rel_path: rel, path: path}) do
    highlight = socket.assigns.search_query

    socket =
      if socket.assigns.selected_custom_folder != fid do
        load_custom_folder(socket, fid)
      else
        socket
      end

    # If the file is in a subfolder, navigate to that subfolder
    folder = Enum.find(socket.assigns.custom_folders, &(&1.id == fid))
    file_dir = Path.dirname(path)

    socket =
      if folder && file_dir != folder.path do
        assign(socket,
          folder_files:
            Folders.sort_files(Folders.list_files(file_dir), socket.assigns.sort_mode),
          folder_current_path: file_dir
        )
      else
        socket
      end

    send_update(FoldersViewerComponent,
      id: "folders-viewer",
      initial_file: Path.basename(path)
    )

    {:noreply,
     socket
     |> assign(
       active_tab: :folders,
       folder_nav_selected: rel,
       url_folder_file: Path.basename(path),
       content_highlight: highlight
     )
     |> push_patch(
       to:
         UrlParams.build(socket.assigns, %{
           tab: :folders,
           folder: fid,
           folder_file: Path.basename(path)
         }),
       replace: true
     )}
  end

  defp search_result_paths(results, projects_dir) do
    Enum.map(results, fn
      %{source: :plan, filename: filename} ->
        Path.join(ClaudePlans.plans_dir(), filename)

      %{source: :project, project: proj, rel_path: rel} ->
        Path.join([projects_dir, proj, rel])

      %{source: :folder, path: path} ->
        path
    end)
  end

  defp load_project(socket, dir_name) do
    projects_dir = socket.assigns.projects_dir
    files = Projects.list_files(projects_dir, dir_name)
    sorted_files = Projects.sort_files(files, socket.assigns.sort_mode)
    first_file = if sorted_files != [], do: hd(sorted_files).rel_path
    project_path = Path.join(projects_dir, dir_name)

    # Pre-render all project files in background
    all_paths = Enum.map(files, &Path.join(project_path, &1.rel_path))
    RenderCache.prerender(all_paths)

    # Start file watcher for the project directory
    FolderWatcherSupervisor.add_folder(project_path)

    assign(socket,
      selected_project: dir_name,
      project_files: sorted_files,
      selected_file: first_file,
      url_project_file: first_file,
      project_annotation_state: nil
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
    first_file = if files != [], do: hd(files).rel_path
    assign(socket, project_files: files, selected_file: first_file, url_project_file: first_file)
  end

  defp after_delete(_tab, socket), do: socket

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
          content_highlight_line: nil,
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

  # --- Custom Folders helpers ---

  # --- Sort helpers ---

  defp next_sort_mode("name", :name_asc), do: :name_desc
  defp next_sort_mode("name", _), do: :name_asc
  defp next_sort_mode("modified", :modified_desc), do: :modified_asc
  defp next_sort_mode("modified", _), do: :modified_desc
  defp next_sort_mode(_, current), do: current

  defp apply_sort(socket) do
    mode = socket.assigns.sort_mode

    socket
    |> sort_plans(mode)
    |> sort_project_files(mode)
    |> sort_folder_files(mode)
    |> sort_search(mode)
  end

  defp sort_plans(socket, mode) do
    sorted =
      case mode do
        :name_asc -> Enum.sort_by(socket.assigns.plans, & &1.display_name)
        :name_desc -> Enum.sort_by(socket.assigns.plans, & &1.display_name, :desc)
        :modified_desc -> Enum.sort_by(socket.assigns.plans, & &1.modified, :desc)
        :modified_asc -> Enum.sort_by(socket.assigns.plans, & &1.modified, :asc)
        _ -> socket.assigns.plans
      end

    assign(socket, plans: sorted)
  end

  defp sort_project_files(socket, mode) do
    assign(socket, project_files: Projects.sort_files(socket.assigns.project_files, mode))
  end

  defp sort_folder_files(socket, mode) do
    assign(socket, folder_files: Folders.sort_files(socket.assigns.folder_files, mode))
  end

  defp sort_search(socket, mode) do
    sorted = sort_search_results_by_mode(socket.assigns.search_results, mode)
    flat_matches = build_flat_matches(sorted)
    assign(socket, search_results: sorted, search_flat_matches: flat_matches)
  end

  defp sort_search_results_by_mode(results, :name_asc),
    do: Enum.sort_by(results, & &1.display_name)

  defp sort_search_results_by_mode(results, :name_desc),
    do: Enum.sort_by(results, & &1.display_name, :desc)

  defp sort_search_results_by_mode(results, :modified_asc),
    do: Enum.sort_by(results, & &1.modified_at, :asc)

  defp sort_search_results_by_mode(results, _), do: Enum.sort_by(results, & &1.modified_at, :desc)

  defp load_custom_folder(socket, folder_id) do
    folder = Enum.find(socket.assigns.custom_folders, &(&1.id == folder_id))

    if folder do
      files = Folders.sort_files(Folders.list_files(folder.path), socket.assigns.sort_mode)

      assign(socket,
        selected_custom_folder: folder_id,
        folder_files: files,
        folder_nav_selected: nil,
        folder_current_path: nil
      )
    else
      socket
    end
  end

  defp current_project_path(assigns) do
    case assigns[:selected_project] do
      nil -> nil
      project -> Path.join(assigns.projects_dir, project)
    end
  end

  defp current_folder_path(assigns) do
    assigns[:folder_current_path] || folder_original_path(assigns)
  end

  defp folder_original_path(assigns) do
    case assigns[:selected_custom_folder] do
      nil ->
        nil

      id ->
        case Enum.find(assigns.custom_folders, &(&1.id == id)) do
          nil -> nil
          folder -> folder.path
        end
    end
  end

  defp find_folder_for_path(folders, file_path) do
    Enum.find_value(folders, fn folder ->
      if String.starts_with?(file_path, folder.path <> "/") do
        {folder, Path.relative_to(file_path, folder.path)}
      end
    end)
  end

  defp list_subdirs(path) do
    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn name ->
          not String.starts_with?(name, ".") and File.dir?(Path.join(path, name))
        end)
        |> Enum.sort()
        |> Enum.take(50)

      {:error, _} ->
        []
    end
  end

  # Reusable annotation panel for LiveComponent-based tabs (Folders, Projects)
  # Events target the component via phx-target={@target}, IDs are prefixed with @prefix
  attr :state, :map, required: true
  attr :target, :string, required: true
  attr :prefix, :string, required: true

  defp component_annotation_panel(assigns) do
    state = assigns.state

    assigns =
      assign(assigns,
        annotations: state.annotations,
        editing_annotation: state.editing_annotation,
        has_file_annotations: state.has_file_annotations,
        selected: state.selected
      )

    ~H"""
    <div class="cb-annotation-panel">
      <div class="cb-annotation-header">
        <span class="cb-section-label">Annotations</span>
        <span :if={@annotations != []} class="cb-count">({length(@annotations)})</span>
        <button :if={@annotations != []} phx-click="clear_annotations" phx-target={@target} class="cb-annotation-clear">Clear all</button>
      </div>
      <div class="cb-annotation-body">
        <div :if={@annotations == []} class="cb-annotation-empty">
          Click any block to annotate it
        </div>
        <div :for={ann <- @annotations} class="cb-annotation-card" id={"#{@prefix}-ann-#{ann.id}"}>
          <div class="cb-annotation-card-header">
            <span class="cb-annotation-label">{ann.id}</span>
            <button phx-click="remove_annotation" phx-value-id={ann.id} phx-target={@target} class="cb-annotation-remove" title="Remove">&times;</button>
          </div>
          <div class="cb-annotation-ref">{ann.block_path}</div>
          <%= if @editing_annotation == ann.id do %>
            <form phx-change="update_annotation" phx-value-id={ann.id} phx-target={@target}>
              <textarea
                id={"#{@prefix}-ann-input-#{ann.id}"}
                name="direction"
                class="cb-annotation-input"
                placeholder="What should change?"
                rows="2"
                phx-debounce="300"
              >{ann.direction}</textarea>
            </form>
            <button phx-click="save_annotation" phx-value-id={ann.id} phx-target={@target} class="cb-annotation-save">Save</button>
          <% else %>
            <div
              phx-click="edit_annotation"
              phx-value-id={ann.id}
              phx-target={@target}
              class={"cb-annotation-display#{if ann.direction == "", do: " cb-annotation-display--empty", else: ""}"}
            >
              {if ann.direction == "", do: "Click to add direction...", else: ann.direction}
            </div>
          <% end %>
        </div>
      </div>
      <div :if={@annotations != []} class="cb-annotation-footer">
        <button
          id={"#{@prefix}-copy-annotations"}
          class="cb-annotation-copy"
          phx-hook="CopyAnnotations"
          data-filename={@selected}
          data-annotations={Jason.encode!(@annotations)}
        >
          Copy All Annotations
        </button>
        <button
          id={"#{@prefix}-write-annotations"}
          class="cb-annotation-write"
          phx-hook="WriteAnnotations"
          phx-click="write_annotations"
          phx-target={@target}
        >
          Write to File
        </button>
      </div>
      <div :if={@annotations == [] && @has_file_annotations} class="cb-annotation-footer">
        <button phx-click="strip_annotations" phx-target={@target} class="cb-annotation-strip">
          Strip Annotations from File
        </button>
      </div>
    </div>
    """
  end
end
