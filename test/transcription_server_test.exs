defmodule ExGoogleSTT.TranscriptionServerTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias ExGoogleSTT.{Error, Fixtures, SpeechEvent, Transcript, TranscriptionServer}

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
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target)
      audio_data = Fixtures.small_audio_bytes()
      TranscriptionServer.process_audio(server_pid, audio_data)

      assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:stt_event, %Transcript{content: "Hello."}}, 5000
    end

    test "starts a new stream if the previous one is closed and process the audio, when forcing the stream to end" do
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target)
      audio_data = Fixtures.audio_bytes()

      for _ <- 1..3 do
        TranscriptionServer.process_audio(server_pid, audio_data)

        assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                       5000

        TranscriptionServer.end_stream(server_pid)
        assert_receive {:stt_event, %Transcript{content: "Advent"}}, 5000
      end
    end

    test "starts a new stream if the previous one is closed and process the audio, when stream ended by itself" do
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target)
      audio_data = Fixtures.small_audio_bytes()

      for _ <- 1..3 do
        TranscriptionServer.process_audio(server_pid, audio_data)

        assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                       5000

        TranscriptionServer.end_stream(server_pid)
        assert_receive {:stt_event, %Transcript{content: "Hello."}}, 5000
      end
    end

    test "does not process the audio if the stream is canceled" do
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target)
      audio_data = Fixtures.small_audio_bytes()
      TranscriptionServer.process_audio(server_pid, audio_data)
      TranscriptionServer.cancel_stream(server_pid)
      refute_receive {:stt_event, %Transcript{content: "Hello."}}, 500
    end

    test "starts a new stream if the previous one is canceled and processes the new ones" do
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target)

      audio_data = Fixtures.small_audio_bytes()
      TranscriptionServer.process_audio(server_pid, audio_data)
      TranscriptionServer.cancel_stream(server_pid)
      refute_receive {:stt_event, %Transcript{content: "Hello."}}, 500

      TranscriptionServer.process_audio(server_pid, audio_data)

      assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:stt_event, %Transcript{content: "Hello."}}, 5000
    end

    test "Keeps processing the requests in the same stream if not ended" do
      target = self()
      {:ok, server_pid} = TranscriptionServer.start_link(target: target)
      audio_data = Fixtures.audio_bytes()

      for _ <- 1..3 do
        TranscriptionServer.process_audio(server_pid, audio_data)
      end

      TranscriptionServer.end_stream(server_pid)

      assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:stt_event,
                      %ExGoogleSTT.Transcript{content: "Adventure will Adventure will Advent."}},
                     5000
    end

    test "works as expected with interim results" do
      {:ok, server_pid} =
        TranscriptionServer.start_link(
          target: self(),
          interim_results: true
        )

      Fixtures.chunked_audio_bytes()
      |> Enum.each(&TranscriptionServer.process_audio(server_pid, &1))

      assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      capture_and_assert_interim_transcripts()
    end

    defp capture_and_assert_interim_transcripts(interim_transcripts \\ []) do
      assert_receive {:stt_event, %Transcript{} = transcript}, 5000
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

    test "returns an error if the audio is too large, when split_by_chunk is off" do
      {:ok, server_pid} = TranscriptionServer.start_link(target: self(), split_by_chunk: false)
      audio_data = Fixtures.full_audio_bytes()

      TranscriptionServer.process_audio(server_pid, audio_data)

      assert_receive {:stt_event,
                      %Error{
                        message: "Audio chunk can be of a a maximum of 25600 bytes" <> _
                      }},
                     5000
    end

    test "process large audio bytes correctly, when split_by_chunk is on" do
      {:ok, server_pid} = TranscriptionServer.start_link(target: self(), split_by_chunk: true)
      audio_data = Fixtures.full_audio_bytes()

      TranscriptionServer.process_audio(server_pid, audio_data)

      assert_receive {
                       :stt_event,
                       %ExGoogleSTT.Transcript{
                         content:
                           "Adventure 1 a scandal in Bohemia from The Adventures of Sherlock Holmes by Sir Arthur Conan Doyle",
                         is_final: true
                       }
                     },
                     5000
    end

    test "Can process audio after an error" do
      {:ok, server_pid} = TranscriptionServer.start_link(target: self(), split_by_chunk: false)
      bad_audio = Fixtures.full_audio_bytes()
      good_audio = Fixtures.small_audio_bytes()

      TranscriptionServer.process_audio(server_pid, bad_audio)

      assert_receive {:stt_event,
                      %Error{
                        message: "Audio chunk can be of a a maximum of 25600 bytes" <> _
                      }},
                     5000

      TranscriptionServer.process_audio(server_pid, good_audio)

      assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                     5000

      assert_receive {:stt_event, %Transcript{content: "Hello."}}, 5000
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
            {:ok, server_pid} = TranscriptionServer.start_link(target: target)

            TranscriptionServer.process_audio(server_pid, audio_data)
            TranscriptionServer.end_stream(server_pid)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      for _ <- 1..number_of_sessions do
        assert_receive {:stt_event, %SpeechEvent{event: :SPEECH_ACTIVITY_BEGIN}},
                       5000

        assert_receive {:stt_event, %Transcript{content: "Advent"}}, 5000
      end
    end
  end
end
