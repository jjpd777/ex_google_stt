alias Google.Cloud.Speech.V1.{
  RecognitionConfig,
  StreamingRecognitionConfig,
  StreamingRecognizeRequest,
  StreamingRecognizeResponse
}

alias GCloud.SpeechAPI.Streaming.Client

cfg =
  RecognitionConfig.new(
    audio_channel_count: 1,
    encoding: :FLAC,
    language_code: "en-GB",
    sample_rate_hertz: 16000
  )

str_cfg =
  StreamingRecognitionConfig.new(
    config: cfg,
    interim_results: false
  )

str_cfg_req =
  StreamingRecognizeRequest.new(
    streaming_request: {:streaming_config, str_cfg}
  )

<<part_a::binary-size(48277), part_b::binary-size(44177),
  part_c::binary>> = File.read!("test/fixtures/sample.flac")

content_reqs =
  [part_a, part_b, part_c] |> Enum.map(fn data ->
    StreamingRecognizeRequest.new(
      streaming_request: {:audio_content, data}
    )
  end)

{:ok, client} = Client.start_link()
client |> Client.send_request(str_cfg_req)
dbg()
content_reqs |> Enum.each(fn stream_audio_req ->
  Client.send_request(
    client,
    stream_audio_req
  )
end)

Client.end_stream(client)

receive do
  %StreamingRecognizeResponse{results: results} ->
    IO.inspect(results)
end
