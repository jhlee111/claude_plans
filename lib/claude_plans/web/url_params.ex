defmodule ClaudePlans.Web.UrlParams do
  @moduledoc "Pure functions for building and parsing URL query parameters."

  @spec build(map(), map()) :: String.t()
  def build(assigns, overrides \\ %{}) do
    tab = Map.get(overrides, :tab, assigns.active_tab)
    plan = Map.get(overrides, :plan, assigns.selected)
    project = Map.get(overrides, :project, assigns.selected_project)
    file = Map.get(overrides, :file, assigns.selected_file)
    query = Map.get(overrides, :q, assigns.search_query)
    view = Map.get(overrides, :view, assigns.view_mode)
    folder = Map.get(overrides, :folder, assigns[:selected_custom_folder])
    folder_file = Map.get(overrides, :folder_file, assigns[:folder_nav_selected])

    params =
      [
        param("tab", tab != :plans, fn -> Atom.to_string(tab) end),
        param("plan", not is_nil(plan), fn -> plan end),
        param("project", tab == :projects and not is_nil(project), fn -> project end),
        param("file", tab == :projects and not is_nil(file), fn -> file end),
        param("folder", tab == :folders and not is_nil(folder), fn -> folder end),
        param("folder_file", tab == :folders and not is_nil(folder_file), fn -> folder_file end),
        param("q", query != "", fn -> query end),
        param("view", view != :rendered, fn -> Atom.to_string(view) end)
      ]
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    if params == %{}, do: "/", else: "/?" <> URI.encode_query(params)
  end

  @spec parse_tab(String.t() | nil) :: :plans | :projects | :folders | :activity
  def parse_tab("projects"), do: :projects
  def parse_tab("folders"), do: :folders
  def parse_tab("activity"), do: :activity
  def parse_tab(_), do: :plans

  defp param(key, true, value_fn), do: {key, value_fn.()}
  defp param(_key, _false, _value_fn), do: nil
end
