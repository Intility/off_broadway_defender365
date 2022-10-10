defmodule OffBroadway365Defender.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Microsoft 365 Defender API Producer for Broadway"
  @source_url "https://gitlab.intility.com/soc/off_broadway_defender365"

  def project do
    [
      app: :off_broadway_defender365,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      package: [
        maintainers: ["Rolf Håvard Blindheim <rolf.havard.blindheim@intility.no>"],
        licenses: ["Apache-2.0"],
        links: %{Gitlab: @source_url}
      ],
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        extras: [
          "README.md",
          "LICENSE"
        ]
      ],
      test_coverage: [
        summary: [threshold: 80]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: extra_applications(Mix.env())
    ]
  end

  def extra_applications(env) when env in [:dev, :test], do: [:logger, :hackney]
  def extra_applications(_), do: [:logger]

  defp deps do
    [
      {:broadway, "~> 1.0"},
      {:decimal, "~> 2.0"},
      {:ex_doc, "~> 0.28.4", only: [:dev, :test], runtime: false},
      {:exconstructor, "~> 1.2"},
      {:hackney, "~> 1.18", optional: true},
      {:jason, ">= 1.0.0"},
      {:junit_formatter, "~> 3.3", only: :test},
      {:mix_test_watch, "~> 1.1", only: :dev},
      {:nimble_options, "~> 0.3 or ~> 0.4"},
      {:telemetry, "~> 1.1"},
      {:tesla, "~> 1.4"}
    ]
  end
end
