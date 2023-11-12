defmodule ExGoogleSTT.Fixtures do
  @moduledoc """
  Fixtures for testing.
  """

  alias Google.Cloud.Speech.V2.{
    StreamingRecognizeRequest,
    StreamingRecognitionConfig,
    RecognitionConfig
  }

  def interim_results do
    [
      "advent",
      "adventure",
      "adventure 1",
      "adventure",
      "1",
      "adventure",
      "one",
      "adventure",
      "1 a",
      "adventure",
      "1 a scand",
      "adventure",
      "1 a scandal",
      "adventure 1 a",
      "scandal",
      "adventure 1 a",
      "scandal in",
      "adventure 1 a scandal",
      "in",
      "adventure 1 a scandal",
      "in bo",
      "adventure 1 a scandal",
      "in boh",
      "adventure 1 a scandal",
      "in bohem",
      "adventure 1 a scandal",
      "in bohemia",
      "adventure 1 a scandal in",
      "bohemia",
      "adventure 1 a scandal in",
      "bohemia from",
      "adventure 1 a scandal in",
      "bohemia from the",
      "adventure 1 a scandal in bohemia",
      "from the",
      "adventure 1 a scandal in bohemia from",
      "the",
      "adventure 1 a scandal in bohemia from",
      "the advent",
      "adventure 1 a scandal in bohemia from the",
      "advent",
      "adventure 1 a scandal in bohemia from the",
      "adventures",
      "adventure 1 a scandal in bohemia from the",
      "adventures of",
      "adventure 1 a scandal in bohemia from the",
      "adventures of sh.",
      "adventure 1 a scandal in bohemia from the adventures",
      "of sher",
      "adventure 1 a scandal in bohemia from the adventures",
      "of sherlock",
      "adventure 1 a scandal in bohemia from the adventures of",
      "sherlock",
      "adventure 1 a scandal in bohemia from the adventures of",
      "sherlock hol",
      "adventure 1 a scandal in bohemia from the adventures of sherlock",
      "holmes",
      "adventure 1 a scandal in bohemia from the adventures of sherlock",
      "holmes by",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes",
      "by",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes",
      "by sir",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes",
      "by sir ar",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes",
      "by sir arth",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by",
      "sir arthur",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by",
      "sir arthur con",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by sir",
      "arthur conan",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by sir",
      "arthur conan do",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by sir arthur",
      "conan doyle",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by sir arthur conan",
      "doyle",
      "adventure 1 a scandal in bohemia from the adventures of sherlock holmes by sir arthur conan doyle"
    ]
  end

  def full_audio_bytes() do
    sherlock_with_silence = "./sherlock_with_silence.mp3" |> Path.expand(__DIR__)
    File.read!(sherlock_with_silence)
  end

  def chunked_audio_bytes() do
    sherlock_with_silence = "./sherlock_with_silence.mp3" |> Path.expand(__DIR__)

    <<part_a::binary-size(25_600), part_b::binary-size(25_600), part_c::binary-size(25_600),
      part_d::binary-size(25_600), part_e::binary-size(25_600), part_f::binary-size(25_600),
      part_g::binary-size(25_600), part_h::binary>> = File.read!(sherlock_with_silence)

    [part_a, part_b, part_c, part_d, part_e, part_f, part_g, part_h]
  end

  def audio_bytes() do
    sherlock_with_silence = "./sherlock_with_silence.mp3" |> Path.expand(__DIR__)
    <<chunk::binary-size(25_600), _rest::binary>> = File.read!(sherlock_with_silence)
    chunk
  end

  def recognition_config(opts \\ []) do
    interim_results = Keyword.get(opts, :interim_results, false)

    %RecognitionConfig{
      decoding_config:
        {:auto_decoding_config, %Google.Cloud.Speech.V2.AutoDetectDecodingConfig{}},
      model: "latest_long",
      language_codes: ["en-GB"],
      features: %{enable_automatic_punctuation: true, interim_results: interim_results}
    }
  end

  def streaming_recognition_config(opts \\ []) do
    %StreamingRecognitionConfig{
      config: recognition_config(opts),
      # ABSOLUTELY NECESSARY FOR INFINITE STREAMING
      streaming_features: %{enable_voice_activity_events: true}
    }
  end

  def recognizer do
    creds_json = Application.get_env(:goth, :json)
    Jason.decode!(creds_json)["project_id"]
    "projects/#{Jason.decode!(creds_json)["project_id"]}/locations/global/recognizers/_"
  end

  def config_request(opts \\ []) do
    %StreamingRecognizeRequest{
      streaming_request: {:streaming_config, streaming_recognition_config(opts)},
      recognizer: recognizer()
    }
  end

  def bad_config_request do
    %StreamingRecognizeRequest{
      streaming_request: {:streaming_config, :not_valid}
    }
  end

  def audio_request(data \\ nil) do
    data = data || audio_bytes()
    %StreamingRecognizeRequest{streaming_request: {:audio, data}, recognizer: recognizer()}
  end

  def bad_audio_request do
    %StreamingRecognizeRequest{streaming_request: {:audio, :not_valid}}
  end
end
