defmodule ExGoogleSTT.Grpc.StreamClientTest do
  @moduledoc false

  # needs to be false, so that we can use `put_env`
  use ExUnit.Case, async: false

  alias ExGoogleSTT.Grpc.StreamClient

  @moduletag :integration

  setup do
    original_env = Application.get_env(:goth, :json)

    on_exit(fn ->
      Application.put_env(:goth, :json, original_env)
    end)
  end

  describe "start_stream/0" do
    test "returns a stream, if credentials are valid" do
      assert {:ok, %GRPC.Client.Stream{}} = StreamClient.start_stream()
    end

    test "raises an error, if credentials are invalid" do
      invalid_creds = Jason.encode!(%{"private_key" => "invalid", "client_email" => "invalid"})
      Application.put_env(:goth, :json, invalid_creds)
      assert_raise ArgumentError, &StreamClient.start_stream/0
    end
  end
end
