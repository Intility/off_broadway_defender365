ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])
ExUnit.start(capture_log: true)

defmodule TestHelpers do
  defmodule Fixture do
    def read(filename), do: File.read!("test/support/fixtures/#{filename}")
  end
end
