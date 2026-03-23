defmodule ClaudePlans.Web.Components.Helpers do
  @moduledoc "Shared helper functions used by sidebar and content components."

  def format_time(posix_time) when is_integer(posix_time) do
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

  def format_version_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M")
  end

  def format_bytes(bytes) when is_integer(bytes) do
    if bytes >= 1024 do
      "#{Float.round(bytes / 1024, 1)} KB"
    else
      "#{bytes} B"
    end
  end

  def action_icon(:created), do: "+"
  def action_icon(:updated), do: "~"
  def action_icon(:deleted), do: "-"

  def category_label(:plan), do: "plan"
  def category_label(:project_memory), do: "memory"
  def category_label(:project_config), do: "config"

  def format_project_name(dir_name), do: ClaudePlans.Projects.display_name(dir_name)

  def source_label(%{source: :plan}), do: "plan"
  def source_label(%{source: :project, project: proj}), do: "project: #{proj}"

  def search_result_active?(result, assigns) do
    case result do
      %{source: :plan, filename: f} ->
        assigns.selected == f

      %{source: :project, project: p, rel_path: r} ->
        assigns.selected_project == p && assigns.selected_file == r
    end
  end

  def editor_url(file_path) do
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
