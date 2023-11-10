defmodule ExGoogleSTT.StreamingServer do
  @moduledoc """
  A client process for Streaming API.

  Once a client is started, it establishes a connection to the Streaming API,
  gets ready to send requests to the API and forwards incoming responses to a set process.

  ## Requests

  The requests can be sent using `send_request/3`. Each request should be a
  `t:Google.Cloud.Speech.V2.StreamingRecognizeRequest.t/0` struct created using
  `Google.Cloud.Speech.V2.StreamingRecognizeRequest.new/1` accepting keyword with struct fields.
  This is an auto-generated module, so check out [this notice](readme.html#auto-generated-modules) and
  [API reference](https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.V2#google.cloud.speech.V2.StreamingRecognizeRequest)

  ## Responses

  The client sends responses from API via messages to the target (by default it is the process that spawned client).
  Each message is a struct `t:Google.Cloud.Speech.V2.StreamingRecognizeResponse.t/0` or a tuple with pid of sender and the same struct. Message format is controlled by `include_sender` option of a client.

  ## Usage

  1. Start the client
  1. Send request with `Google.Cloud.Speech.V2.StreamingRecognitionConfig`
  1. Send request(s) with `Google.Cloud.Speech.V2.RecognitionAudio` containing audio data
  1. (async) Receive messages conatining `Google.Cloud.Speech.V2.StreamingRecognizeResponse`
  1. Send final `Google.Cloud.Speech.V2.RecognitionAudio` with option `end_stream: true`
     or call `end_stream/1` after final audio chunk has been sent.
  1. Stop the client after receiving all results

  See [README](readme.html) for code example
  """

  use GenServer

  alias Google.Cloud.Speech.V2.RecognitionConfig
  alias ExGoogleSTT.GrpcSpeechClient

  alias Google.Cloud.Speech.V2.{
    RecognitionConfig,
    StreamingRecognitionConfig,
    StreamingRecognizeRequest,
    StreamingRecognizeResponse
  }

  @typedoc "Format of messages sent by the client to the target"
  @type message :: StreamingRecognizeResponse.t() | {pid(), StreamingRecognizeResponse.t()}

  @doc """
  Starts a linked client process.

  Possible options are:
  - `target` - A pid of a process that will receive recognition results. Defaults to `self()`.
  """
  @spec start_link(target :: pid()) :: {:ok, pid} | {:error, any()}
  def start_link(target: target) do
    GenServer.start_link(__MODULE__, %{target: target})
  end

  # raise_on_missing_stream_config(options)
  # defp maybe_raise_on_missing_config(%{
  #        streaming_config: %StreamingRecognitionConfig{
  #          config: %RecognitionConfig{} = recognition_config
  #        }
  #      }) do
  #   all_there? =
  #     Enum.all?(
  #       [:decoding_config, :model, :language_codes, :features],
  #       is_map_key(recognition_config)
  #     )

  #   all_there? || raise "Missing required fields in recognition config"
  # end

  # defp maybe_raise_on_missing_config(_), do: nil

  @doc """
  Stops a client process.
  """
  @spec stop(client :: pid()) :: :ok
  defdelegate stop(pid), to: GenServer

  @doc """
  Sends a request to the API. If option `end_stream: true` is passed,
  closes a client-side gRPC stream.
  """
  @spec send_request(client :: pid(), StreamingRecognizeRequest.t(), Keyword.t()) :: :ok
  def send_request(pid, request, opts \\ []) do
    GenServer.cast(pid, {:send_requests, [request], opts})
    :ok
  end

  @doc """
  Sends a list of requests to the API. If option `end_stream: true` is passed,
  closes a client-side gRPC stream.
  """
  @spec send_requests(client :: pid(), [StreamingRecognizeRequest.t()], Keyword.t()) :: :ok
  def send_requests(pid, request, opts \\ []) do
    GenServer.cast(pid, {:send_requests, request, opts})
    :ok
  end

  @doc """
  Closes a client-side gRPC stream.
  """
  @spec end_stream(client :: pid()) :: :ok
  def end_stream(pid) do
    GenServer.cast(pid, :end_stream)
    :ok
  end

  @impl true
  def init(%{target: target} = options) do
    with {:ok, grpc_client} <- GrpcSpeechClient.start_link() do
      Process.monitor(target)
      {:ok, %{options | grpc_client: grpc_client}}
    end
  end

  @impl true
  def handle_cast({:send_requests, requests, opts}, state) do
    :ok = state.conn |> GrpcSpeechClient.send_requests(requests, opts)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:end_stream, state) do
    :ok = state.conn |> GrpcSpeechClient.end_stream()
    {:noreply, state}
  end

  @impl true
  def handle_info(%StreamingRecognizeResponse{} = response, state) do
    if state.include_sender do
      send(state.target, {self(), response})
    else
      send(state.target, response)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{target: pid} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    state.conn |> GrpcSpeechClient.stop()
  end
end
