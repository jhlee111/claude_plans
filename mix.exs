defmodule ClaudePlans.MixProject do
  use Mix.Project

  @version "0.8.4"

  def project do
    [
      app: :claude_plans,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      name: "ClaudePlans",
      description: "Standalone viewer for Claude Code plans and project memory",
      source_url: "https://github.com/jhlee111/claude_plans",
      homepage_url: "https://github.com/jhlee111/claude_plans",
      docs: docs(),
      listeners: [Phoenix.CodeReloader],
      usage_rules: usage_rules()
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
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:tidewave, "~> 0.5", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:mdex, "~> 0.10"},
      {:rustler, ">= 0.0.0", optional: true},
      {:mermex,
       github: "jhlee111/mermex", branch: "feat/semantic-node-attributes", override: true},
      {:mdex_mermex, "~> 0.1.1"},
      {:file_system, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:burrito, "~> 1.5", only: :prod},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

      defp usage_rules do
        # Example for those using claude.
        [
          file: "CLAUDE.md",
          # rules to include directly in CLAUDE.md
          usage_rules: ["usage_rules:all"],
          skills: [
            location: ".claude/skills",
            # build skills that combine multiple usage rules
            build: [
              "ash-framework": [
                # The description tells people how to use this skill.
                description: "Use this skill working with Ash Framework or any of its extensions. Always consult this when making any domain changes, features or fixes.",
                # Include all Ash dependencies
                usage_rules: [:ash, ~r/^ash_/]
              ],
              "phoenix-framework": [
                description: "Use this skill working with Phoenix Framework. Consult this when working with the web layer, controllers, views, liveviews etc.",
                # Include all Phoenix dependencies
                usage_rules: [:phoenix, ~r/^phoenix_/]
              ]
            ]
          ]
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
