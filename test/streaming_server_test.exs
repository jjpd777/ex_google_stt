defmodule ExGoogleSTT.StreamingServerTest do
  use ExUnit.Case, async: true

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

  @recognition_cfg %RecognitionConfig{
    decoding_config: {:auto_decoding_config, %Google.Cloud.Speech.V2.AutoDetectDecodingConfig{}},
    model: "latest_long",
    language_codes: ["en-GB"],
    features: %{enable_automatic_punctuation: true}
  }
  creds_json = Application.compile_env(:goth, :json)
  Jason.decode!(creds_json)["project_id"]

  @recognizer "projects/#{Jason.decode!(creds_json)["project_id"]}/locations/global/recognizers/_"

  describe "Testing external api calls" do
    @describetag :integration
    test "recognize in parts" do
      str_cfg = %StreamingRecognitionConfig{config: @recognition_cfg}

      str_cfg_req = %StreamingRecognizeRequest{
        streaming_request: {:streaming_config, str_cfg},
        recognizer: @recognizer
      }

      content_reqs =
        Fixtures.chunked_audio_bytes()
        |> Enum.map(fn data ->
          %StreamingRecognizeRequest{streaming_request: {:audio, data}, recognizer: @recognizer}
        end)

      assert {:ok, client} = StreamingServer.start_link()
      client |> StreamingServer.send_config(str_cfg_req)

      StreamingServer.send_requests(
        client,
        content_reqs
      )

      StreamingServer.end_stream(client)

      assert_receive %StreamingRecognizeResponse{results: results}, 5000
      assert [%StreamingRecognitionResult{alternatives: alternative}] = results
      assert [%SpeechRecognitionAlternative{transcript: transcript}] = alternative

      assert transcript ==
               "Adventure 1 a scandal in Bohemia from the Adventures of Sherlock Holmes by Sir Arthur Conan Doyle"
    end

    test "interim results" do
      str_cfg = %StreamingRecognitionConfig{
        config: @recognition_cfg,
        streaming_features: %{enable_voice_activity_events: true, interim_results: true}
      }

      str_cfg_req = %StreamingRecognizeRequest{
        streaming_request: {:streaming_config, str_cfg},
        recognizer: @recognizer
      }

      requests =
        Fixtures.chunked_audio_bytes()
        |> Enum.map(fn data ->
          %StreamingRecognizeRequest{streaming_request: {:audio, data}, recognizer: @recognizer}
        end)

      assert {:ok, client} = StreamingServer.start_link(include_sender: true)
      client |> StreamingServer.send_config(str_cfg_req)

      StreamingServer.send_requests(
        client,
        requests
      )

      %{last_response: last_response, interim_results: interim_results} =
        capture_interim_responses(client)

      %{transcript: final_transcript, is_final: true} = last_response

      assert_interim_results(interim_results)

      assert final_transcript ==
               "Adventure 1 a scandal in Bohemia from the Adventures of Sherlock Holmes by Sir Arthur Conan Doyle"

      StreamingServer.end_stream(client)
    end
  end

  defp capture_interim_responses(client, interim_results \\ []) do
    assert_receive {^client, %StreamingRecognizeResponse{} = response}, 5000

    parsed_results = parse_results(response.results)
    interim_results = interim_results ++ parsed_results

    if last_response = Enum.find(parsed_results, & &1.is_final) do
      %{last_response: last_response, interim_results: interim_results}
    else
      capture_interim_responses(client, interim_results)
    end
  end

  defp parse_results(results) do
    for result <- results do
      %{alternatives: [%{transcript: transcript}], is_final: is_final} = result
      %{transcript: transcript, is_final: is_final}
    end
  end

  # This checks for 90% accuracy, as the interim results are not deterministic
  defp assert_interim_results(interim_results) when is_list(interim_results) do
    interim_transcripts =
      interim_results
      |> Enum.map(&(&1.transcript |> String.trim() |> String.downcase()))

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

    assert matches / length(expected_interims) >= 0.9
  end

  test "shutdown on monitored process down" do
    target = self()

    task =
      Task.async(fn ->
        send(target, {:client, StreamingServer.start_link(monitor_target: true)})
        receive do: (:exit -> :ok)
      end)

    assert_receive {:client, {:ok, client}}, 2000
    ref = Process.monitor(client)
    send(task.pid, :exit)
    assert :ok = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^client, :normal}
  end
end
