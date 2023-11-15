defmodule ExGoogleSTT.MixProject do
  use Mix.Project

  @version "0.2.1"
  @github_url "https://github.com/luiz-pereira/ex_google_stt"

  def project do
    [
      app: :ex_google_stt,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Elixir client for Google Speech-to-Text streaming API using gRPC",
      package: package(),
      name: "Google Speech gRPC API",
      source_url: @github_url,
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:certifi, "~> 2.12"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:goth, "~> 1.3"},
      {:grpc, "~> 0.7"},
      {:protobuf, "~> 0.12"}
    ]
  end

  defp package do
    [
      maintainers: ["Luiz Pereira"],
      links: %{
        "GitHub" => @github_url
      },
      licenses: ["Apache-2.0"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Auto-generated": [
          ~r/Google\.Cloud\.Speech.V1\..*/,
          ~r/Google\.Longrunning..*/,
          ~r/Google\.Protobuf\..*/,
          ~r/Google\.Rpc\..*/
        ]
      ],
      nest_modules_by_prefix: [
        ExGoogleSTT,
        Google.Cloud.Speech.V1,
        Google.Longrunning,
        Google.Protobuf,
        Google.Rpc
      ]
    ]
  end
end
