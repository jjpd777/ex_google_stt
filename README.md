# Google Cloud Speech gRPC API client

[![Hex.pm](https://img.shields.io/hexpm/v/ex_google_stt.svg)](https://hex.pm/packages/ex_google_stt)

Elixir client for Google Speech-to-Text streaming API using gRPC

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

## Usage example

```elixir
alias Google.Cloud.Speech.V1.{
  RecognitionConfig,
  StreamingRecognitionConfig,
  StreamingRecognizeRequest,
  StreamingRecognizeResponse
}

alias ExGoogleSTT.StreamingServer

cfg =
  RecognitionConfig.new(
    audio_channel_count: 1,
    encoding: :FLAC,
    language_code: "en-GB",
    sample_rate_hertz: 16_000
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
  part_c::binary>> = File.read!("test/support/fixtures/sample.flac")

content_reqs =
  [part_a, part_b, part_c] |> Enum.map(fn data ->
    StreamingRecognizeRequest.new(
      streaming_request: {:audio_content, data}
    )
  end)

{:ok, client} = Client.start_link()
client |> Client.send_request(str_cfg_req)

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
```

## Auto-generated modules

This library uses [`protobuf-elixir`](https://github.com/tony612/protobuf-elixir) and its `protoc-gen-elixir` plugin to generate Elixir modules from `*.proto` files for Google's Speech gRPC API. The documentation for the types defined in `*.proto` files can be found [here](https://cloud.google.com/speech-to-text/docs/reference/rpc/google.cloud.speech.v1)

### Mapping between Protobuf types and Elixir modules

Since the auto-generated modules have poor typing and no docs, the mapping may not be obvious. Here are some clues about how to use them:

* Structs defined in these modules should be created with `new/1` function accepting keyword list with values for fields
* when message field is an union field, it should be set to a tuple with atom indicating content of this field and an actual value, e.g. for `StreamingRecognizeRequest` the field `streaming_request` can be set to either `{:streaming_config, config}` or `{:audio_content, "binary_with_audio_data"}`
* Fields of enum types can be set to an integer or an atom matching the enum, e.g. value of field `:audio_encoding` in `RecognitionConfig` can be set to `:FLAC` or `2`

## Fixture

A recording fragment in `test/fixtures` comes from an audiobook
"The adventures of Sherlock Holmes (version 2)" available on [LibriVox](https://librivox.org/the-adventures-of-sherlock-holmes-by-sir-arthur-conan-doyle/)

## Status

Current version of library supports only Streaming API, regular and LongRunning are not implemented

<!-- TODO: Decide which license to use -->
## License

This project includes modified code from [Original Project or Code Name], which is licensed under the Apache License 2.0 (the "License"). You may not use the files containing modifications from the original project except in compliance with the License. A copy of the License is included in this project in the file named `LICENSE`.

### Apache License 2.0

The original work is available at [link to the original repository or project homepage].

Portions of this project are modifications based on work created by [![Software Mansion](https://membraneframework.github.io/static/logo/swm_logo_readme.png)](https://swmansion.com/) and used according to terms described in the Apache License 2.0. See [here](https://github.com/software-mansion-labs/elixir-gcloud-speech-grpc) for the original repository.

The modifications are licensed under [Your New License], which is [brief description of your license, including how it differs from Apache 2.0, if applicable].

A copy of [Your New License] is included in this project in the file named `YOUR_LICENSE_FILE`.

### Changes Made

A summary of changes made to the original source:
- [Date] Description of modifications made (by [Your Name or Your Organization])
- [Date] Further changes or additions (by [Your Name or Your Organization])

*Please refer to the commit history for a complete list of changes.*

## Contributing

[If you wish to accept contributions from others, provide instructions on how they should do so. This could include the process for submitting pull requests, code of conduct, and other relevant processes for your project.]

## Disclaimer

While this project includes modified code from [Original Project or Code Name], it is not endorsed by or affiliated with the original authors or their organizations.

## Contact

For questions and support regarding this project, please contact [Your Contact Information].

