defmodule ClaudePlans.Web.BrowserLive do
  use Phoenix.LiveView

  alias ClaudePlans.Watcher
  alias ClaudePlans.Renderer
  alias ClaudePlans.SearchIndex

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Watcher.subscribe()

    plans = Watcher.list_plans()
    projects_dir = ClaudePlans.projects_dir()
    projects = list_projects(projects_dir)

    {selected, html} =
      case plans do
        [first | _] -> {first.filename, Renderer.to_html(File.read!(first.path))}
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
       highlight_index: nil,
       content_highlight: nil,
       show_help: false
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

    {:noreply, assign(socket, active_tab: tab, highlight_index: nil, content_highlight: nil)}
  end

  def handle_event("select_plan", %{"filename" => filename}, socket) do
    path = Path.join(ClaudePlans.plans_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           selected: filename,
           html: Renderer.to_html(content),
           content_highlight: nil
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
        {:noreply,
         assign(socket,
           selected_file: rel_path,
           file_html: Renderer.to_html(content),
           content_highlight: nil
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # --- Search ---

  def handle_event("search", %{"query" => query}, socket) do
    query = String.trim(query)

    {results, highlight_index} =
      if query == "" do
        {[], nil}
      else
        results = SearchIndex.search(query)
        {results, if(results != [], do: 0, else: nil)}
      end

    {:noreply,
     assign(socket,
       search_query: query,
       search_results: results,
       highlight_index: highlight_index,
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
       highlight_index: nil,
       content_highlight: nil
     )}
  end

  def handle_event("select_search_result", %{"index" => idx_str}, socket) do
    idx = String.to_integer(idx_str)

    case Enum.at(socket.assigns.search_results, idx) do
      nil -> {:noreply, socket}
      result -> select_search_result(socket, result, idx)
    end
  end

  # --- Keyboard Navigation ---

  def handle_event("kb_navigate", %{"direction" => dir}, socket) do
    list = visible_list(socket)
    max_idx = max(length(list) - 1, 0)
    current = socket.assigns.highlight_index

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

    if socket.assigns.search_query != "" and new_idx != nil do
      case Enum.at(list, new_idx) do
        nil -> {:noreply, assign(socket, highlight_index: new_idx)}
        result -> select_search_result(socket, result, new_idx)
      end
    else
      {:noreply, assign(socket, highlight_index: new_idx)}
    end
  end

  def handle_event("kb_select", _params, socket) do
    list = visible_list(socket)
    idx = socket.assigns.highlight_index

    case Enum.at(list, idx || -1) do
      nil ->
        {:noreply, socket}

      item ->
        if socket.assigns.search_query != "" do
          select_search_result(socket, item, idx || 0)
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
        socket.assigns.show_help ->
          assign(socket, show_help: false)

        socket.assigns.content_highlight != nil ->
          assign(socket, content_highlight: nil)

        socket.assigns.search_query != "" ->
          assign(socket,
            search_query: "",
            search_results: [],
            highlight_index: nil,
            content_highlight: nil
          )

        socket.assigns.highlight_index != nil ->
          assign(socket, highlight_index: nil)

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("kb_tab", %{"tab" => tab}, socket) do
    socket =
      assign(socket,
        highlight_index: nil,
        search_query: "",
        search_results: [],
        content_highlight: nil
      )

    handle_event("switch_tab", %{"tab" => tab}, socket)
  end

  def handle_event("kb_help", _params, socket) do
    {:noreply, assign(socket, show_help: !socket.assigns.show_help)}
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
              [first | _] -> {first.filename, Renderer.to_html(File.read!(first.path))}
              [] -> {nil, nil}
            end

          plan ->
            {plan.filename, Renderer.to_html(File.read!(plan.path))}
        end
      else
        case plans do
          [first | _] -> {first.filename, Renderer.to_html(File.read!(first.path))}
          [] -> {nil, nil}
        end
      end

    {:noreply, assign(socket, plans: plans, selected: selected, html: html, highlight_index: nil)}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div id="kb-nav" class="cb-layout" phx-hook="KeyboardNav">
      <div class="cb-sidebar">
        <div class="cb-tabs">
          <button
            :for={{id, label} <- [{:plans, "Plans"}, {:projects, "Projects"}]}
            phx-click="switch_tab"
            phx-value-tab={id}
            class={"cb-tab#{if @active_tab == id, do: " cb-tab--active", else: ""}"}
          >
            {label}
          </button>
          <button phx-click="kb_help" class="cb-help-btn" title="Keyboard shortcuts">?</button>
          <button id="theme-toggle" class="cb-theme-toggle" phx-hook="ThemeToggle" phx-update="ignore">&#9790;</button>
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
            <button :if={@search_query != ""} phx-click="clear_search" class="cb-search-clear" title="Clear search (Esc)">&times;</button>
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
            <dt><kbd>1</kbd> <kbd>2</kbd></dt><dd>Plans / Projects tab</dd>
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
        class={"cb-file-btn#{if @highlight_index == idx, do: " cb-file-btn--active cb-file-btn--highlighted", else: ""}"}
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
    <div :for={{plan, idx} <- Enum.with_index(@plans)} class="cb-file-row">
      <button
        phx-click="select_plan"
        phx-value-filename={plan.filename}
        class={"cb-file-btn#{if @selected == plan.filename, do: " cb-file-btn--active", else: ""}#{if @highlight_index == idx and @search_query == "", do: " cb-file-btn--highlighted", else: ""}"}
      >
        <div class="cb-file-name">{plan.display_name}</div>
        <div class="cb-file-time">{format_time(plan.modified)}</div>
      </button>
      <span
        id={"copy-plan-#{plan.filename}"}
        class="cb-copy-btn"
        phx-hook="CopyPath"
        data-path={plan.path}
        title={plan.path}
      >Copy Path</span>
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
      <div :for={{file, idx} <- Enum.with_index(@project_files)} class="cb-file-row">
        <button
          phx-click="select_file"
          phx-value-path={file.rel_path}
          class={"cb-file-btn#{if @selected_file == file.rel_path, do: " cb-file-btn--active", else: ""}#{if @highlight_index == idx and @search_query == "", do: " cb-file-btn--highlighted", else: ""}"}
        >
          <div class="cb-file-name">
            <span :if={file.dir} class="cb-file-dir">{file.dir}/</span>{file.name}
          </div>
        </button>
        <span
          id={"copy-file-#{file.rel_path}"}
          class="cb-copy-btn"
          phx-hook="CopyPath"
          data-path={Path.join([@projects_dir, @selected_project, file.rel_path])}
          title={Path.join([@projects_dir, @selected_project, file.rel_path])}
        >Copy Path</span>
      </div>
      <div :if={@project_files == []} class="cb-empty">No .md files</div>
    </div>
    """
  end

  defp main_content(%{active_tab: :plans} = assigns) do
    ~H"""
    <div :if={@html} class="cb-content-wrap">
      <div class="cb-file-header">{@selected}</div>
      <div id="plan-content" class="cp-content" phx-hook="Mermaid" phx-update="replace" data-highlight={@content_highlight}>
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
      <div id="project-file-content" class="cp-content" phx-hook="Mermaid" phx-update="replace" data-highlight={@content_highlight}>
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
      current = socket.assigns.highlight_index || -1

      new_idx =
        case direction do
          :next -> min(current + 1, max_idx)
          :prev -> max(current - 1, 0)
        end

      case Enum.at(results, new_idx) do
        nil -> {:noreply, socket}
        result -> select_search_result(socket, result, new_idx)
      end
    end
  end

  defp visible_list(socket) do
    cond do
      socket.assigns.search_query != "" -> socket.assigns.search_results
      socket.assigns.active_tab == :plans -> socket.assigns.plans
      socket.assigns.active_tab == :projects -> socket.assigns.project_files
      true -> []
    end
  end

  defp select_visible_item(socket, item) do
    case socket.assigns.active_tab do
      :plans ->
        handle_event("select_plan", %{"filename" => item.filename}, socket)

      :projects ->
        handle_event("select_file", %{"path" => item.rel_path}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  defp select_search_result(socket, %{source: :plan} = result, idx) do
    path = Path.join(ClaudePlans.plans_dir(), result.filename)
    highlight = socket.assigns.search_query

    case File.read(path) do
      {:ok, content} ->
        {:noreply,
         assign(socket,
           active_tab: :plans,
           selected: result.filename,
           html: Renderer.to_html(content),
           highlight_index: idx,
           content_highlight: highlight
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp select_search_result(socket, %{source: :project, project: proj, rel_path: rel}, idx) do
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
           file_html: Renderer.to_html(content),
           highlight_index: idx,
           content_highlight: highlight
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp source_label(%{source: :plan}), do: "plan"
  defp source_label(%{source: :project, project: proj}), do: "project: #{proj}"

  defp load_project(socket, dir_name) do
    projects_dir = socket.assigns.projects_dir
    files = list_project_files(projects_dir, dir_name)

    {selected_file, file_html} =
      case files do
        [first | _] ->
          path = Path.join([projects_dir, dir_name, first.rel_path])
          {first.rel_path, Renderer.to_html(File.read!(path))}

        [] ->
          {nil, nil}
      end

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
    posix_time |> DateTime.from_unix!() |> Calendar.strftime("%b %d, %H:%M")
  end
end
