defmodule Instantflow.WorkflowRuntime.ParticipantPreview do
  @moduledoc "Synthetic draft preview using the runtime actor/section policy; never reads records or executes commands."
  alias Instantflow.WorkflowRuntime.Policy

  def project(definition, params) do
    page = Instantflow.WorkflowCatalog.ParticipantPages.find(definition, params["page"])
    role = params["role"]
    stage = params["stage"]
    roles = Enum.map(definition["role_requirements"], & &1["key"])
    actor = %Instantflow.Identity.Membership{id: -1, user_id: -1, role: role, department_id: -1}

    ticket = %Instantflow.WorkflowRuntime.Ticket{
      id: -1,
      requester_id: -2,
      stage: stage,
      assigned_department_id: -1
    }

    version = %{
      definition: definition,
      bindings: %{
        "roles" => Map.new(roles, &{&1, [&1]}),
        "departments" => Map.new(definition["bindings"], &{&1["key"], -1})
      }
    }

    facts = %{
      relationships:
        if(params["verified"] == "true",
          do: Enum.map(Map.get(definition, "participants", []), & &1["key"]),
          else: []
        ),
      assignments: []
    }

    visible =
      page && role in roles && stage in Enum.map(definition["stages"], & &1["key"]) &&
        role in page["participant"]["visibility_roles"] &&
        Enum.any?(
          page["participant"]["audience"],
          &Policy.actor?(actor, ticket, version, &1, facts)
        ) &&
        Enum.any?(
          definition["sections"],
          &Policy.section?(actor, ticket, version, &1, :read, facts)
        )

    if visible do
      spec = page["participant"]
      fields = Instantflow.WorkflowCatalog.Definition.fields(definition)

      readable = fn ref ->
        key = hd(String.split(ref, "."))
        section = Enum.find(definition["sections"], &(&1["key"] == key))

        section && Map.has_key?(fields, ref) &&
          Policy.section?(actor, ticket, version, section, :read, facts)
      end

      %{
        allowed?: true,
        fields:
          for(
            ref <- spec["fields"],
            readable.(ref),
            do: %{id: ref, label: fields[ref]["label"], value: "Exemplo sintético"}
          ),
        documents: Enum.filter(spec["documents"], readable),
        actions:
          for(
            edge <- definition["transitions"],
            edge["key"] in spec["actions"],
            Policy.transition?(actor, ticket, version, edge, facts),
            do: edge["label"]
          ),
        status: if(spec["status"], do: stage),
        messages: spec["messages"] || []
      }
    else
      %{allowed?: false, fields: [], documents: [], actions: [], status: nil, messages: []}
    end
  end
end
