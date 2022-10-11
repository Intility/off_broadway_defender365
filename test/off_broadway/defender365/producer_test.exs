defmodule OffBroadway.Defender365.ProducerTest do
  use ExUnit.Case, async: true

  alias Broadway.Message
  import ExUnit.CaptureLog

  defmodule MessageServer do
    def start_link, do: Agent.start_link(fn -> [] end)

    def push_messages(server, messages),
      do: Agent.update(server, fn queue -> queue ++ messages end)

    def take_messages(server, amount),
      do: Agent.get_and_update(server, &Enum.split(&1, amount))
  end

  defmodule FakeIncidentClient do
    @behaviour OffBroadway.Defender365.Client
    @behaviour Broadway.Acknowledger

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def receive_messages(demand, opts) do
      messages = MessageServer.take_messages(opts[:message_server], demand)
      send(opts[:test_pid], {:messages_received, length(messages)})

      for msg <- messages do
        ack_data = %{
          receipt: %{id: 1},
          test_pid: opts[:test_pid]
        }

        metadata = %{custom: "custom-data"}
        %Message{data: msg, metadata: metadata, acknowledger: {__MODULE__, :ack_ref, ack_data}}
      end
    end

    @impl true
    def ack(_ack_ref, successful, _failed) do
      [%Message{acknowledger: {_, _, %{test_pid: test_pid}}} | _] = successful
      send(test_pid, {:messages_acknowledged, length(successful)})
    end
  end

  defmodule Forwarder do
    use Broadway

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def init(opts), do: {:ok, opts}

    def handle_message(_, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data, message.metadata})
      message
    end

    def handle_batch(_, messages, _, _) do
      messages
    end
  end

  defp prepare_for_start_module_opts(module_opts) do
    {:ok, message_server} = MessageServer.start_link()
    {:ok, pid} = start_broadway(message_server)

    try do
      OffBroadway.Defender365.Producer.prepare_for_start(Forwarder,
        producer: [
          module: {OffBroadway.Defender365.Producer, module_opts},
          concurrency: 1
        ]
      )
    after
      stop_broadway(pid)
    end
  end

  describe "prepare_for_start/2 validation" do
    test ":config should be a non-empty keyword list" do
      assert_raise(
        ArgumentError,
        ~r/invalid configuration given to/,
        fn ->
          prepare_for_start_module_opts([])
        end
      )

      assert {[],
              [
                producer: [
                  module: {OffBroadway.Defender365.Producer, module_opts},
                  concurrency: 1
                ]
              ]} =
               prepare_for_start_module_opts(
                 config: [
                   tenant_id: "your-tenant-id-here",
                   client_id: "your-client-id-here",
                   client_secret: "your-client-secret-here"
                 ]
               )

      assert module_opts[:config] == [
               tenant_id: "your-tenant-id-here",
               client_id: "your-client-id-here",
               client_secret: "your-client-secret-here"
             ]
    end

    test ":from_timestamp is optional" do
      timestamp = DateTime.utc_now()

      assert {[],
              [
                producer: [
                  module: {OffBroadway.Defender365.Producer, module_opts},
                  concurrency: 1
                ]
              ]} =
               prepare_for_start_module_opts(
                 from_timestamp: timestamp,
                 config: [
                   tenant_id: "your-tenant-id-here",
                   client_id: "your-client-id-here",
                   client_secret: "your-client-secret-here"
                 ]
               )

      assert ^timestamp = module_opts[:from_timestamp]
    end
  end

  describe "producer" do
    test "receive messages when the queue has less than the demand" do
      {:ok, message_server} = MessageServer.start_link()
      {:ok, pid} = start_broadway(message_server)

      MessageServer.push_messages(message_server, 1..5)

      assert_receive {:messages_received, 5}

      for msg <- 1..5 do
        assert_receive {:message_handled, ^msg, _}
      end

      stop_broadway(pid)
    end

    test "receive messages with metadata defined by the client" do
      {:ok, message_server} = MessageServer.start_link()
      {:ok, pid} = start_broadway(message_server)
      MessageServer.push_messages(message_server, 1..5)

      assert_receive {:message_handled, _, %{custom: "custom-data"}}

      stop_broadway(pid)
    end

    test "keep receiving messages when the queue has more than the demand" do
      {:ok, message_server} = MessageServer.start_link()
      MessageServer.push_messages(message_server, 1..20)
      {:ok, pid} = start_broadway(message_server)

      assert_receive {:messages_received, 10}

      for msg <- 1..10 do
        assert_receive {:message_handled, ^msg, _}
      end

      assert_receive {:messages_received, 5}

      for msg <- 11..15 do
        assert_receive {:message_handled, ^msg, _}
      end

      assert_receive {:messages_received, 5}

      for msg <- 16..20 do
        assert_receive {:message_handled, ^msg, _}
      end

      assert_receive {:messages_received, 0}

      stop_broadway(pid)
    end

    test "keep trying to receive new messages when the queue is empty" do
      {:ok, message_server} = MessageServer.start_link()
      {:ok, pid} = start_broadway(message_server)

      MessageServer.push_messages(message_server, [13])
      assert_receive {:messages_received, 1}
      assert_receive {:message_handled, 13, _}

      assert_receive {:messages_received, 0}
      refute_receive {:message_handled, _, _}

      MessageServer.push_messages(message_server, [14, 15])
      assert_receive {:messages_received, 2}
      assert_receive {:message_handled, 14, _}
      assert_receive {:message_handled, 15, _}

      stop_broadway(pid)
    end

    test "stop trying to receive new messages after start draining" do
      {:ok, message_server} = MessageServer.start_link()
      broadway_name = new_unique_name()
      {:ok, pid} = start_broadway(broadway_name, message_server, receive_interval: 5_000)

      [producer] = Broadway.producer_names(broadway_name)
      assert_receive {:messages_received, 0}

      # Drain and explicitly ask it to receive messages but it shouldn't work
      Broadway.Topology.ProducerStage.drain(producer)
      send(producer, :receive_messages)

      refute_receive {:messages_received, _}, 10
      stop_broadway(pid)
    end

    test "acknowledged messages" do
      {:ok, message_server} = MessageServer.start_link()
      {:ok, pid} = start_broadway(message_server)

      MessageServer.push_messages(message_server, 1..20)
      assert_receive {:messages_acknowledged, 10}

      stop_broadway(pid)
    end

    test "emit a telemetry start event with demand" do
      self = self()
      {:ok, message_server} = MessageServer.start_link()
      {:ok, pid} = start_broadway(message_server)

      capture_log(fn ->
        :ok =
          :telemetry.attach(
            "start_test",
            [:off_broadway_defender365, :receive_messages, :start],
            fn name, measurements, metadata, _ ->
              send(self, {:telemetry_event, name, measurements, metadata})
            end,
            nil
          )
      end)

      MessageServer.push_messages(message_server, [2])

      assert_receive {:telemetry_event, [:off_broadway_defender365, :receive_messages, :start], %{system_time: _},
                      %{demand: 10}}

      stop_broadway(pid)
    end

    test "emit a telemetry stop event with received count" do
      self = self()
      {:ok, message_server} = MessageServer.start_link()
      {:ok, pid} = start_broadway(message_server)

      capture_log(fn ->
        :ok =
          :telemetry.attach(
            "stop_test",
            [:off_broadway_defender365, :receive_messages, :stop],
            fn name, measurements, metadata, _ ->
              send(self, {:telemetry_event, name, measurements, metadata})
            end,
            nil
          )
      end)

      assert_receive {:telemetry_event, [:off_broadway_defender365, :receive_messages, :stop], %{duration: _},
                      %{received: _, demand: 10}}

      stop_broadway(pid)
    end
  end

  defp start_broadway(broadway_name \\ new_unique_name(), message_server, opts \\ []) do
    Broadway.start_link(
      Forwarder,
      build_broadway_opts(broadway_name, opts,
        incident_client: FakeIncidentClient,
        config: [
          tenant_id: "your-tenant-id-here",
          client_id: "your-client-id-here",
          client_secret: "your-client-secret-here"
        ],
        receive_interval: 0,
        test_pid: self(),
        message_server: message_server
      )
    )
  end

  defp build_broadway_opts(broadway_name, opts, producer_opts) do
    [
      name: broadway_name,
      context: %{test_pid: self()},
      producer: [
        module: {OffBroadway.Defender365.Producer, Keyword.merge(producer_opts, opts)},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 1]
      ],
      batchers: [
        default: [
          batch_size: 10,
          batch_timeout: 50,
          concurrency: 1
        ]
      ]
    ]
  end

  defp new_unique_name() do
    :"Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  defp stop_broadway(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :normal)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    end
  end
end
