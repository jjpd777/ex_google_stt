defmodule ExGoogleSTT.Grpc.StreamClient do
  @moduledoc """
  Connection module for GRPC. It connects to Google Cloud Speech-to-Text API and returns a Stream.
  """

  alias Google.Cloud.Speech.V2.Speech.Stub, as: SpeechStub
  alias GRPC.Client.Stream

  @doc """
  Starts s Google STT streaming client
  """
  @spec start_stream() :: {:ok, Stream.t()} | {:error, any()}
  def start_stream() do
    with {:ok, channel} <- connect() do
      stream = SpeechStub.streaming_recognize(channel, request_opts())
      {:ok, stream}
    end
  end

  defp request_opts() do
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

  @spec connect() :: {:ok, GRPC.Channel.t()}
  defp connect() do
    cred = GRPC.Credential.new(ssl: [cacerts: :public_key.cacerts_get(), verify: :verify_none])
    api_port = 443
    api_url = "speech.googleapis.com"

    GRPC.Stub.connect(api_url, api_port, cred: cred, adapter: GRPC.Client.Adapters.Mint)
  end

  @doc """
  Disconnects from Google Cloud Speech-to-Text API
  """
  @spec disconnect(GRPC.Channel.t()) :: {:ok, GRPC.Channel.t()} | {:error, any()}
  defdelegate disconnect(channel), to: GRPC.Stub
end
