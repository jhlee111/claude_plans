defmodule ClaudePlans.Web.BrowserLive do
  use Phoenix.LiveView

  alias ClaudePlans.Watcher
  alias ClaudePlans.Renderer

  @projects_dir Path.expand("~/.claude/projects")

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Watcher.subscribe()

    plans = Watcher.list_plans()
    projects = list_projects()

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
       projects_dir: @projects_dir
     )}
  end

  # --- Events ---

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      case tab do
        :projects when is_nil(socket.assigns.selected_project) and socket.assigns.projects != [] ->
          [first | _] = socket.assigns.projects
          load_project(socket, first.dir_name)

        _ ->
          socket
      end

    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("select_plan", %{"filename" => filename}, socket) do
    path = Path.join(ClaudePlans.plans_dir(), filename)

    case File.read(path) do
      {:ok, content} ->
        {:noreply, assign(socket, selected: filename, html: Renderer.to_html(content))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("select_project", %{"project" => ""}, socket), do: {:noreply, socket}

  def handle_event("select_project", %{"project" => dir_name}, socket) do
    {:noreply, load_project(socket, dir_name)}
  end

  def handle_event("select_file", %{"path" => rel_path}, socket) do
    full_path = Path.join([@projects_dir, socket.assigns.selected_project, rel_path])

    case File.read(full_path) do
      {:ok, content} ->
        {:noreply, assign(socket, selected_file: rel_path, file_html: Renderer.to_html(content))}

      {:error, _} ->
        {:noreply, socket}
    end
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

    {:noreply, assign(socket, plans: plans, selected: selected, html: html)}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="cb-layout">
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
        </div>
        <div class="cb-sidebar-body">
          {sidebar_content(assigns)}
        </div>
      </div>
      <div class="cb-main">
        {main_content(assigns)}
      </div>
    </div>
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
      <div id="plan-content" class="cp-content" phx-hook="Mermaid" phx-update="replace">
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
      <div id="project-file-content" class="cp-content" phx-hook="Mermaid" phx-update="replace">
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

  defp load_project(socket, dir_name) do
    files = list_project_files(dir_name)

    {selected_file, file_html} =
      case files do
        [first | _] ->
          path = Path.join([@projects_dir, dir_name, first.rel_path])
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

  defp list_projects do
    case File.ls(@projects_dir) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(&File.dir?(Path.join(@projects_dir, &1)))
        |> Enum.map(fn dir_name ->
          candidate = "/" <> (dir_name |> String.trim_leading("-") |> String.replace("-", "/"))

          display =
            if File.dir?(candidate) do
              Path.relative_to(candidate, System.user_home!()) |> then(&"~/#{&1}")
            else
              dir_name |> String.trim_leading("-Users-#{System.get_env("USER", "user")}-")
            end

          has_memory? = File.dir?(Path.join([@projects_dir, dir_name, "memory"]))
          %{dir_name: dir_name, display_name: display, has_memory?: has_memory?}
        end)
        |> Enum.filter(& &1.has_memory?)
        |> Enum.sort_by(& &1.display_name)

      {:error, _} ->
        []
    end
  end

  defp list_project_files(dir_name) do
    project_path = Path.join(@projects_dir, dir_name)
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
