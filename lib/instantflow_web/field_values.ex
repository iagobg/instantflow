defmodule InstantflowWeb.FieldValues do
  @moduledoc "Normalize generated form transport values before runtime validation."

  def cast("multiple_choice", ""), do: []
  def cast("multiple_choice", values) when is_list(values), do: Enum.reject(values, &(&1 == ""))
  def cast(type, "") when type not in ~w(short_text long_text), do: nil
  def cast("boolean", "true"), do: true
  def cast("boolean", "false"), do: false

  def cast(type, value) when type in ~w(integer money directory_reference) and is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> value
    end
  end

  def cast(_, value), do: value
end
