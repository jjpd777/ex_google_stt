# Google Cloud Speech gRPC API client

[![Hex.pm](https://img.shields.io/hexpm/v/ex_google_stt.svg)](https://hex.pm/packages/ex_google_stt)

Elixir client for Google Speech-to-Text V2 streaming API using gRPC

## Installation

The package can be installed by adding `:ex_google_stt` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_google_stt, "~> 0.0.1"}
  ]
end
```

## Configuration

This library uses [`Goth`](https://github.com/peburrows/goth) to obtain authentication tokens. It requires Google Cloud credendials to be configured. See [Goth's README](https://github.com/peburrows/goth#installation) for details.

Tests with tag `:integration` communicate with Google APIs and require such config, thus are
excluded by default, use `mix test --include integration` to run them.

## Usage

### Introduction
Here's the basic flow:

#### Create your Genserver
A Genserver is required to that the `StreamingServer` can send the transcriptions back to the caller. This is captured via a `handle_info`

#### Build the configurations
```elixir
recognizer = "projects/["project_id"]/locations/global/recognizers/_"

cfg = %RecognitionConfig{
  decoding_config:
    {:auto_decoding_config, %Google.Cloud.Speech.V2.AutoDetectDecodingConfig{}},
  model: "long",
  language_codes: ["en-GB"],
  features: %{enable_automatic_punctuation: true}
}

str_cfg = %StreamingRecognitionConfig{
  config: cfg,
  streaming_features: %{interim_results: true}
}

str_cfg_req = %StreamingRecognizeRequest{
  streaming_request: {:streaming_config, str_cfg},
  recognizer: @recognizer
}
```
#### Start the server
- Start the `StreamingServer` with `start_link`
- Send the configuration request. This must always be the first request.
```elixir
{:ok, transcription_server} = StreamingServer.start_link()
StreamingServer.send_config(transcription_server, str_cfg_req)
```

#### Send Requests
```elixir
request = %StreamingRecognizeRequest{streaming_request: {:audio, data}, recognizer: recognizer}

StreamingServer.send_request(transcription_server, request)
```

#### Receive Responses
This is done in the original caller.
You can also include this in a `Phoenix.Channel`.

```elixir
def handle_info(%StreamingRecognizeResponse{} = response, state) do
  results = response.results
  transcripts = Enum.map(results, fn result ->
    [alternative] = result.alternatives
      %{content: alternative.transcript, is_final: result.is_final}
  end)
end
```

### Infinite stream
Google's STT V2 knows when a sentence finishes, as long as there's some silence after it. When that happens, it'll return the transcription without ending the stream.

Therefore, as long as we keep the stream open, we can keep transcribing realtime speech.

A few points to notice though.
- The `model` must be `long` or `latest_long`. `short` will result in ending the stream after the first utterance.
- One must end the stream to ensure the transcription stops.


## Auto-generated modules

This library uses [`protobuf-elixir`](https://github.com/tony612/protobuf-elixir) and its `protoc-gen-elixir` plugin to generate Elixir modules from `*.proto` files for Google's Speech gRPC API. The documentation for the types defined in `*.proto` files can be found [here](https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1)

## Fixture

A recording fragment in `test/fixtures` comes from an audiobook
"The adventures of Sherlock Holmes (version 2)" available on [LibriVox](https://librivox.org/the-adventures-of-sherlock-holmes-by-sir-arthur-conan-doyle/)

## Status

Current version of library supports only Streaming API and not tested in production. Treat this as experimental.
## License

This project includes modified code from [Original Project or Code Name], which is licensed under the Apache License 2.0 (the "License"). You may not use the files containing modifications from the original project except in compliance with the License. A copy of the License is included in this project in the file named `LICENSE`.

The original work is available at [link to the original repository or project homepage].

Portions of this project are modifications based on work created by [![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/) and used according to terms described in the Apache License 2.0. See [here](https://github.com/software-mansion-labs/elixir-gcloud-speech-grpc) for the original repository.

The modifications are also licensed under Apache License 2.0.

## Disclaimer

While this project includes modified code from [Original Project or Code Name], it is not endorsed by or affiliated with the original authors or their organizations.
