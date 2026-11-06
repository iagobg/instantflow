defmodule Instantflow.WorkflowRuntime.RecordProjection do
  @moduledoc "Current record page data and controls from one authorization transaction."
  alias Instantflow.{Participants, PrivateDocuments, Tenant, WorkflowRuntime}
  alias Instantflow.Collaboration.Presence
  alias Instantflow.Delivery.Curated

  def load(actor, id, options \\ []) do
    Tenant.read_context(
      actor,
      fn context ->
        {:ok, data} = WorkflowRuntime.get_in_context(context, id, options)

        {:ok,
         %{
           data: data,
           management:
             Participants.controls_in_context(
               context,
               id,
               Keyword.get(options, :participant_query, "")
             ),
           communications:
             Curated.controls_in_context(
               context,
               id,
               Keyword.get(options, :communication_query, "")
             ),
           documents:
             PrivateDocuments.list_page_in_context(
               context,
               id,
               Keyword.get(options, :documents_before)
             ),
           presence: Presence.editors_in_context(context, id)
         }}
      end,
      {:error, :not_found}
    )
  end
end
