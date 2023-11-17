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

alias ExGoogleSTT.TranscriptionServer

creds_json = Application.compile_env(:goth, :json)
Jason.decode!(creds_json)["project_id"]

recognizer = "projects/#{Jason.decode!(creds_json)["project_id"]}/locations/global/recognizers/_"

{:ok, transcription_server} = TranscriptionServer.start_link(target: self(), recognizer: recognizer, interim_results: false)

# speech_binary = File.read!("./test/support/fixtures/audio.mp3")

# speech_binary = Fixtures.audio_bytes()
# speech_binary = File.read!("./test/support/fixtures/audio.mp3")
# stream = TranscriptionServer.process_audio(transcription_server, speech_binary)
# stream = TranscriptionServer.process_audio(transcription_server, Fixtures.audio_bytes())
Fixtures.chunked_audio_bytes()
|> Enum.each(fn data ->
  TranscriptionServer.process_audio(transcription_server, data)
end)

# TranscriptionServer.end_stream(stream)

# receive do
#   something -> nil
# end

receive do
  something -> dbg()
end
