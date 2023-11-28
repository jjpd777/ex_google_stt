defmodule ExGoogleSTT.Error do
  @moduledoc false
  defstruct [:status, :message]

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          message: String.t()
        }
end
