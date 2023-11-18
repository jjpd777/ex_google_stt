# Google Cloud Speech gRPC API client

[![Hex.pm](https://img.shields.io/hexpm/v/ex_google_stt.svg)](https://hex.pm/packages/ex_google_stt)

Elixir client for Google Speech-to-Text V2 streaming API using gRPC

## Installation

The package can be installed by adding `:ex_google_stt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_google_stt, "~> 0.3.0"}
  ]
end
```

## Configuration

This library uses [`Goth`](https://github.com/peburrows/goth) to obtain authentication tokens. It requires Google Cloud credendials to be configured. See [Goth's README](https://github.com/peburrows/goth#installation) for details.

Using Google's V2 API requires that you set a recognizer to use for your requests (see [here](https://cloud.google.com/speech-to-text/v2/docs/reference/rest/v2/projects.locations.recognizers#Recognizer])). It is a string like the following:

`projects/{project}/locations/{location}/recognizers/{recognizer}`

You can either set this in the config or send it as a configuration when starting the `TranscriptionServer`.

In the config:
```elixir
config :ex_google_stt, recognizer: "projects/{project}/locations/{location}/recognizers/_"
```


## Usage

### Introduction
The library is designed to abstract most of the GRPC logic, so I'll provide the most basic use of it here.

- In summary, we use a `TranscriptionServer` than handles the GRPC streams to Google.
- That `TranscriptionServer` is responsible for monitoring/opening the streams and to parse the responses.
- Send audio data (as binary) using `TranscriptionServer.process_audio(server_pid, audio_data)`
- The `TranscriptionServer` will then send the responses to the target pid, set when creating the server.
- The caller should define a `handle_info` that will receive the transcripts and handle eventual errors.


### Initial Configurations
When starting the `TranscriptionServer`, you can define a few configs:

```
- target - a pid to send the results to, defaults to self()
- language_codes - a list of language codes to use for recognition, defaults to ["en-US"]
- enable_automatic_punctuation - a boolean to enable automatic punctuation, defaults to true
- interim_results - a boolean to enable interim results, defaults to false
- recognizer - a string representing the recognizer to use, defaults to use the recognizer from the config
- model - a string representing the model to use, defaults to "latest_long". Be careful, changing to 'short' may have unintended consequences
```

### Example

```elixir

defmodule MyModule.Transcribing do
  use GenServer

  alias ExGoogleSTT.{Transcript, TranscriptionServer}

  ...
  def init(_opts) do
    {:ok, transcription_server} = TranscriptionServer.start_link(target: self(), interim_results: true)
  end

  def handle_info({:got_new_speech, speech_binary}, state) do
    TranscriptionServer.process_audio(state.server_pid, speech_binary)
  end

  def handle_info({:response, %{Transcript{} = transcript}}, state) do
    # Do whatever you need with the transcription
  end


  def handle_info({:response, other_responses_or_error}, state) do
    # Do something or just ignore
  end
end

```

### Other usages
The library allows you define other response handling functions and even ditch the `GenServer` part of `TranscriptionServer` altogether.


## Notes

### Infinite stream
Google's STT V2 knows when a sentence finishes, as long as there's some silence after it. When that happens, it'll return the transcription without ending the stream.

Therefore, as long as we keep the stream open, we can keep transcribing realtime speech.

A few points to notice though.
- The `model` must be `long` or `latest_long`. `short` will result in ending the stream after the first utterance.
- One must end the stream to ensure the transcription stops.


### Auto-generated modules

This library uses [`protobuf-elixir`](https://github.com/tony612/protobuf-elixir) and its `protoc-gen-elixir` plugin to generate Elixir modules from `*.proto` files for Google's Speech gRPC API. The documentation for the types defined in `*.proto` files can be found [here](https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1)


### Tests

ALL the tests require communication with google, so you must have a google credentials configured to run them in this repo.

Tests with tag `:load_test` are excluded by default, since they can be a bit expensive to run, use `mix test --include load_test` to run them.

#### Fixture

A recording fragment in `test/fixtures` comes from an audiobook
"The adventures of Sherlock Holmes (version 2)" available on [LibriVox](https://librivox.org/the-adventures-of-sherlock-holmes-by-sir-arthur-conan-doyle/)

## Status

Current version of library supports only Streaming API and not tested in production. Treat this as experimental.

## License

Portions of this project are modifications based on work created by [![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/) and used according to terms described in the Apache License 2.0. See [here](https://github.com/software-mansion-labs/elixir-gcloud-speech-grpc) for the original repository.

The modifications are also licensed under Apache License 2.0.

## Disclaimer

While this project includes modified code from [Original Project or Code Name], it is not endorsed by or affiliated with the original authors or their organizations.
