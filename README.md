# OffBroadway.Defender365

![pipeline status](https://github.com/Intility/off_broadway_defender365/actions/workflows/elixir.yaml/badge.svg?event=push)

[Broadway](https://github.com/dashbitco/broadway) consumer acts as a consumer for incidents reported by the
[Microsoft 365 Defender](https://www.microsoft.com/en-us/security/business/siem-and-xdr/microsoft-365-defender) APIs.

Read the full documentation [here](https://hexdocs.pm/off_broadway_defender365/readme.html).

## Installation

This package is [available in Hex](https://hex.pm/packages/off_broadway_defender365), and can be installed
by adding `off_broadway_defender365` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_defender365, "~> 1.0.0"}
  ]
end
```

## Usage

The `OffBroadway.Defender365.IncidentClient` tries to read the following configuration from `config.exs`.

```elixir
# config.exs

config :off_broadway_defender365, :incident_client,
  base_url: System.get_env("365DEFENDER_BASE_URL", "https://api.security.microsoft.com"),
  tenant_id: System.get_env("365DEFENDER_TENANT_ID", "your-tenant-id-here"),
  client_id: System.get_env("365DEFENDER_CLIENT_ID", "your-client-id-here"),
  client_secret: System.get_env("365DEFENDER_CLIENT_SECRET", "your-client-secret-here")
```

Options for the `OffBroadway.Defender365.IncidentClient` can be configured either in `config.exs` or passed as
options directly to the `OffBroadway.Defender365.Producer` module. Options are merged, with the passed options
taking precedence over those configured in `config.exs`.

```elixir
# my_broadway.ex

defmodule MyBroadway do
  use Broadway

  alias Broadway.Message

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {OffBroadway.Defender365.Producer,
           config: [
             client_id: "your-client-id-here",
             client_secret: "your-client-secret-here",
           ]}
      ],
      processors: [
        default: []
      ],
      batchers: [
        default: [
          batch_size: 500,
          batch_timeout: 5000
        ]
      ]
    )
  end

  ...callbacks...
end
```

### Processing messages

In order to process incoming messages, we need to implement some callback functions.

```elixir
defmodule MyBroadway do
  use Broadway

  alias Broadway.Message

  ...start_link...

  @impl true
  def handle_message(_, %Message{data: data} ,_) do
    message
    |> Message.update_data(fn -> ...whatever... end)
  end

  @impl true
  def handle_batch(_batcher, messages, _batch_info, _context) do
    IO.puts("Received a batch of #{length(messages)} messages!")
    messages
  end
end
```

For the sake of the example, we're not really doing anything here. Whenever we're receiving a batch of messages, we just prints out a
message saying "Received a batch of messages!", and for each message we run `Message.update_data/2` passing a function that can
process that message ie. by doing some calculations on the data or something else.
