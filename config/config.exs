import Config

case config_env() do
  :dev ->
    config :mix_test_watch, tasks: ["test --cover"]

    config :tesla, adapter: {Tesla.Adapter.Hackney, [recv_timeout: 30_000]}

  # config :off_broadway_defender365, :api_client,
  #   base_url: System.get_env("MS_GRAPH_BASE_URL", "https://graph.microsoft.com"),
  #   client_secret: System.get_env("MS_GRAPH_CLIENT_SECRET", "your-api-token-here"),
  #   client_id: System.get_env("MS_GRAPH_CLIENT_ID", "your-client-id-here")

  :test ->
    config :tesla, adapter: Tesla.Mock
end
