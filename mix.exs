defmodule OffBroadway365Defender.MixProject do
  use Mix.Project

  @version "1.0.3"
  @description "Microsoft 365 Defender API Producer for Broadway"
  @source_url "https://github.com/Intility/off_broadway_defender365"

  def project do
    [
      app: :off_broadway_defender365,
      version: @version,
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @description,
      deps: deps(),
      package: [
        name: "off_broadway_defender365",
        maintainers: ["Rolf Håvard Blindheim <rolf.havard.blindheim@intility.no>"],
        licenses: ["Apache-2.0"],
        links: %{GitHub: @source_url}
      ],
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        source_url: @source_url,
        extras: [
          "README.md",
          "LICENSE"
        ]
      ],
      test_coverage: [
        [tool: ExCoveralls],
        summary: [threshold: 90]
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
      {:exconstructor, "~> 1.2"},
      {:excoveralls, "~> 0.16.0", only: :test},
      {:ex_doc, "~> 0.29", only: [:dev, :test], runtime: false},
      {:hackney, "~> 1.18", optional: true},
      {:jason, "~> 1.4"},
      {:mix_test_watch, "~> 1.1", only: :dev},
      {:nimble_options, "~> 0.5 or ~> 1.0"},
      {:telemetry, "~> 1.2"},
      {:tesla, "~> 1.5"}
    ]
  end
end
