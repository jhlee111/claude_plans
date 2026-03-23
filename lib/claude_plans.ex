defmodule ClaudePlans do
  @moduledoc "Standalone viewer for Claude Code plans and project memory."

  @spec claude_dir() :: String.t()
  def claude_dir, do: Path.expand("~/.claude")

  @spec plans_dir() :: String.t() | nil
  def plans_dir, do: Application.get_env(:claude_plans, :plans_dir)

  @spec projects_dir() :: String.t() | nil
  def projects_dir, do: Application.get_env(:claude_plans, :projects_dir)
end
