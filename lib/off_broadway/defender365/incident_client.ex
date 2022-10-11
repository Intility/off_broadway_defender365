defmodule OffBroadway.Defender365.IncidentClient do
  @moduledoc """
  Default API client used by `OffBroadway.Defender365.Producer` to receive incidents
  from Microsoft 365 Defender
  [Incident APIs](https://learn.microsoft.com/en-us/microsoft-365/security/defender/api-incident).
  An incident is a collection of related alerts that help describe an attack. Events from
  different entities in an organization are automatically aggregated by Microsoft Defender 365.

  This module implements the `OffBroadway.Defender365.Client` and `Broadway.Acknowledger`
  behaviours which defines callbacks for receiving and acknowledging events.

  The 365 Defender Incident client uses the `api.security.microsoft.com` endpoints for receiving
  incidents and is implemented using the [Tesla](https://hexdocs.pm/tesla/readme.html) library.
  Tesla is a HTTP client abstraction library which lets us easily select from a range of HTTP adapters.
  Please see the Tesla [documentation](https://hexdocs.pm/tesla/readme.html#adapters)
  for more information.

  The following quotas are enforced for the incidents API:

    - Maximum page size is **100 incidents**
    - Maximum rate of requests is **50 calls per minute** and **1500 calls per hour**

  The following permissions are required to call the incidents API:

    - Permission type: **Application** - _Incident.Read.All_
    - Permission type: **Application** - _Incident.ReadWrite.All_
    - Permission type: **Delegated** - _Incident.Read_
    - Permission type: **Delegated** - _Incident.ReadWrite_
  """
  alias Broadway.{Acknowledger, Message}
  alias OffBroadway.Defender365.Incident
  require Logger

  @behaviour Acknowledger
  @behaviour OffBroadway.Defender365.Client

  @impl true
  def init(opts) do
    {:ok,
     opts
     |> prepare_cfg(Application.get_env(:off_broadway_defender365, :defender365_client) || [])
     |> Keyword.put(:ack_ref, opts[:broadway][:name])}
  end

  @doc """
  Returns a `Tesla.Client` configured with middleware.

    * `Tesla.Middleware.BaseUrl` middleware configured with `base_url` passed via `opts`.
    * `Tesla.Middleware.BearerAuth` middleware configured with `api_token` passed via `opts`.
    * `Tesla.Middleware.Query` middleware configured with `query` passed via `opts`.
    * `Tesla.Middleware.JSON` middleware configured with `Jason` engine.
  """
  @spec client(opts :: Keyword.t()) :: Tesla.Client.t()
  def client(opts) do
    middleware = [
      {Tesla.Middleware.BaseUrl, client_option(opts, :base_url)},
      {Tesla.Middleware.BearerAuth, token: fetch_client_token(opts)},
      {Tesla.Middleware.Query, client_option(opts, :query)},
      {Tesla.Middleware.JSON, engine: Jason}
    ]

    Tesla.client(middleware)
  end

  @impl true
  def receive_messages(demand, opts) when is_integer(demand) and demand in 1..100 do
    client(put_demand_query(demand, opts))
    |> Tesla.get("/api/incidents")
    |> wrap_received_messages(opts)
  end

  @impl Acknowledger
  def ack(ack_ref, successful, failed) do
    ack_options = :persistent_term.get(ack_ref)

    messages =
      Enum.filter(successful, &ack?(&1, ack_options, :on_success)) ++
        Enum.filter(failed, &ack?(&1, ack_options, :on_failure))

    Enum.each(messages, &ack_message(&1, ack_options))
  end

  @impl true
  def ack_message(message, ack_options) do
    :telemetry.execute(
      [:off_broadway_defender365, :receive_messages, :ack],
      %{time: System.system_time(), count: 1},
      %{tenant_id: ack_options.config[:tenant_id], receipt: extract_message_receipt(message)}
    )
  end

  defp ack?(message, ack_options, option) do
    {_, _, msg_ack_options} = message.acknowledger
    (msg_ack_options[option] || Map.fetch!(ack_options, option)) == :ack
  end

  defp wrap_received_messages(
         {:ok, %Tesla.Env{status: 200, body: %{"value" => messages}}},
         opts
       ) do
    Enum.map(messages, fn message ->
      metadata = Map.put(message, "tenant_id", opts[:tenant_id]) |> to_struct("metadata")
      alerts = to_struct(message, "alerts")
      acknowledger = build_acknowledger(metadata, opts[:ack_ref])
      %Message{data: alerts, metadata: metadata, acknowledger: acknowledger}
    end)
  end

  defp wrap_received_messages({:ok, %Tesla.Env{status: status_code, body: body}}, _opts) do
    Logger.error(
      "Failed to fetch incidents from remote host. " <>
        "Request failed with status code #{status_code} and response body #{inspect(body)}."
    )

    []
  end

  defp build_acknowledger(metadata, ack_ref) do
    receipt = %{id: metadata.incident_id}
    {__MODULE__, ack_ref, %{receipt: receipt}}
  end

  defp extract_message_receipt(%{acknowledger: {_, _, %{receipt: receipt}}}), do: receipt

  @spec to_struct(message :: map, key :: binary) :: map
  defp to_struct(message, "metadata") do
    Incident.Metadata.new(message)
    |> Map.put(:comments, Map.get(message, "comments", []) |> Enum.map(&Incident.Comment.new/1))
  end

  defp to_struct(message, "alerts") do
    Map.get(message, "alerts", [])
    |> Enum.map(&Incident.Alert.new/1)
    |> Enum.map(fn alert -> Map.put(alert, :devices, Enum.map(alert.devices, &Incident.Device.new/1)) end)
    |> Enum.map(fn alert -> Map.put(alert, :entities, Enum.map(alert.entities, &Incident.Entity.new/1)) end)
  end

  @spec put_demand_query(demand :: pos_integer, Keyword.t()) :: Keyword.t()
  defp put_demand_query(demand, opts) do
    query = client_option(opts, :query) |> Keyword.put(:"$top", demand)
    Keyword.put(opts, :query, query)
  end

  @spec prepare_cfg(opts :: Keyword.t(), env :: Keyword.t()) :: Keyword.t()
  defp prepare_cfg(opts, env), do: Keyword.merge(env, Keyword.get(opts, :config))

  @spec fetch_client_token(opts :: Keyword.t()) :: String.t()
  defp fetch_client_token(opts) do
    middleware = [
      Tesla.Middleware.FormUrlencoded,
      {Tesla.Middleware.BaseUrl, "https://login.windows.net/#{opts[:tenant_id]}"}
    ]

    with body <- prepare_auth_client_body(opts),
         client <- Tesla.client(middleware),
         %Tesla.Env{status: 200, body: response_body} <- Tesla.post!(client, "/oauth2/token", body) do
      Map.fetch!(response_body, "access_token")
    else
      %Tesla.Env{status: status, body: response_body} ->
        Logger.error(
          "Failed to obtain access token for service. " <>
            "Request failed with status code #{status} and response body: #{inspect(response_body)}"
        )

        ""
    end
  end

  @spec prepare_auth_client_body(opts :: Keyword.t()) :: map
  defp prepare_auth_client_body(opts),
    do: %{
      "resource" => "https://api.security.microsoft.com",
      "client_id" => opts[:client_id],
      "client_secret" => opts[:client_secret],
      "grant_type" => "client_credentials"
    }

  @spec client_option(opts :: Keyword.t(), Atom.t()) :: any
  defp client_option(opts, :base_url), do: Keyword.get(opts, :base_url, "https://api.security.microsoft.com")
  defp client_option(opts, :tenant_id), do: Keyword.get(opts, :tenant_id, "")
  defp client_option(opts, :client_id), do: Keyword.get(opts, :client_id, "")
  defp client_option(opts, :client_secret), do: Keyword.get(opts, :client_secret, "")
  defp client_option(opts, :query), do: Keyword.get(opts, :query, [])
end
