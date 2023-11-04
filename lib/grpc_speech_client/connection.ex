defmodule ExGoogleSTT.GrpcSpeechClient.Connection do
  @moduledoc """
  Main module of the library. It provides a high-level API for Google Cloud Speech-to-Text API.
  """

  @doc """
  Connects to a Google Cloud Speech-to-Text API
  """
  @spec connect() :: {:ok, GRPC.Channel.t()}
  def connect() do
    cred = GRPC.Credential.new(ssl: [cacerts: :certifi.cacerts(), verify: :verify_none])
    gun_opts = [http2_opts: %{keepalive: :infinity}]
    api_port = 443
    api_url = "speech.googleapis.com"

    GRPC.Stub.connect(api_url, api_port, cred: cred, adapter_opts: gun_opts)
  end

  @doc """
  Returns a list of options that need to be passed to a Service Stub when making a gRPC call
  """
  @spec request_opts() :: Keyword.t()
  def request_opts() do
    [
      metadata: authorization_header(),
      timeout: :infinity
    ]
  end

  defp authorization_header do
    credentials = Application.get_env(:goth, :json) |> Jason.decode!()

    with {:ok, token} <- Goth.Token.fetch(source: {:service_account, credentials}) do
      %{"authorization" => "#{token.type} #{token.token}"}
    end
  end

  @doc """
  Disconnects from Google Cloud Speech-to-Text API
  """
  @spec disconnect(GRPC.Channel.t()) :: {:ok, GRPC.Channel.t()} | {:error, any()}
  defdelegate disconnect(channel), to: GRPC.Stub
end
