import Config

config :ex_google_stt, recognizer: System.fetch_env!("GOOGLE_SPEECH_RECOGNIZER")
