defmodule OffBroadway.Defender365.IncidentClientTest do
  use ExUnit.Case

  import ExUnit.CaptureLog
  import Tesla.Mock

  alias Broadway.Message
  alias OffBroadway.Defender365.IncidentClient
  alias TestHelpers.Fixture

  setup do
    mock(fn
      %{method: :get, url: "https://api.security.microsoft.com/api/incidents"} ->
        %Tesla.Env{status: 200, body: Fixture.read("incidents-response.json") |> Jason.decode!()}

      %{method: :get, url: "https://api-fails.security.microsoft.com/api/incidents"} ->
        %Tesla.Env{status: 400, body: %{"error" => "some error message"}}

      %{method: :post, url: "https://login.windows.net/this-is-my-tenant-id/oauth2/token"} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "token_type" => "Bearer",
            "expires_in" => 3599,
            "ext_expires_in" => 3599,
            "access_token" => "this-is-my-access-token"
          }
        }
    end)
  end

  describe "receiving messages" do
    setup do
      {:ok,
       %{
         opts: [
           broadway: [name: :BroadwayDefenderTest],
           config: [
             tenant_id: "this-is-my-tenant-id",
             client_id: "this-is-my-client-id",
             client_secret: "this-is-my-client-secret"
           ]
         ]
       }}
    end

    test "init/1 returns normalized client options", %{opts: base_opts} do
      assert {:ok,
              [
                ack_ref: :BroadwayDefenderTest,
                tenant_id: "this-is-my-tenant-id",
                client_id: "this-is-my-client-id",
                client_secret: "this-is-my-client-secret"
              ]} = IncidentClient.init(base_opts)
    end

    test "returns a list of Broadway.Message with :data and :acknowledger set", %{opts: base_opts} do
      {:ok, opts} = IncidentClient.init(base_opts)

      [
        %Message{metadata: metadata1, acknowledger: acknowledger1},
        %Message{metadata: metadata2},
        %Message{metadata: metadata3}
      ] = IncidentClient.receive_messages(100, opts)

      assert metadata1.incident_id == 924_565
      assert metadata2.incident_id == 924_521
      assert metadata3.incident_id == 924_518

      assert acknowledger1 ==
               {IncidentClient, :BroadwayDefenderTest, %{receipt: %{id: 924_565}}}
    end

    test "exceeding maximum allowed number of incidents fetches more", %{opts: base_opts} do
      {:ok, opts} = IncidentClient.init(base_opts)

      capture_log(fn ->
        assert 6 == IncidentClient.receive_messages(150, opts) |> length()
      end) =~ """
      [warning] Received demand greater than maximum allowed number of incidents allowed to fetch from 365 Defender API. Trying to fetch remaining 50 incidents, but this can possibly cause quota limits to be exceeded.
      """
    end

    test "if the request fails, return an empty list and log the error", %{opts: base_opts} do
      config =
        Keyword.get(base_opts, :config)
        |> Keyword.put(:base_url, "https://api-fails.security.microsoft.com")

      {:ok, opts} = Keyword.put(base_opts, :config, config) |> IncidentClient.init()

      assert capture_log(fn ->
               assert [] == IncidentClient.receive_messages(100, opts)
             end) =~ """
             [error] Failed to fetch incidents from remote host. Request failed with status code 400 and response body %{\"error\" => \"some error message\"}.
             """
    end
  end

  describe "acknowledging messages" do
    setup do
      {:ok,
       %{
         opts: [
           broadway: [name: :BroadwayDefenderTest],
           config: [
             tenant_id: "this-is-my-tenant-id",
             client_id: "this-is-my-client-id",
             client_secret: "this-is-my-client-secret"
           ],
           on_success: :ack,
           on_failure: :noop
         ]
       }}
    end

    test "emits a telemetry event", %{opts: base_opts} do
      self = self()
      {:ok, opts} = IncidentClient.init(base_opts)

      ack_data = %{receipt: %{id: 1}}
      fill_persistent_term(opts[:broadway][:name], base_opts)

      capture_log(fn ->
        :ok =
          :telemetry.attach(
            "ack_test",
            [:off_broadway_defender365, :receive_messages, :ack],
            fn name, measurements, metadata, _ ->
              send(self, {:telemetry_event, name, measurements, metadata})
            end,
            nil
          )
      end)

      IncidentClient.ack(
        opts[:broadway][:name],
        [%Message{acknowledger: {IncidentClient, opts[:broadway][:name], ack_data}, data: nil}],
        []
      )

      assert_receive {:telemetry_event, [:off_broadway_defender365, :receive_messages, :ack], %{time: _},
                      %{receipt: %{id: 1}, tenant_id: "this-is-my-tenant-id"}}
    end
  end

  defp fill_persistent_term(ack_ref, base_opts) do
    :persistent_term.put(ack_ref, %{
      config: base_opts[:config],
      on_success: base_opts[:on_success] || :ack,
      on_failure: base_opts[:on_failure] || :noop
    })
  end
end
