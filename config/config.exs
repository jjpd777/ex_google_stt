import Config

creds_path = Path.expand("./google-credentials.json", __DIR__)

if creds_path |> File.exists?() do
  config :goth, json: creds_path |> File.read!()
else
  config :goth, disabled: true
end
