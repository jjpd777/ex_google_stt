defmodule ExGoogleSTT.TranscriptionServerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias ExGoogleSTT.{Fixtures, TranscriptionServer}

  alias GRPC.Client.Stream

  alias Google.Cloud.Speech.V2.{
    StreamingRecognizeResponse,
    StreamingRecognitionResult,
    SpeechRecognitionAlternative
  }

  describe "send_config/3" do
    test "succesfully sends a config request to the Stream Client" do
      config_request = Fixtures.config_request()
      {:ok, stream} = TranscriptionServer.start_stream()
      assert {:ok, %Stream{}} = TranscriptionServer.send_config(stream, config_request)
    end

    test "fails if sending a bad config" do
      config_request = Fixtures.bad_config_request()
      {:ok, stream} = TranscriptionServer.start_stream()

      assert_raise Protobuf.EncodeError, fn ->
        TranscriptionServer.send_config(stream, config_request)
      end
    end
  end

  describe "send_request/3" do
    test "succesfully sends a request to the Stream Client" do
      audio_request = Fixtures.audio_request()
      {:ok, stream} = TranscriptionServer.start_stream()
      assert {:ok, %Stream{}} = TranscriptionServer.send_request(stream, audio_request)
    end

    test "fails if sending a bad request" do
      audio_request = Fixtures.bad_audio_request()
      {:ok, stream} = TranscriptionServer.start_stream()

      assert_raise Protobuf.EncodeError, fn ->
        TranscriptionServer.send_request(stream, audio_request)
      end
    end
  end

  describe "receive_stream_responses/2" do
    test "successfully performs the function sent on every response" do
      config_request = Fixtures.config_request()
      audio_request = Fixtures.audio_request()

      {:ok, stream} = TranscriptionServer.start_stream()

      TranscriptionServer.send_config(stream, config_request)
      TranscriptionServer.send_request(stream, audio_request)

      target = self()

      func = fn response ->
        assert {:ok, %StreamingRecognizeResponse{} = recognize_response} = response
        send(target, {:response, recognize_response})
      end

      # ending the stream to receive the response. Usually not needed, but the audio does not end in silence
      TranscriptionServer.end_stream(stream)
      TranscriptionServer.receive_stream_responses(stream, func)

      assert_transcript("Advent", false)
    end
  end

  describe "Transcription Tests - " do
    setup do
      {:ok, stream} = TranscriptionServer.start_stream()
      config_request = Fixtures.config_request()
      {:ok, stream} = TranscriptionServer.send_config(stream, config_request)

      target = self()

      func = fn response ->
        assert {:ok, %StreamingRecognizeResponse{} = recognize_response} = response
        send(target, {:response, recognize_response})
      end

      {:ok, %{stream: stream, func: func}}
    end

    test "successfully transcribes data sent in chunks", %{stream: stream, func: func} do
      audio_chunks = Fixtures.chunked_audio_bytes()

      Enum.map(audio_chunks, fn data ->
        TranscriptionServer.send_request(stream, Fixtures.audio_request(data))
      end)

      TranscriptionServer.receive_stream_responses(stream, func)

      assert_transcript(
        "Adventure 1 a scandal in Bohemia from the Adventures of Sherlock Holmes by Sir Arthur Conan Doyle"
      )
    end

    test "successfully transcribes data sent in chunks, even if requests are sent after we start receiving response",
         %{func: func} do
      {:ok, stream} = TranscriptionServer.start_stream()
      config_request = Fixtures.config_request(interim_results: false)
      {:ok, stream} = TranscriptionServer.send_config(stream, config_request)

      audio_chunks = Fixtures.chunked_audio_bytes()
      {first_chunk, rest_of_chunks} = Enum.split(audio_chunks, 2)
      {second_chunk, rest_of_chunks} = Enum.split(rest_of_chunks, 2)

      # send first 2 requests
      Enum.each(first_chunk, fn data ->
        TranscriptionServer.send_request(stream, Fixtures.audio_request(data))
      end)

      # Now ask for the responses
      TranscriptionServer.receive_stream_responses(stream, func)

      # send the second chunk
      Enum.each(second_chunk, fn data ->
        TranscriptionServer.send_request(stream, Fixtures.audio_request(data))
      end)

      # send the rest of the chunks
      Enum.each(rest_of_chunks, fn data ->
        TranscriptionServer.send_request(stream, Fixtures.audio_request(data))
      end)

      assert_transcript(
        "Adventure 1 a scandal in Bohemia from the Adventures of Sherlock Holmes by Sir Arthur Conan Doyle"
      )
    end

    test "fails if Audio data is larger than 25_600 bytes", %{stream: stream} do
      target = self()

      func = fn response ->
        assert {:error,
                %GRPC.RPCError{
                  status: 3,
                  message: "Audio chunk can be of a a maximum of 25600 bytes" <> _
                }} = response

        send(target, {:response, response})
      end

      audio_request = Fixtures.audio_request(Fixtures.full_audio_bytes())
      TranscriptionServer.send_request(stream, audio_request)
      TranscriptionServer.receive_stream_responses(stream, func)
      assert_receive {:response, _response}, 1000
    end
  end

  defp assert_transcript(expected_transcript, end_event \\ true) do
    assert_receive {:response,
                    %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                   1000

    if end_event do
      assert_receive {:response,
                      %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_END}},
                     1000
    end

    assert_receive {:response, %StreamingRecognizeResponse{results: results}}, 5000
    assert [%StreamingRecognitionResult{alternatives: alternative}] = results
    assert [%SpeechRecognitionAlternative{transcript: transcript}] = alternative
    assert String.downcase(transcript) == String.downcase(expected_transcript)
  end
end
