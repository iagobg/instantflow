defmodule Instantflow.WorkflowCatalog.Corrections do
  @moduledoc "Pure explicit reset/invalidation declarations; no inferred section ownership."
  def validate(d) do
    sections = Enum.map(d["sections"], & &1["key"])
    initial = Enum.find(d["stages"], & &1["initial"])["key"]

    errors =
      Enum.flat_map(d["transitions"], fn edge ->
        spec = edge["reset"]
        targets = if spec, do: spec["sections"] ++ spec["invalidate_approvals"], else: []

        cond do
          edge["finance"] && edge["finance"]["operation"] == "release" && edge["to"] == initial &&
              is_nil(spec) ->
            [
              "transitions.#{edge["key"]}.reset: declare explicitamente as seções e aprovações invalidadas."
            ]

          Enum.any?(targets, &(&1 not in sections)) ->
            ["transitions.#{edge["key"]}.reset: seção desconhecida."]

          Enum.uniq(targets) != targets ->
            ["transitions.#{edge["key"]}.reset: não duplique alvos entre limpeza e aprovação."]

          spec && edge["from"] == edge["to"] ->
            ["transitions.#{edge["key"]}.reset: a invalidação exige mudança de etapa."]

          spec && edge["finance"] && edge["finance"]["operation"] not in ["release", "reverse"] ->
            [
              "transitions.#{edge["key"]}.reset: combine a invalidação financeira com liberação ou estorno."
            ]

          true ->
            []
        end
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end
end
