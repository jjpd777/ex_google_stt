defmodule ExGoogleSTT.TranscriptionServerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias ExGoogleSTT.{Fixtures, Transcript, TranscriptionServer}

  alias Google.Cloud.Speech.V2.StreamingRecognizeResponse

  # ===================== GenServer Tests =====================

  describe "Monitor" do
    test "stream server is closed if caller is shut down" do
      target = self()

      {:ok, client_pid} =
        Task.start(fn ->
          {:ok, server} = TranscriptionServer.start_link(target: self())
          send(target, {:server, server})
        end)

      assert_receive {:server, server}, 5000

      Process.monitor(server)
      Process.exit(client_pid, :normal)
      assert_receive {:DOWN, _, :process, ^server, :noproc}, 5000
    end
  end

  describe "process_audio/2" do
    test "correcly starts a stream and process the audio" do
      recognizer = Fixtures.recognizer()
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target, recognizer: recognizer)
      audio_data = Fixtures.small_audio_bytes()
      TranscriptionServer.process_audio(server_pid, audio_data)

      assert_receive {:response,
                      %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:response, %Transcript{content: "Hello."}}, 5000
    end

    test "starts a new stream if the previous one is closed and process the audio, when forcing the stream to end" do
      recognizer = Fixtures.recognizer()
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target, recognizer: recognizer)
      audio_data = Fixtures.audio_bytes()

      for _ <- 1..3 do
        TranscriptionServer.process_audio(server_pid, audio_data)

        assert_receive {:response,
                        %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                       5000

        TranscriptionServer.end_stream(server_pid)
        assert_receive {:response, %Transcript{content: "Advent"}}, 5000
      end
    end

    test "starts a new stream if the previous one is closed and process the audio, when stream ended by itself" do
      recognizer = Fixtures.recognizer()
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target, recognizer: recognizer)
      audio_data = Fixtures.small_audio_bytes()

      for _ <- 1..3 do
        TranscriptionServer.process_audio(server_pid, audio_data)

        assert_receive {:response,
                        %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                       5000

        TranscriptionServer.end_stream(server_pid)
        assert_receive {:response, %Transcript{content: "Hello."}}, 5000
      end
    end

    test "Keeps processing the requests in the same stream if not ended" do
      recognizer = Fixtures.recognizer()
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target, recognizer: recognizer)
      audio_data = Fixtures.audio_bytes()

      for _ <- 1..3 do
        TranscriptionServer.process_audio(server_pid, audio_data)
      end

      TranscriptionServer.end_stream(server_pid)

      assert_receive {:response,
                      %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:response,
                      %ExGoogleSTT.Transcript{content: "Adventure will Adventure will Advent."}},
                     5000
    end

    test "works as expected with interim results" do
      recognizer = Fixtures.recognizer()

      {:ok, server_pid} =
        TranscriptionServer.start_link(
          target: self(),
          recognizer: recognizer,
          interim_results: true
        )

      Fixtures.chunked_audio_bytes()
      |> Enum.each(&TranscriptionServer.process_audio(server_pid, &1))

      assert_receive {:response,
                      %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      capture_and_assert_interim_transcripts()
    end

    defp capture_and_assert_interim_transcripts(interim_transcripts \\ []) do
      assert_receive {:response, %Transcript{} = transcript}, 5000
      interim_transcripts = interim_transcripts ++ [transcript]

      if transcript.is_final do
        interim_transcripts
        |> Enum.map(&(&1.content |> String.trim() |> String.downcase()))
        |> assert_interim_transcripts()

        # Final one
        transcript
      else
        capture_and_assert_interim_transcripts(interim_transcripts)
      end
    end

    # This checks for 88% accuracy, as the interim results are not deterministic
    defp assert_interim_transcripts(interim_transcripts) do
      expected_interims =
        Fixtures.interim_results()
        |> Enum.map(&(String.trim(&1) |> String.downcase()))

      matches =
        interim_transcripts
        |> Enum.reduce(0, fn
          interim_transcript, matches ->
            if interim_transcript in expected_interims,
              do: matches + 1,
              else: matches
        end)

      assert matches / length(expected_interims) >= 0.88
    end

    test "returns an error if the audio is too large" do
      recognizer = Fixtures.recognizer()
      {:ok, server_pid} = TranscriptionServer.start_link(target: self(), recognizer: recognizer)
      audio_data = Fixtures.full_audio_bytes()

      TranscriptionServer.process_audio(server_pid, audio_data)

      assert_receive {:response,
                      %GRPC.RPCError{
                        message: "Audio chunk can be of a a maximum of 25600 bytes" <> _
                      }},
                     5000
    end

    test "Can process audio after an error" do
      recognizer = Fixtures.recognizer()
      {:ok, server_pid} = TranscriptionServer.start_link(target: self(), recognizer: recognizer)
      bad_audio = Fixtures.full_audio_bytes()
      good_audio = Fixtures.small_audio_bytes()

      TranscriptionServer.process_audio(server_pid, bad_audio)

      assert_receive {:response,
                      %GRPC.RPCError{
                        message: "Audio chunk can be of a a maximum of 25600 bytes" <> _
                      }},
                     5000

      TranscriptionServer.process_audio(server_pid, good_audio)

      assert_receive {:response,
                      %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:response, %Transcript{content: "Hello."}}, 5000
    end
  end

  # Careful when running these, since they'll cost you money
  describe "Load Tests" do
    @describetag :load_test
    test "can open 50 sessions at the same time without issue" do
      number_of_sessions = 50

      target = self()
      audio_data = Fixtures.audio_bytes()

      tasks =
        for _ <- 1..number_of_sessions do
          Task.async(fn ->
            recognizer = Fixtures.recognizer()

            {:ok, server_pid} =
              TranscriptionServer.start_link(target: target, recognizer: recognizer)

            TranscriptionServer.process_audio(server_pid, audio_data)
            TranscriptionServer.end_stream(server_pid)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      for _ <- 1..number_of_sessions do
        assert_receive {:response,
                        %StreamingRecognizeResponse{speech_event_type: :SPEECH_ACTIVITY_BEGIN}},
                       5000

        assert_receive {:response, %Transcript{content: "Advent"}}, 5000
      end
    end
  end
end
