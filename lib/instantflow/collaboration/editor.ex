defmodule Instantflow.Collaboration.Editor do
  @moduledoc "In-memory drafts preserve their observed revisions until an explicit reconciliation."

  def new(section, ticket) do
    %{
      values: section.values,
      revision: section.revision,
      stage_revision: ticket.stage_revision,
      dirty: false,
      conflict: false,
      comparing: false,
      key: Ecto.UUID.generate()
    }
  end

  def draft(editor, values) do
    if values == editor.values,
      do: editor,
      else: %{editor | values: values, dirty: true, key: Ecto.UUID.generate()}
  end

  def reconcile(editors, data) do
    Map.new(data.sections, fn section ->
      previous = editors[section.key]

      editor =
        if previous && previous.dirty && section.key in data.editable do
          %{
            previous
            | conflict:
                previous.revision != section.revision or
                  previous.stage_revision != data.ticket.stage_revision
          }
        else
          new(section, data.ticket)
        end

      {section.key, editor}
    end)
  end

  def reapply(editor, section, ticket),
    do: %{
      editor
      | revision: section.revision,
        stage_revision: ticket.stage_revision,
        conflict: false,
        comparing: false,
        key: Ecto.UUID.generate()
    }
end
