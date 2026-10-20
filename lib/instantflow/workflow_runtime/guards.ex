defmodule Instantflow.WorkflowRuntime.Guards do
  def pass?(nil, _, _, _), do: true

  def pass?(%{"op" => "all", "args" => args}, values, fields, deliveries),
    do: Enum.all?(args, &pass?(&1, values, fields, deliveries))

  def pass?(%{"op" => "any", "args" => args}, values, fields, deliveries),
    do: Enum.any?(args, &pass?(&1, values, fields, deliveries))

  def pass?(%{"op" => "present", "field" => ref}, values, _, _),
    do: Instantflow.WorkflowCatalog.Definition.present?(values[ref])

  def pass?(%{"op" => "delivery_succeeded", "kind" => kind}, _, _, deliveries),
    do: kind in deliveries

  def pass?(%{"op" => "attachment_ready"}, _, _, _), do: false

  def pass?(%{"op" => "in", "field" => ref, "value" => list}, values, _, _),
    do: values[ref] in list

  def pass?(%{"op" => "eq", "field" => ref, "value" => expected}, values, _, _),
    do: values[ref] == expected

  def pass?(%{"op" => op, "field" => ref, "value" => expected}, values, fields, _) do
    case compare(fields[ref]["type"], values[ref], expected) do
      :gt -> op in ~w(gt gte)
      :lt -> op in ~w(lt lte)
      :eq -> op in ~w(gte lte)
      _ -> false
    end
  end

  defp compare(_, nil, _), do: :invalid

  defp compare("date", left, right),
    do: Date.compare(Date.from_iso8601!(left), Date.from_iso8601!(right))

  defp compare("datetime", left, right) do
    {:ok, left, _} = DateTime.from_iso8601(left)
    {:ok, right, _} = DateTime.from_iso8601(right)
    DateTime.compare(left, right)
  end

  defp compare(_, left, right) when left > right, do: :gt
  defp compare(_, left, right) when left < right, do: :lt
  defp compare(_, _, _), do: :eq
end
