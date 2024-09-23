defmodule ExGoogleSTT.TranscriptionServer do
  @moduledoc """
  A Server to handle transcription requests.
  """
  use GenServer

  alias ExGoogleSTT.Grpc.SpeechClient, as: GrpcSpeechClient
  alias ExGoogleSTT.{Error, SpeechEvent, Transcript}

  alias Google.Cloud.Speech.V2.{
    RecognitionConfig,
    StreamingRecognitionConfig,
    StreamingRecognizeRequest,
    StreamingRecognizeResponse,
    StreamingRecognitionResult
  }

  @grpc_dealine 5 * 60 * 1000
  @restart_stream_timeout 3 * 60 * 1000
  @smaller_restart_stream_timeout 10_000

  # ================== APIs ==================
  @doc """
  Starts a transcription server.
  The basic usage is to start the server with the config you want. It is then kept in state and can be used to send audio requests later on.

  ## Examples

      iex> TranscriptionServer.start_link()
      {:ok, #PID<0.123.0>}

  ## Options
    These options are all optional. The recognizer should be the main point of configuration.


    - target - a pid to send the results to, defaults to self()
    - language_codes - a list of language codes to use for recognition, defaults to ["en-US"]
    - enable_automatic_punctuation - a boolean to enable automatic punctuation, defaults to true
    - interim_results - a boolean to enable interim results, defaults to false
    - recognizer - a string representing the recognizer to use, defaults to use the recognizer from the config
    - model - a string representing the model to use, defaults to "latest_long". Be careful, changing to 'short' may have unintended consequences
    - split_by_chunk - boolean - whether to split the audio into chunks or not, defaults to true. Used to avoid hitting the Google STT limit
    - infinite - boolean - the deadline for the GRPC stream is set to 5 minutes by default. If you want to keep the stream open indefinitely, set this to true and ExGoogleSTT will handle the stream timeout for you.
  """
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc """
  That's the main entrypoint for processing audio.
  It will start a stream, if it's not already started and send the audio to it.
  It will also send the config if it's not already sent.
  """
  @spec process_audio(pid(), binary()) :: :ok
  def process_audio(transcription_server_pid, audio_data) do
    with {:ok, _speech_client} <- get_or_start_speech_client(transcription_server_pid) do
      send_audio_data(transcription_server_pid, audio_data)
    end
  end

  @spec get_or_start_speech_client(pid()) :: {:ok, pid()}
  defp get_or_start_speech_client(transcription_server_pid) do
    speech_client =
      GenServer.call(transcription_server_pid, {:get_or_start_speech_client}, :infinity)

    {:ok, speech_client}
  end

  def end_stream(transcription_server_pid),
    do: GenServer.call(transcription_server_pid, :end_stream)

  def cancel_stream(transcription_server_pid),
    do: GenServer.call(transcription_server_pid, :cancel_stream)

  # ================== GenServer ==================

  @impl GenServer
  def init(opts_map) do
    config_request = build_config_request(opts_map)
    recognizer = Map.get(opts_map, :recognizer, default_recognizer())
    split_by_chunk = Map.get(opts_map, :split_by_chunk, true)
    target = Map.get(opts_map, :target, self())
    infinite = Map.get(opts_map, :infinite, false)

    # This ensures the transcriptions server is killed if the caller dies
    Process.monitor(target)

    if infinite, do: schedule_restart_stream(@restart_stream_timeout)

    {:ok,
     %{
       config_request: config_request,
       recognizer: recognizer,
       speech_client: nil,
       split_by_chunk: split_by_chunk,
       stream_state: :closed,
       target: target,
       deadline: System.monotonic_time(:millisecond) + @grpc_dealine
     }}
  end

  def schedule_restart_stream(interval),
    do: Process.send_after(self(), :restart_stream, interval)

  @impl GenServer
  def handle_call({:get_or_start_speech_client}, _from, state) do
    if state.stream_state == :closed or speech_client_state(state.speech_client) == :closed do
      {:ok, new_state} = restart_speech_client(state)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_call({:send_audio_request, audio_data}, _from, state) do
    audio_data
    |> maybe_split_audio(state.split_by_chunk)
    |> Enum.each(fn audio_chunk ->
      audio_request = build_audio_request(audio_chunk, state.recognizer)
      send_request(state.speech_client, audio_request)
    end)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:end_stream, _from, state) do
    case state.stream_state do
      :open ->
        :ok = GrpcSpeechClient.end_stream(state.speech_client)
        {:reply, :ok, %{state | stream_state: :closed}}

      :closed ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  # The difference between cancel and end is that this one kills the speech client immediately
  def handle_call(:cancel_stream, _from, state) do
    case state.stream_state do
      :open ->
        :ok = GrpcSpeechClient.cancel_stream(state.speech_client)
        :ok = GrpcSpeechClient.stop(state.speech_client)
        {:reply, :ok, %{state | stream_state: :closed, speech_client: nil}}

      :closed ->
        {:reply, :ok, state}
    end
  end

  @impl GenServer
  # This ensures the transcriptions server is killed if the caller dies
  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{target: pid} = state) do
    {:stop, :normal, state}
  end

  # If audio data has not been received for the stream timeout, an `aborted`
  # error is returned. Afterwards, no requests will be processed so the stream
  # has to be closed. A new `process_audio` request would restart the stream.
  def handle_info({:error, %GRPC.RPCError{status: 10}}, %{target: target} = state) do
    if speech_client_state(state.speech_client) == :open do
      GrpcSpeechClient.stop(state.speech_client)
    end

    send(target, {:stt_event, :stream_timeout})
    {:noreply, %{state | stream_state: :closed, speech_client: nil}}
  end

  def handle_info(recognize_response, %{target: target} = state) do
    entries = parse_response(recognize_response)

    for entry <- entries do
      send(target, entry)
    end

    {:noreply, state}
  end

  def handle_info(:restart_stream, %{stream_state: stream_state} = state) do
    # Only restart the stream if it's closed, i.e. there's no active stream going on, otherwise it'll cut the transcription midway
    # If the 3 minute mark is reached, we'll try again in smaller intervals
    # If the deadline is close to being reached, we'll force a restart to avoid breaking the stream
    now = System.monotonic_time(:millisecond)

    if stream_state == :closed or now > @grpc_dealine - @smaller_restart_stream_timeout * 2 do
      {:ok, new_state} = restart_speech_client(state)
      schedule_restart_stream(@restart_stream_timeout)
      {:noreply, new_state}
    else
      schedule_restart_stream(@smaller_restart_stream_timeout)
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  # ================== GenServer Helpers ==================

  defp build_config_request(opts_map) do
    stream_recognition_cfg = build_str_recognition_config(opts_map)
    recognizer = Map.get(opts_map, :recognizer, default_recognizer())

    %StreamingRecognizeRequest{
      streaming_request: {:streaming_config, stream_recognition_cfg},
      recognizer: recognizer
    }
  end

  defp build_str_recognition_config(opts_map) do
    # The recognizer is the main point of configuration, but we can override some configurations.
    # Ideally, apart from the language, we should not need to override anything
    recognition_config =
      %RecognitionConfig{}
      |> cast_decoding_config(opts_map)
      |> cast_model(opts_map)
      |> cast_language_codes(opts_map)
      |> cast_automatic_punctuation(opts_map)

    # ABSOLUTELY NECESSARY FOR INFINITE STREAMING, because it lets us receive a response immediately after the stream is opened
    activity_events = true

    interim_results = Map.get(opts_map, :interim_results, false)

    %StreamingRecognitionConfig{
      streaming_features: %{
        enable_voice_activity_events: activity_events,
        interim_results: interim_results
      }
    }
    |> cast_recognition_config(recognition_config)
  end

  # do not send the config if empty
  defp cast_recognition_config(stream_rec_config, recognition_config)
       when recognition_config == %RecognitionConfig{},
       do: stream_rec_config

  defp cast_recognition_config(stream_rec_config, recognition_config) do
    stream_rec_config
    |> Map.put(:config, recognition_config)
  end

  defp cast_decoding_config(recognition_config, %{auto_decoding_config: auto_decoding_config}) do
    recognition_config
    |> Map.put(:decoding_config, {:auto_decoding_config, auto_decoding_config})
  end

  defp cast_decoding_config(recognition_config, %{
         explicit_decoding_config: explicit_decoding_config
       }) do
    recognition_config
    |> Map.put(:decoding_config, {:explicit_decoding_config, explicit_decoding_config})
  end

  defp cast_decoding_config(recognition_config, _), do: recognition_config

  defp cast_model(recognition_config, %{model: model}) do
    recognition_config
    |> Map.put(:model, model)
  end

  defp cast_model(recognition_config, _) do
    recognition_config
    |> Map.put(:model, nil)
  end

  defp cast_language_codes(recognition_config, %{language_codes: language_codes}) do
    recognition_config
    |> Map.put(:language_codes, language_codes)
  end

  defp cast_language_codes(recognition_config, _), do: recognition_config

  defp cast_automatic_punctuation(
         recognition_config,
         %{enable_automatic_punctuation: enable_automatic_punctuation}
       ) do
    recognition_config
    |> Map.put(:features, %{enable_automatic_punctuation: enable_automatic_punctuation})
  end

  defp cast_automatic_punctuation(recognition_config, _), do: recognition_config

  defp default_recognizer, do: Application.get_env(:ex_google_stt, :recognizer)

  defp build_audio_request(audio_data, recognizer) do
    %StreamingRecognizeRequest{streaming_request: {:audio, audio_data}, recognizer: recognizer}
  end

  @google_stt_limit 25_600
  defp maybe_split_audio(audio_data, true), do: chunk_every(audio_data, @google_stt_limit)
  defp maybe_split_audio(audio_data, false), do: [audio_data]

  def chunk_every(binary, chunk_size) do
    if byte_size(binary) <= chunk_size do
      [binary]
    else
      {result, _} = chunk_every_rem(binary, chunk_size)
      result
    end
  end

  @spec chunk_every_rem(binary, chunk_size :: pos_integer) :: {[binary], remainder :: binary}
  def chunk_every_rem(binary, chunk_size) do
    do_chunk_every_rem(binary, chunk_size)
  end

  defp do_chunk_every_rem(binary, chunk_size, acc \\ []) do
    case binary do
      <<chunk::binary-size(chunk_size)>> <> rest ->
        do_chunk_every_rem(rest, chunk_size, [chunk | acc])

      rest ->
        {acc |> Enum.reverse(), rest}
    end
  end

  defp restart_speech_client(state) do
    maybe_kill_speech_client(state.speech_client)
    {:ok, speech_client} = GrpcSpeechClient.start_link()
    :ok = send_config(speech_client, state.config_request)

    changed_attrs = %{
      speech_client: speech_client,
      stream_state: :open,
      deadline: System.monotonic_time(:millisecond) + @grpc_dealine
    }

    new_state = Map.merge(state, changed_attrs)

    {:ok, new_state}
  end

  defp maybe_kill_speech_client(speech_client) do
    if speech_client_state(speech_client) == :open,
      do: GrpcSpeechClient.stop(speech_client),
      else: :ok
  end

  defp speech_client_state(nil), do: :closed

  defp speech_client_state(speech_client) do
    case Process.alive?(speech_client) do
      true -> :open
      false -> :closed
    end
  end

  @spec send_config(pid(), StreamingRecognizeRequest.t()) :: :ok
  defp send_config(speech_client, cfg_request), do: send_request(speech_client, cfg_request)

  @spec send_request(pid(), StreamingRecognizeRequest.t()) :: :ok
  defp send_request(speech_client, request) do
    GrpcSpeechClient.send_request(speech_client, request)
  end

  defp send_audio_data(transcription_server_pid, audio_data) do
    GenServer.call(transcription_server_pid, {:send_audio_request, audio_data}, :infinity)
  end

  defp parse_response(%StreamingRecognizeResponse{results: results}) when results != [] do
    parse_results(results)
  end

  defp parse_response(%StreamingRecognizeResponse{speech_event_type: event_type}),
    do: [{:stt_event, %SpeechEvent{event: event_type}}]

  defp parse_response({:error, %GRPC.RPCError{status: status, message: message}}),
    do: [{:stt_event, %Error{status: status, message: message}}]

  # Ignoring the noise for now
  defp parse_response(_), do: []

  defp parse_results(results) do
    results_content = Enum.map_join(results, "", &parse_result(&1))
    is_final = Enum.any?(results, & &1.is_final)

    [{:stt_event, %Transcript{content: results_content, is_final: is_final}}]
  end

  defp parse_result(%StreamingRecognitionResult{alternatives: [alternative]}),
    do: alternative.transcript

  # Seeing this in the logs. Not sure what it is
  defp parse_result(%StreamingRecognitionResult{alternatives: []}),
    do: ""
end
