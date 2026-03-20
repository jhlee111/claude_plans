defmodule ClaudePlans do
  @moduledoc "Standalone viewer for Claude Code plans and project memory."

  def plans_dir, do: Application.get_env(:claude_plans, :plans_dir)
  def projects_dir, do: Application.get_env(:claude_plans, :projects_dir)
end
