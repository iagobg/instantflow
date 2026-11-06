defmodule Instantflow.Tenant.ReadContext do
  @moduledoc "Opaque handle to a current read boundary; never retain it in a socket or another process."
  @enforce_keys [:ref]
  defstruct [:ref]
  @opaque t :: %__MODULE__{ref: reference()}
end
