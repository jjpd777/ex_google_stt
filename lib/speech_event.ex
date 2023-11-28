defmodule ExGoogleSTT.SpeechEvent do
  @moduledoc false
  defstruct [:event]

  @type t :: %__MODULE__{
          event: atom()
        }
end
