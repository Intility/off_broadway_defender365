defmodule OffBroadway.Defender365.Producer do
  @moduledoc """
  GenStage Producer for a stream of incidents from the Microsoft 365 Defender APIs.

  ## Producer options

  #{NimbleOptions.docs(OffBroadway.Defender365.Options.definition())}

  ## Acknowledgements

  You can use `on_success` and `on_failure` options to control how messages are
  acknowledged. You can set these options when starting the Defender365 producer,
  or change them for each message through `Broadway.Message.configure_ack/2`.
  By default, successful messages are acked (`:ack`) and failed messages are not (`:noop`).

  The possible values for `:on_success` and `:on_failure` are:

    * `:ack` - acknowledge the message. The 365 defender APIs does not have any concept of
      acking messages because we are just consuming messages from a web api endpoint.
      For now we are just executing a `:telemetry` event for acked messages.

    * `:noop` - do not acknowledge the message. No action are taken.

    ## Telemetry

    This library exposes the following telemetry events:

      * `[:off_broadway_defender365, :receive_messages, :start]` - Dispatched before receiving
        messages from the 365 Defender APIs.

        * measurement: `%{time: System.monotonic_time}`
        * metadata: `%{tenant_id: string, demand: integer}`

      * `[:off_broadway_defender365, :receive_messages, :stop]` - Dispatched after messages have been
        received from the 365 Defender APIs and "wrapped".

        * measurement: `%{time: native_time}`
        * metadata:

        ```
        %{
          tenant_id: string,
          received: integer,
          demand: integer
        }
        ```

      * `[:off_broadway_defender365, :receive_messages, :exception]` - Dispatched after a failure while
        receiving messages from the 365 Defender APIs.

        * measurement: `%{duration: native_time}`
        * metadata:

        ```
        %{
          tenant_id: string,
          demand: integer,
          kind: kind,
          reason: reason,
          stacktrace: stacktrace
        }
            ```

      * `[:off_broadway_defender365, :receive_messages, :ack]` - Dispatched when acking a message.

        * measurement: `%{time: System.system_time, count: 1}`
        * meatadata:

        ```
        %{
          tenant_id: string,
          receipt: receipt
        }
        ```
  """

  use GenStage
  alias Broadway.Producer
  alias NimbleOptions.ValidationError

  require Logger

  @behaviour Producer
  @max_num_req_min 50

  @impl true
  def init(opts) do
    client = opts[:incident_client]
    receive_interval = opts[:receive_interval]
    {:ok, client_opts} = client.init(opts)

    if receive_interval < 60_000 / @max_num_req_min do
      Logger.warning(
        "Receive interval can potentially exceed quota limits of 50 requests per minute. " <>
          "Consider increasing receive interval to no less than 1200ms."
      )
    end

    {:producer,
     %{
       demand: 0,
       receive_timer: nil,
       receive_interval: opts[:receive_interval],
       from_timestamp: opts[:from_timestamp] || DateTime.utc_now(),
       incident_client: {client, client_opts}
     }}
  end

  @impl true
  def prepare_for_start(_module, broadway_opts) do
    {producer_module, client_opts} = broadway_opts[:producer][:module]

    case NimbleOptions.validate(client_opts, OffBroadway.Defender365.Options.definition()) do
      {:error, error} ->
        raise ArgumentError, format_error(error)

      {:ok, opts} ->
        :persistent_term.put(broadway_opts[:name], %{
          config: opts[:config],
          on_success: opts[:on_success],
          on_failure: opts[:on_failure]
        })

        with_default_opts = put_in(broadway_opts, [:producer, :module], {producer_module, opts})
        {[], with_default_opts}
    end
  end

  @impl Producer
  def prepare_for_draining(%{receive_timer: receive_timer} = state) do
    receive_timer && Process.cancel_timer(receive_timer)
    {:noreply, [], %{state | receive_timer: nil}}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    handle_receive_messages(%{state | demand: demand + incoming_demand})
  end

  @impl true
  def handle_info(:receive_messages, %{receive_timer: nil} = state), do: {:noreply, [], state}
  def handle_info(:receive_messages, state), do: handle_receive_messages(%{state | receive_timer: nil})
  def handle_info(_, state), do: {:noreply, [], state}

  defp format_error(%ValidationError{keys_path: [], message: message}) do
    "invalid configuration given to OffBroadway.Defender365.Producer.prepare_for_start/2, " <>
      message
  end

  defp format_error(%ValidationError{keys_path: keys_path, message: message}) do
    "invalid configuration given to OffBroadway.Defender365.Producer.prepare_for_start/2 for key #{inspect(keys_path)}, " <>
      message
  end

  defp handle_receive_messages(%{receive_timer: nil, demand: demand} = state) when demand > 0 do
    messages = receive_messages_from_defender(state, demand)
    new_demand = demand - length(messages)
    from_timestamp = get_last_updated_timestamp(messages)

    receive_timer =
      case {messages, new_demand} do
        {[], _} -> schedule_receive_messages(state.receive_interval)
        {_, 0} -> nil
        _ -> schedule_receive_messages(round(60_000 / @max_num_req_min))
      end

    {:noreply, messages, %{state | demand: new_demand, from_timestamp: from_timestamp, receive_timer: receive_timer}}
  end

  defp handle_receive_messages(state), do: {:noreply, [], state}

  defp receive_messages_from_defender(
         %{incident_client: {client, client_opts}, from_timestamp: timestamp},
         total_demand
       ) do
    metadata = %{tenant_id: client_opts[:config][:tenant_id], demand: total_demand}
    client_opts = Keyword.put(client_opts, :query, "$filter": "lastUpdateTime+ge+#{DateTime.to_iso8601(timestamp)}")

    :telemetry.span(
      [:off_broadway_defender365, :receive_messages],
      metadata,
      fn ->
        messages = client.receive_messages(total_demand, client_opts)
        {messages, Map.put(metadata, :received, length(messages))}
      end
    )
  end

  defp get_last_updated_timestamp(messages) when is_list(messages) do
    timestamps =
      messages
      |> Enum.map(fn
        %{metadata: %{last_update_time: timestamp}} when is_binary(timestamp) -> timestamp
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn timestamp ->
        {:ok, datetime, _offset} = DateTime.from_iso8601(timestamp)
        datetime
      end)

    unless Enum.empty?(timestamps), do: Enum.max(timestamps, DateTime), else: DateTime.utc_now()
  end

  defp schedule_receive_messages(interval), do: Process.send_after(self(), :receive_messages, interval)
end
