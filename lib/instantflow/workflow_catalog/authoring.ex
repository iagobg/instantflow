defmodule Instantflow.WorkflowCatalog.Authoring do
  @moduledoc "Fixed, typed authoring controls over the declarative contract. No dynamic atoms or executable code."
  alias Instantflow.WorkflowCatalog.{Definition, Interchange}

  @collections ~w(stages sections fields access transitions actions roles bindings views participants communications)
  @types %{
    key: :string,
    label: :string,
    type: :string,
    initial: :boolean,
    terminal: :boolean,
    classification: :string,
    role: :string,
    scope: :string,
    department_binding: :string,
    assignment_key: :string,
    relationship: :string,
    recipient_relationship: :string,
    message_fields: {:array, :string},
    guard_communication: :string,
    manager_roles: {:array, :string},
    candidate_roles: {:array, :string},
    reference_target: :string,
    reference_relationship: :string,
    document_reviewers: {:array, :string},
    document_department: :string,
    document_max_bytes: :integer,
    document_media_types: {:array, :string},
    read: :boolean,
    edit_stages: {:array, :string},
    options: :string,
    currency: :string,
    from: :string,
    to: :string,
    kind: :string,
    requester_roles: {:array, :string},
    department_roles: {:array, :string},
    required_fields: {:array, :string},
    require_reason: :boolean,
    disallow_requester: :boolean,
    finance_sensitive: :boolean,
    history_visibility: :string,
    behavior: :string,
    columns: {:array, :string},
    visibility_roles: {:array, :string},
    view_filters: {:array, :string},
    sort_field: :string,
    sort_direction: :string,
    calendar_field: :string,
    urgency_field: :string,
    urgency_values: :string,
    assignment_section: :string,
    reset_sections: {:array, :string},
    invalidate_approvals: {:array, :string},
    reset_enabled: :boolean,
    creates: :boolean,
    guard_op: :string,
    guard_field: :string,
    guard_value: :string,
    guard_kind: :string,
    guard_json: :string
  }

  def collections, do: @collections

  def field_types,
    do:
      ~w(short_text long_text integer money date datetime boolean single_choice multiple_choice directory_reference attachment)

  def form(item \\ %{}, definition \\ nil) do
    data = %{
      key: item["key"],
      label: item["label"],
      type: item["type"],
      initial: item["initial"] || false,
      terminal: item["terminal"] || false,
      classification: item["classification"] || "internal",
      role: item["role"],
      scope: item["scope"] || "requester",
      department_binding:
        item["department_binding"] ||
          get_in(item, ["managers", Access.at(0), "department_binding"]) ||
          get_in(item, ["release_actors", Access.at(0), "department_binding"]),
      assignment_key: item["assignment_key"],
      relationship: item["relationship"],
      recipient_relationship: item["recipient_relationship"],
      message_fields: Enum.filter(item["fields"] || [], &is_binary/1),
      guard_communication: get_in(item, ["guard", "communication"]),
      manager_roles: for(a <- item["managers"] || item["release_actors"] || [], do: a["role"]),
      candidate_roles: item["candidate_roles"] || [],
      reference_target: get_in(item, ["reference", "target"]),
      reference_relationship: get_in(item, ["reference", "relationship"]),
      document_reviewers:
        for(a <- get_in(item, ["document_policy", "reviewers"]) || [], do: a["role"]),
      document_department:
        get_in(item, ["document_policy", "reviewers", Access.at(0), "department_binding"]),
      document_max_bytes: get_in(item, ["document_policy", "max_bytes"]) || 5_242_880,
      document_media_types:
        get_in(item, ["document_policy", "media_types"]) ||
          ~w(application/pdf image/png image/jpeg),
      read: Map.get(item, "read", true),
      edit_stages: item["edit_stages"] || [],
      options: Enum.join(item["options"] || [], "\n"),
      currency: item["currency"] || "BRL",
      from: item["from"],
      to: item["to"],
      kind: item["kind"] || "forward",
      requester_roles: for(a <- item["actors"] || [], a["scope"] == "requester", do: a["role"]),
      department_roles:
        for(a <- item["actors"] || [], a["scope"] == "assigned_department", do: a["role"]),
      required_fields: item["required_fields"] || [],
      require_reason: item["require_reason"] || false,
      disallow_requester: item["disallow_requester"] || false,
      finance_sensitive: item["finance_sensitive"] || false,
      history_visibility: item["history_visibility"] || "participants",
      behavior: item["behavior"] || "success",
      columns: item["columns"] || [],
      visibility_roles: item["visibility_roles"] || [],
      view_filters: item["filters"] || [],
      sort_field: get_in(item, ["sort", "field"]) || "id",
      sort_direction: get_in(item, ["sort", "direction"]) || "desc",
      calendar_field: item["calendar_field"] || "",
      urgency_field: get_in(item, ["urgency", "field"]) || "",
      urgency_values: Enum.join(get_in(item, ["urgency", "values"]) || [], "\n"),
      assignment_section: item["assignment_section"] || "",
      reset_sections: get_in(item, ["reset", "sections"]) || [],
      invalidate_approvals: get_in(item, ["reset", "invalidate_approvals"]) || [],
      reset_enabled: Map.has_key?(item, "reset"),
      creates: definition != nil and item["key"] in definition["creation"]["roles"],
      guard_op: item["guard"]["op"] || "",
      guard_field: item["guard"]["field"],
      guard_value:
        if(item["guard"] && Map.has_key?(item["guard"], "value"),
          do: Jason.encode!(item["guard"]["value"]),
          else: ""
        ),
      guard_kind: item["guard"]["kind"],
      guard_json: Interchange.encode(item["guard"])
    }

    Ecto.Changeset.change({data, @types})
  end

  def change(definition, collection, parent, original_key, params)
      when collection in @collections do
    params =
      Map.new(params, fn {key, value} ->
        {key, if(is_list(value), do: Enum.reject(value, &(&1 == "")), else: value)}
      end)

    changeset = form() |> Ecto.Changeset.cast(params, Map.keys(@types))

    if changeset.valid? do
      values = Ecto.Changeset.apply_changes(changeset)
      current = items(definition, collection, parent)
      old = Enum.find(current, &(identity(&1, collection) == original_key)) || %{}
      item = build(collection, values, old, definition)
      identity = identity(item, collection)

      cond do
        original_key != nil and old == %{} ->
          {:error, :not_found}

        original_key != nil and identity != original_key and collection not in ~w(access actions) ->
          {:error, :immutable_key}

        identity != original_key and Enum.any?(current, &(identity(&1, collection) == identity)) ->
          {:error, :duplicate_key}

        true ->
          updated =
            if original_key,
              do:
                Enum.map(
                  current,
                  &if(identity(&1, collection) == original_key, do: item, else: &1)
                ),
              else: current ++ [item]

          result = put_items(definition, collection, parent, updated)

          result =
            if collection == "roles",
              do:
                put_in(
                  result,
                  ["creation", "roles"],
                  update_members(result["creation"]["roles"], item["key"], values.creates)
                ),
              else: result

          result =
            if collection == "fields" and item["document_policy"],
              do: Map.update!(result, "capabilities", &Enum.uniq(&1 ++ ["documents"])),
              else: result

          {:ok, result}
      end
    else
      {:error, changeset}
    end
  rescue
    _ -> {:error, :invalid_control}
  end

  def change(_, _, _, _, _), do: {:error, :invalid_control}

  def move_stage(definition, key, direction) when direction in ["up", "down"] do
    stages = definition["stages"]
    index = Enum.find_index(stages, &(&1["key"] == key))
    target = if index, do: index + if(direction == "up", do: -1, else: 1)

    if index && target >= 0 && target < length(stages) do
      reordered =
        stages
        |> List.replace_at(index, Enum.at(stages, target))
        |> List.replace_at(target, Enum.at(stages, index))

      {:ok, Map.put(definition, "stages", reordered)}
    else
      {:error, :invalid_control}
    end
  end

  def move_stage(_, _, _), do: {:error, :invalid_control}

  def remove(definition, collection, parent, key) when collection in @collections do
    list = items(definition, collection, parent)

    if Enum.any?(list, &(identity(&1, collection) == key)),
      do:
        {:ok,
         put_items(
           definition,
           collection,
           parent,
           Enum.reject(list, &(identity(&1, collection) == key))
         )},
      else: {:error, :not_found}
  rescue
    _ -> {:error, :not_found}
  end

  def remove(_, _, _, _), do: {:error, :invalid_control}

  def items(d, "fields", parent), do: find_parent(d["sections"], parent)["fields"]
  def items(d, "access", parent), do: find_parent(d["sections"], parent)["access"]
  def items(d, "actions", parent), do: find_parent(d["transitions"], parent)["actions"]
  def items(d, "roles", _), do: d["role_requirements"]
  def items(d, "participants", _), do: Map.get(d, "participants", [])
  def items(d, "communications", _), do: Map.get(d, "communications", [])
  def items(d, c, _) when c in @collections, do: d[c]

  def identity(%{"scope" => "participant"} = item, "access"),
    do: item["role"] <> ":participant:" <> item["relationship"]

  def identity(item, "access"), do: item["role"] <> ":" <> item["scope"]
  def identity(item, "actions"), do: item["type"] <> ":" <> item["behavior"]
  def identity(item, _), do: item["key"]

  defp find_parent(list, key), do: Enum.find(list, &(&1["key"] == key)) || raise(ArgumentError)

  defp put_items(d, collection, parent, items) when collection in ~w(fields access actions) do
    outer = if collection == "actions", do: "transitions", else: "sections"

    Map.update!(d, outer, fn list ->
      Enum.map(list, &if(&1["key"] == parent, do: Map.put(&1, collection, items), else: &1))
    end)
  end

  defp put_items(d, "roles", _, items), do: Map.put(d, "role_requirements", items)

  defp put_items(d, "communications", _, items) do
    d
    |> Map.put("communications", items)
    |> Map.update!("capabilities", &Enum.uniq(&1 ++ ["participants", "communications"]))
  end

  defp put_items(d, "participants", _, []), do: Map.delete(d, "participants")

  defp put_items(d, "participants", _, items) do
    d
    |> Map.put("participants", items)
    |> Map.update!("capabilities", &Enum.uniq(&1 ++ ["participants"]))
  end

  defp put_items(d, collection, _, items), do: Map.put(d, collection, items)

  defp update_members(list, key, true), do: Enum.uniq(list ++ [key])
  defp update_members(list, key, false), do: List.delete(list, key)
  defp base(v), do: %{"key" => v.key, "label" => v.label}

  defp build("stages", v, _, _),
    do: Map.merge(base(v), %{"initial" => v.initial, "terminal" => v.terminal})

  defp build("roles", v, _, _), do: base(v)

  defp build("communications", v, old, _) do
    actors =
      if Enum.all?(old["release_actors"] || [], &(&1["scope"] == "workflow_department")) do
        Enum.map(
          v.manager_roles,
          &%{
            "role" => &1,
            "scope" => "workflow_department",
            "department_binding" => v.department_binding
          }
        )
      else
        old["release_actors"]
      end

    Map.merge(base(v), %{
      "recipient_relationship" => v.recipient_relationship,
      "fields" => v.message_fields,
      "release_actors" => actors,
      "behavior" => v.behavior
    })
  end

  defp build("participants", v, old, _) do
    managers =
      if Enum.all?(old["managers"] || [], &(&1["scope"] == "workflow_department")) do
        Enum.map(
          v.manager_roles,
          &%{
            "role" => &1,
            "scope" => "workflow_department",
            "department_binding" => v.department_binding
          }
        )
      else
        # Imported assigned-department managers retain their declared semantics.
        old["managers"]
      end

    Map.merge(base(v), %{
      "kind" => v.kind,
      "managers" => managers,
      "candidate_roles" => v.candidate_roles
    })
  end

  defp build("bindings", v, old, _), do: Map.put(base(v), "type", old["type"] || "department")

  defp build("sections", v, old, _),
    do:
      Map.merge(
        Map.take(old, ["assignment"]),
        Map.merge(base(v), %{
          "classification" => v.classification,
          "fields" => old["fields"] || [],
          "access" =>
            old["access"] ||
              [
                %{
                  "role" => "requester",
                  "scope" => "requester",
                  "read" => true,
                  "edit_stages" => []
                }
              ]
        })
      )

  defp build("fields", v, old, _) do
    field = Map.put(base(v), "type", v.type)

    cond do
      v.type == "attachment" and v.document_reviewers != [] ->
        old_policy = old["document_policy"]

        policy =
          if old_policy &&
               Enum.any?(old_policy["reviewers"], &(&1["scope"] != "workflow_department")) do
            old_policy
          else
            %{
              "reviewers" =>
                Enum.map(
                  v.document_reviewers,
                  &%{
                    "role" => &1,
                    "scope" => "workflow_department",
                    "department_binding" => v.document_department
                  }
                ),
              "max_bytes" => v.document_max_bytes,
              "media_types" => v.document_media_types
            }
          end

        Map.put(field, "document_policy", policy)

      v.type == "directory_reference" and v.reference_target not in [nil, ""] ->
        Map.put(field, "reference", %{
          "target" => v.reference_target,
          "relationship" => v.reference_relationship,
          "cardinality" => "one"
        })

      v.type in ~w(single_choice multiple_choice) ->
        Map.put(field, "options", String.split(v.options || "", "\n", trim: true))

      v.type == "money" ->
        Map.put(field, "currency", v.currency)

      true ->
        field
    end
  end

  defp build("access", v, _, _) do
    item = %{
      "role" => v.role,
      "scope" => v.scope,
      "read" => v.read,
      "edit_stages" => v.edit_stages
    }

    case v.scope do
      "participant" -> Map.put(item, "relationship", v.relationship)
      "workflow_department" -> Map.put(item, "department_binding", v.department_binding)
      "assigned_user" -> Map.put(item, "assignment_key", v.assignment_key)
      _ -> item
    end
  end

  defp build("actions", v, _, _), do: %{"type" => v.type, "behavior" => v.behavior}

  defp build("views", v, _, _) do
    view =
      Map.merge(base(v), %{
        "type" => v.type,
        "columns" => v.columns,
        "filters" => v.view_filters,
        "sort" => %{"field" => v.sort_field, "direction" => v.sort_direction}
      })

    view =
      if v.visibility_roles == [],
        do: view,
        else: Map.put(view, "visibility_roles", v.visibility_roles)

    view =
      if v.calendar_field in [nil, ""],
        do: view,
        else: Map.put(view, "calendar_field", v.calendar_field)

    view =
      if v.assignment_section in [nil, ""],
        do: view,
        else: Map.put(view, "assignment_section", v.assignment_section)

    if v.urgency_field in [nil, ""],
      do: view,
      else:
        Map.put(view, "urgency", %{
          "field" => v.urgency_field,
          "values" => String.split(v.urgency_values || "", "\n", trim: true)
        })
  end

  defp build("transitions", v, old, d) do
    actors =
      Enum.map(v.requester_roles, &%{"role" => &1, "scope" => "requester"}) ++
        Enum.map(v.department_roles, &%{"role" => &1, "scope" => "assigned_department"}) ++
        Enum.filter(
          old["actors"] || [],
          &(&1["scope"] in ~w(workflow_department assigned_user participant))
        )

    item =
      Map.merge(base(v), %{
        "from" => v.from,
        "to" => v.to,
        "kind" => v.kind,
        "actors" => actors,
        "required_fields" => v.required_fields,
        "require_reason" => v.require_reason,
        "disallow_requester" => v.disallow_requester,
        "finance_sensitive" => v.finance_sensitive,
        "history_visibility" => v.history_visibility,
        "actions" => old["actions"] || [],
        "guard" => guard(v, d)
      })

    item = Map.merge(Map.take(old, ~w(calculation requires_calculation)), item)
    item = if old["finance"], do: Map.put(item, "finance", old["finance"]), else: item

    item =
      if v.reset_enabled,
        do:
          Map.put(item, "reset", %{
            "sections" => v.reset_sections,
            "invalidate_approvals" => v.invalidate_approvals
          }),
        else: item

    if v.department_binding in [nil, ""],
      do: item,
      else: Map.put(item, "department_binding", v.department_binding)
  end

  defp guard(%{guard_op: op}, _) when op in [nil, ""], do: nil

  defp guard(%{guard_op: op} = v, _) when op in ~w(all any) do
    case Interchange.decode(v.guard_json) do
      {:ok, %{"op" => ^op} = g} -> g
      _ -> raise ArgumentError
    end
  end

  defp guard(%{guard_op: "delivery_succeeded"} = v, _),
    do: %{"op" => "delivery_succeeded", "kind" => v.guard_kind}

  defp guard(%{guard_op: "communication_succeeded"} = v, _),
    do: %{"op" => "communication_succeeded", "communication" => v.guard_communication}

  defp guard(%{guard_op: op} = v, _) when op in ~w(present attachment_ready),
    do: %{"op" => op, "field" => v.guard_field}

  defp guard(v, d) do
    field = Definition.fields(d)[v.guard_field] || raise ArgumentError

    value =
      case Jason.decode(v.guard_value || "") do
        {:ok, value} ->
          value

        _ ->
          if field["type"] in ~w(short_text long_text single_choice date datetime),
            do: v.guard_value,
            else: raise(ArgumentError)
      end

    %{"op" => v.guard_op, "field" => v.guard_field, "value" => value}
  end
end
