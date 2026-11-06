defmodule Instantflow.WorkflowRuntime.History do
  @moduledoc "Bounded record history and delivery pages with visibility applied before pagination."
  import Ecto.Query
  alias Instantflow.Repo
  alias Instantflow.WorkflowRuntime.{Event, Policy}
  alias Instantflow.Delivery.Message
  @page_size 50

  @doc "Internal query: caller holds the tenant authorization boundary with a fresh scope."
  def authorized_query(scope, ticket, version, facts \\ :live) do
    unless Repo.in_transaction?(),
      do: raise(ArgumentError, "History requires a tenant transaction")

    sections = Enum.map(version.definition["sections"], & &1["key"])
    participants = Enum.map(Map.get(version.definition, "participants", []), & &1["key"])

    releases =
      Enum.map(Instantflow.WorkflowCatalog.Communications.specs(version.definition), & &1["key"])

    operations =
      ["create"] ++
        Enum.map(version.definition["transitions"], & &1["key"]) ++
        Enum.flat_map(sections, &["save:" <> &1, "assign:" <> &1]) ++
        Enum.map(releases, &("release:" <> &1))

    allowed =
      Enum.filter(operations, &Policy.history?(scope, ticket, version, %{operation: &1}, facts))

    participant_keys =
      Enum.filter(
        participants,
        &Policy.history?(scope, ticket, version, %{operation: "participant:any:" <> &1}, facts)
      )

    document_keys =
      Enum.filter(
        sections,
        &Policy.history?(scope, ticket, version, %{operation: "document:any:" <> &1}, facts)
      )

    # Parse exactly the suffix used by Policy.history?/4, including legacy
    # action names. Match the entire relationship key, not just a prefix.
    from e in Event,
      where: e.ticket_id == ^ticket.id,
      where:
        e.operation in ^allowed or
          fragment("substring(? from '^participant:[^:]*:(.*)$')", e.operation) in ^participant_keys or
          fragment("split_part(substring(? from '^document:[^:]*:(.*)$'), '.', 1)", e.operation) in ^document_keys
  end

  @doc false
  def deliveries_query(events, ticket) do
    from m in Message,
      join: e in subquery(events),
      on: e.id == m.event_id,
      where: m.ticket_id == ^ticket.id and m.kind != "refresh" and m.payload == ^%{}
  end

  @doc false
  def pages(scope, ticket, version, options, facts \\ :live) do
    events = authorized_query(scope, ticket, version, facts)

    %{
      history: page(events, :revision, Keyword.get(options, :history_before)),
      deliveries:
        page(deliveries_query(events, ticket), :id, Keyword.get(options, :deliveries_before))
    }
  end

  defp page(_, :revision, before) when is_integer(before) and before >= 2_147_483_648,
    do: %{rows: [], next_cursor: nil}

  defp page(query, field, before)
       when is_nil(before) or
              (is_integer(before) and before > 0 and before < 9_223_372_036_854_775_807) do
    cursor = if before, do: dynamic([row], field(row, ^field) < ^before), else: dynamic(true)

    rows =
      Repo.all(
        from row in query,
          where: ^cursor,
          order_by: [desc: field(row, ^field)],
          limit: @page_size + 1
      )

    visible = Enum.take(rows, @page_size)

    %{
      rows: visible,
      next_cursor: if(length(rows) > @page_size, do: Map.fetch!(List.last(visible), field))
    }
  end

  defp page(_, _, _), do: %{rows: [], next_cursor: nil}
end
