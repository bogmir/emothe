defmodule Emothe.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up OpenTelemetry instrumentation
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:emothe, :repo])

    children = [
      EmotheWeb.Telemetry,
      Emothe.Repo,
      {DNSCluster, query: Application.get_env(:emothe, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Emothe.PubSub},
      # Start a worker by calling: Emothe.Worker.start_link(arg)
      # {Emothe.Worker, arg},
      # PDF generation via headless Chrome
      {ChromicPDF, Application.get_env(:emothe, ChromicPDF, [])},
      # Start to serve requests, typically the last entry
      EmotheWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Emothe.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EmotheWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
