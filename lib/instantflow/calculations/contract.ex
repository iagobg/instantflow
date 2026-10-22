defmodule Instantflow.Calculations.Contract do
  @moduledoc "Compatibility facade; portable calculation validation belongs to the catalog."
  alias Instantflow.WorkflowCatalog.CalculationContract

  defdelegate key?(value), to: CalculationContract
  defdelegate digest?(value), to: CalculationContract
  defdelegate schema?(schema), to: CalculationContract
  defdelegate values?(schema, values), to: CalculationContract
  defdelegate spec?(spec, definition), to: CalculationContract
  defdelegate sections(definition, mappings), to: CalculationContract
  defdelegate calculations?(definition), to: CalculationContract
  defdelegate computed?(definition, key), to: CalculationContract
end
