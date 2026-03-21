defmodule ClaudePlans.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :claude_plans,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: releases(),
      name: "ClaudePlans",
      description: "Standalone viewer for Claude Code plans and project memory",
      source_url: "https://github.com/jhlee111/claude_plans",
      homepage_url: "https://github.com/jhlee111/claude_plans",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ClaudePlans.Application, []}
    ]
  end

  defp deps do
    [
      {:tidewave, "~> 0.5", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:mdex, "~> 0.10"},
      {:file_system, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:burrito, "~> 1.5", only: :prod},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "main"
    ]
  end

  defp releases do
    [
      claude_plans: [
        steps: [:assemble] ++ burrito_steps(),
        burrito: [
          targets: [
            macos_arm: [os: :darwin, cpu: :aarch64]
            # Uncomment to build for other platforms (requires matching native runner):
            # macos_intel: [os: :darwin, cpu: :x86_64],
            # linux_arm: [os: :linux, cpu: :aarch64],
            # linux_intel: [os: :linux, cpu: :x86_64],
            # windows_intel: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp burrito_steps do
    if Mix.env() == :prod do
      [&Burrito.wrap/1]
    else
      []
    end
  end
end
