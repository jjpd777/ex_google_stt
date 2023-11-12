defmodule ExGoogleSTT.TranscriptionServer do
  @moduledoc """
  A Server to handle transcription requests.
  """
  alias ExGoogleSTT.Grpc.StreamClient

  alias Google.Cloud.Speech.V2.{
    StreamingRecognizeRequest
  }

  alias GRPC.Stub, as: GrpcStub
  alias GRPC.Client.Stream, as: GrpcStream

  #  TODO: ensures that if the caller dies, the stream is closed

  defdelegate start_stream, to: StreamClient, as: :start
  defdelegate stop_stream(stream), to: StreamClient, as: :stop

  def end_stream(stream), do: GrpcStub.end_stream(stream)

  @spec send_config(GrpcStream.t(), StreamingRecognizeRequest.t(), Keyword.t()) ::
          {:ok, GrpcStream.t()} | {:error, any()}
  def send_config(stream, cfg_request, opts \\ []), do: send_request(stream, cfg_request, opts)

  @spec send_request(GrpcStream.t(), StreamingRecognizeRequest.t(), Keyword.t()) ::
          {:ok, GrpcStream.t()} | {:error, any()}
  def send_request(stream, request, opts \\ []) do
    with %GrpcStream{} = stream <- GrpcStub.send_request(stream, request, opts) do
      {:ok, stream}
    end
  end

  @doc """
  Runs a loop that receives responses from the stream and performs the function provided on each response
  Must be called after the config and at least one audio request have been sent
  """
  @spec receive_stream_responses(GrpcStream.t(), fun()) :: :ok
  def receive_stream_responses(stream, func) do
    {:ok, ex_stream} = GRPC.Stub.recv(stream)
    # receive result
    Task.async(fn ->
      ex_stream
      |> Stream.each(&func.(&1))
      # code will be blocked until the stream end
      |> Stream.run()
    end)

    :ok
  end
end
