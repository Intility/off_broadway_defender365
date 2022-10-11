defmodule OffBroadway.Defender365.Options do
  @moduledoc """
  OffBroadway Defender365 option definition and custom validators.
  """
  def definition do
    [
      receive_interval: [
        type: :non_neg_integer,
        doc: """
        The duration (in milliseconds) for which the producer waits before
        making a request for more messages. Keep in mind that the 365 Defender API
        quota is 50 calls per minute and 1500 calls per hour.
        """,
        default: 5000
      ],
      from_timestamp: [
        type: {
          :custom,
          __MODULE__,
          :type_date_time
        },
        doc: """
        If present, use this value to fetch incidents with "lastUpdateTime" greater or
        equal to given value.
        """
      ],
      on_success: [
        type: :atom,
        doc: """
        Configures the acking behaviour for successful messages. See the "Acknowledgements"
        section below for all the possible values.
        """,
        default: :ack
      ],
      on_failure: [
        type: :atom,
        doc: """
        Configures the acking behaviour for failed messages. See the "Acknowledgements"
        section below for all the possible values.
        """,
        default: :noop
      ],
      incident_client: [
        doc: """
        A module that implements the `OffBroadway.Defender365.Client` behaviour.
        This module is responsible for fetching and acknowledging the messages
        from the 365 Defender APIs. All options passed to the producer will also be forwarded to
        the client.
        """,
        type: :mod_arg,
        default: OffBroadway.Defender365.IncidentClient
      ],
      config: [
        type: :non_empty_keyword_list,
        required: true,
        keys: [
          tenant_id: [type: :string, required: true, doc: "Tenant ID to consume incidents for"],
          client_id: [type: :string, required: true, doc: "Client ID to use for obtaining authentication token"],
          client_secret: [type: :string, required: true, doc: "Client secret to use for obtaining authentication token"]
        ],
        doc: """
        A set of config options that overrides the default config for the `incident_client`
        module. Any option set here can also be configured in `config.exs`.
        """,
        default: []
      ],
      test_pid: [type: :pid, doc: false],
      message_server: [type: :pid, doc: false]
    ]
  end

  def type_date_time(value) when is_struct(value), do: {:ok, value}
end
