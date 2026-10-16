defmodule Acme.MixProject do
  use Mix.Project

  def project do
    [app: :acme, version: "0.1.0", elixir: "~> 1.17", deps: deps()]
  end

  defp deps do
    [{:credo, "~> 1.7", only: [:dev, :test], runtime: false}]
  end
end
