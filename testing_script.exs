alias ExGoogleSTT.GrpcSpeechClient.Connection
alias Google.Cloud.Speech.V2.Speech.Stub, as: SpeechStub
alias Google.Cloud.Speech.V2.{
  RecognitionConfig,
  SpeechRecognitionAlternative,
  StreamingRecognitionConfig,
  StreamingRecognitionResult,
  StreamingRecognizeRequest,
  StreamingRecognizeResponse
}

alias ExGoogleSTT.StreamingServer
alias ExGoogleSTT.Fixtures

recognition_cfg = %RecognitionConfig{
  decoding_config: {:auto_decoding_config, %Google.Cloud.Speech.V2.AutoDetectDecodingConfig{}},
  model: "latest_long",
  language_codes: ["en-GB"],
  features: %{enable_automatic_punctuation: true}
}
creds_json = Application.compile_env(:goth, :json)
Jason.decode!(creds_json)["project_id"]

recognizer = "projects/#{Jason.decode!(creds_json)["project_id"]}/locations/global/recognizers/_"

str_cfg = %StreamingRecognitionConfig{
  config: recognition_cfg,
  streaming_features: %{enable_voice_activity_events: true, interim_results: true}
}

str_cfg_req = %StreamingRecognizeRequest{
  streaming_request: {:streaming_config, str_cfg},
  recognizer: recognizer
}

{:ok, channel} = Connection.connect()
request_opts = Connection.request_opts()
stream = SpeechStub.streaming_recognize(channel, request_opts)
# sending config
GRPC.Stub.send_request(stream, str_cfg_req)
# prepare audio requests
content_reqs =
  Fixtures.chunked_audio_bytes()
  |> Enum.map(fn data ->
    %StreamingRecognizeRequest{streaming_request: {:audio, data}, recognizer: recognizer}
  end)


  # send first request
  GRPC.Stub.send_request(stream, Enum.at(content_reqs, 0))
  {:ok, ex_stream} = GRPC.Stub.recv(stream)

# send rest of requests
Enum.drop(content_reqs, 1)
|> Enum.each(fn req ->
  GRPC.Stub.send_request(stream, req)
end)

# receive result
Task.async(fn ->
  ex_stream
  |> Stream.each(&IO.inspect/1)
  |> Stream.run() # code will be blocked until the stream end
end)


dbg()
