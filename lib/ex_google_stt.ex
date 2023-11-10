defmodule ExGoogleSTT do
  @moduledoc """
  The API layer for Google Cloud Speech-to-Text API.
  """

  alias ExGoogleSTT.StreamingServer.DynamicSupervisor, as: StreamingServerSupervisor
  alias ExGoogleSTT.StreamingServer

  alias Google.Cloud.Speech.V2.{
    RecognitionConfig,
    StreamingRecognitionConfig,
    StreamingRecognizeRequest,
    StreamingRecognizeResponse
  }

  def send_audio(target, audio_binary, configs \\ []) when is_binary(audio_binary) do
    with stream_server_pid <- get_or_start_stream(target) do
      build_request(audio_binary)
    end
  end

  defp get_or_start_stream(target \\ self(), configs \\ []) do
    case StreamingServerSupervisor.get_streaming_server(target) do
      {:ok, streaming_server_pid} ->
        streaming_server_pid

      {:error, :not_found} ->
        start_stream(target, configs)
    end
  end

  defp start_stream(target, configs) do
    with {:ok, streaming_server_pid} <- StreamingServerSupervisor.start_stream_server(target) do
      config_request = build_config_request(configs)
      StreamingServer.send_request(streaming_server_pid, config_request)
    end
  end

  defp build_config_request(configs) do
    recognition_cfg = build_recognition_config(configs)
    recognizer = Keyword.get(configs, :recognizer, default_recognizer())

    %StreamingRecognizeRequest{
      streaming_request:
        {:streaming_config, %StreamingRecognitionConfig{config: recognition_cfg}},
      recognizer: recognizer
    }
  end

  defp build_recognition_config(configs) do
    decoding_config = build_decoding_config(configs)
    model = Keyword.get(configs, :model, "long")
    language_codes = Keyword.get(configs, :language_codes, ["en-GB"])
    features = Keyword.get(configs, :features, %{enable_automatic_punctuation: true})

    %RecognitionConfig{
      decoding_config: decoding_config,
      model: model,
      language_codes: language_codes,
      features: features
    }
  end

  defp build_features_config(configs) do
    features = Keyword.get(configs, :features, %{})

    unless is_map(features) do
      raise "Features must be a map"
    end

    Map.merge(default_features(), features)
  end

  defp build_decoding_config(configs),
    do: Keyword.get(configs, :decoding_config, default_decoding_config())

  defp default_recognizer, do: Application.get_env(:ex_google_stt, :recognizer)

  defp default_decoding_config,
    do: {:auto_decoding_config, %Google.Cloud.Speech.V2.AutoDetectDecodingConfig{}}

  defp default_features, do: %{enable_automatic_punctuation: true}
end
