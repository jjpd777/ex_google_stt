defmodule ExGoogleSTT.Transcript do
  @moduledoc false
  defstruct [:content, :is_final]

  @type t :: %__MODULE__{
          content: String.t(),
          is_final: boolean()
        }
end
