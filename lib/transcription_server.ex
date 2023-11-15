defmodule ExGoogleSTT.TranscriptionServer do
  @moduledoc """
  A Server to handle transcription requests.
  """
  use GenServer

  alias ExGoogleSTT.Grpc.StreamClient
  alias ExGoogleSTT.Transcript

  alias Google.Cloud.Speech.V2.{
    AutoDetectDecodingConfig,
    RecognitionConfig,
    StreamingRecognitionConfig,
    StreamingRecognizeRequest,
    StreamingRecognizeResponse,
    StreamingRecognitionResult
  }

  alias GRPC.Stub, as: GrpcStub
  alias GRPC.Client.Stream, as: GrpcStream

  @default_model "latest_long"
  @default_language_codes ["en-US"]

  @doc """
  Starts a transcription server.
  The basic usage is to start the server with the config you want. It is then kept in state and can be used to send audio requests later on.

  ## Examples

      iex> TranscriptionServer.start_link()
      {:ok, #PID<0.123.0>}

  ## Options
    - target - a pid to send the results to, defaults to self()
    - language_codes - a list of language codes to use for recognition, defaults to ["en-US"]
    - enable_automatic_punctuation - a boolean to enable automatic punctuation, defaults to true
    - interim_results - a boolean to enable interim results, defaults to false
    - recognizer - a string representing the recognizer to use, defaults to use the recognizer from the config
    - model - a string representing the model to use, defaults to "latest_long". Be careful, changing to 'short' may have unintended consequences
  """

  # ================== GenServer ==================
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, Map.new(opts), name: __MODULE__)
  end

  @impl GenServer
  def init(opts_map) do
    target = Map.get(opts_map, :target, self())
    config_request = build_config_request(opts_map)
    recognizer = Map.get(opts_map, :recognizer, default_recognizer())

    # This ensures the transcriptions server is killed if the caller dies
    Process.monitor(target)

    initial_stream_state = %{stream: nil, stream_status: :closed, first_request_sent: false}

    {:ok,
     %{
       target: target,
       recognizer: recognizer,
       config_request: config_request,
       stream_state: initial_stream_state
     }}
  end

  defp build_config_request(opts_map) do
    stream_recognition_cfg = build_str_recognition_config(opts_map)
    recognizer = Map.get(opts_map, :recognizer, default_recognizer())

    %StreamingRecognizeRequest{
      streaming_request: {:streaming_config, stream_recognition_cfg},
      recognizer: recognizer
    }
  end

  defp build_str_recognition_config(opts_map) do
    recognition_config = %RecognitionConfig{
      decoding_config: {:auto_decoding_config, %AutoDetectDecodingConfig{}},
      model: Map.get(opts_map, :model, @default_model),
      language_codes: Map.get(opts_map, :language_codes, @default_language_codes),
      features: %{
        enable_automatic_punctuation: Map.get(opts_map, :enable_automatic_punctuation, true)
      }
    }

    # ABSOLUTELY NECESSARY FOR INFINITE STREAMING, because it lets us receive a response immediately after the stream is opened
    activity_events = true

    interim_results = Map.get(opts_map, :interim_results, false)

    %StreamingRecognitionConfig{
      config: recognition_config,
      streaming_features: %{
        enable_voice_activity_events: activity_events,
        interim_results: interim_results
      }
    }
  end

  defp default_recognizer, do: Application.get_env(:ex_google_stt, :recognizer)

  @impl GenServer
  # This ensures the transcriptions server is killed if the caller dies
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{target: pid} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _pid, :normal}, state) do
    # This means the stream closed
    new_stream_state = %{state.stream_state | stream_status: :closed}
    {:noreply, %{state | stream_state: new_stream_state}}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_call({:get_or_start_stream}, _from, %{stream_state: stream_state} = state) do
    stream_state =
      case stream_state.stream_status do
        :open ->
          stream_state

        _ ->
          {:ok, stream} = start_stream()
          {:ok, stream} = send_config(stream, state.config_request)
          %{stream: stream, stream_status: :open, first_request_sent: false}
      end

    {:reply, stream_state.stream, %{state | stream_state: stream_state}}
  end

  @impl GenServer
  def handle_call(
        {:send_audio_request, audio_data},
        _from,
        %{stream_state: %{stream: stream} = stream_state} = state
      ) do
    audio_request = build_audio_request(audio_data, state.recognizer)
    send_request(stream, audio_request)
    # Only the first request requires we start the response generator
    unless stream_state.first_request_sent do
      receive_stream_responses(stream, default_handling_func(state.target))
    end

    new_stream_state = %{state.stream_state | stream: stream, first_request_sent: true}
    {:reply, :ok, %{state | stream_state: new_stream_state}}
  end

  defp build_audio_request(audio_data, recognizer) do
    %StreamingRecognizeRequest{streaming_request: {:audio, audio_data}, recognizer: recognizer}
  end

  def default_handling_func(target) do
    fn recognize_response ->
      entries = parse_response(recognize_response)

      for entry <- entries do
        send(target, {:response, entry})
      end
    end
  end

  defp parse_response({:ok, %StreamingRecognizeResponse{results: results}}) when results != [] do
    parse_results(results)
  end

  defp parse_response({:ok, %StreamingRecognizeResponse{} = response}), do: [response]

  defp parse_response({:error, error}), do: [error]

  defp parse_results(results) do
    for result <- results do
      parse_result(result)
    end
  end

  defp parse_result(%StreamingRecognitionResult{alternatives: [alternative]} = result) do
    %Transcript{content: alternative.transcript, is_final: result.is_final}
  end

  # ================== GenServer Ends ==================

  # ================== API ==================

  @doc """
  That's the main entrypoint for processing audio.
  It will start a stream, if it's not already started and send the audio to it.
  It will also send the config if it's not already sent.
  """
  @spec process_audio(pid(), binary()) :: :ok
  def process_audio(transcription_server_pid, audio_data) do
    stream = get_or_start_stream(transcription_server_pid)
    send_audio_data(transcription_server_pid, audio_data)
  end

  def send_audio_data(transcription_server_pid, audio_data) do
    GenServer.call(transcription_server_pid, {:send_audio_request, audio_data})
  end

  @doc """
  Gets the stream from the state or starts a new one if it's not started yet
  """
  @spec get_or_start_stream(pid()) :: GrpcStream.t()
  def get_or_start_stream(transcription_server_pid) do
    GenServer.call(transcription_server_pid, {:get_or_start_stream})
  end

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
