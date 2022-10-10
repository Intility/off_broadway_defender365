defmodule OffBroadway.Defender365.Client do
  @moduledoc """
  A generic behaviour for implementing 365 Defender API clients for
  `OffBroadway.Defender365.Producer`.

  This module defines callbacks to normalize options and receive events for
  Microsoft 365 Defender REST APIs.

  Modules that implements this behaviour should be passed as the `:defender365_client`
  option from `OffBroadway.Defender365.Producer`.
  """

  alias Broadway.Message

  @type messages :: [Message.t()]

  @callback init(opts :: any) :: {:ok, normalized_opts :: any} | {:error, reason :: binary}
  @callback ack_message(message :: Message.t(), ack_options :: any) :: any
  @callback receive_messages(demand :: pos_integer, opts :: any) :: messages

  @optional_callbacks ack_message: 2
end
