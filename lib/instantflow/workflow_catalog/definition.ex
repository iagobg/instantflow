defmodule Instantflow.WorkflowCatalog.Definition do
  @moduledoc "Shared structural and semantic validation for editing, interchange and publication."
  @types ~w(short_text long_text integer money date datetime boolean single_choice multiple_choice directory_reference attachment)
  @scopes ~w(requester assigned_department guardian workflow_department assigned_user)
  @kinds ~w(forward correction resubmission rejection cancellation reopening)
  @actions ~w(simulate_notification simulate_provisioning simulate_payment)

  def validate(definition) when is_map(definition) do
    with :ok <- bounded(definition),
         :ok <- schema(definition),
         :ok <- shape(definition),
         :ok <- references(definition),
         :ok <- graph(definition) do
      :ok
    end
  rescue
    _ -> {:error, ["Definição inválida: revise os tipos e as referências."]}
  end

  def validate(_), do: error("A definição deve ser um objeto.")

  # Drafts may have incomplete graphs/references; unsupported structures never enter storage.
  def validate_draft(definition) when is_map(definition) do
    with :ok <- bounded(definition), :ok <- schema(definition), :ok <- shape(definition), do: :ok
  rescue
    _ -> error("Definição inválida: revise os tipos e as referências.")
  end

  def validate_draft(_), do: error("A definição deve ser um objeto.")

  # Existing immutable versions use the pre-Sprint-03 spelling of the same contract.
  defp schema(%{"format_version" => "1.0-draft"} = d),
    do: Instantflow.WorkflowCatalog.Schema.validate(Map.put(d, "format_version", "1.0"))

  defp schema(d), do: Instantflow.WorkflowCatalog.Schema.validate(d)

  def fields(definition) do
    for section <- definition["sections"],
        field <- section["fields"],
        into: %{},
        do: {section["key"] <> "." <> field["key"], field}
  end

  def validate_values(section, values) when is_map(values) do
    allowed = Map.new(section["fields"], &{&1["key"], &1})

    if Enum.all?(values, fn {key, value} ->
         Map.has_key?(allowed, key) and valid_value?(allowed[key], value)
       end),
       do: :ok,
       else: error("Há campos desconhecidos ou valores incompatíveis com o formulário.")
  end

  def validate_values(_, _), do: error("Os valores devem ser um objeto.")

  def present?(value),
    do:
      value != nil and value != "" and value != [] and
        (not is_binary(value) or String.trim(value) != "")

  def valid_value?(_field, nil), do: true

  def valid_value?(%{"type" => "short_text"}, value),
    do: is_binary(value) and String.length(value) <= 200

  def valid_value?(%{"type" => "long_text"}, value),
    do: is_binary(value) and String.length(value) <= 10_000

  def valid_value?(%{"type" => "integer"}, value),
    do: is_integer(value) and abs(value) <= 9_007_199_254_740_991

  def valid_value?(%{"type" => "money"}, value),
    do: is_integer(value) and value >= 0 and value <= 9_007_199_254_740_991

  def valid_value?(%{"type" => "boolean"}, value), do: is_boolean(value)

  def valid_value?(%{"type" => "date"}, value),
    do: is_binary(value) and match?({:ok, _}, Date.from_iso8601(value))

  def valid_value?(%{"type" => "datetime"}, value),
    do: is_binary(value) and match?({:ok, _, _}, DateTime.from_iso8601(value))

  def valid_value?(%{"type" => "single_choice", "options" => options}, value),
    do: value in options

  def valid_value?(%{"type" => "multiple_choice", "options" => options}, value),
    do: is_list(value) and Enum.uniq(value) == value and Enum.all?(value, &(&1 in options))

  # The owning context additionally proves ticket, field and organization ownership.
  def valid_value?(%{"type" => "attachment"}, value),
    do: is_binary(value) and Regex.match?(~r/^[0-9a-f-]{36}$/, value)

  def valid_value?(%{"type" => "directory_reference"}, _value),
    do: false

  def valid_value?(_, _), do: false

  defp bounded(value) do
    if byte_size(Jason.encode!(value)) <= 1_048_576 and depth(value) <= 20,
      do: :ok,
      else: error("A definição excede os limites de tamanho ou profundidade.")
  end

  defp depth(map) when is_map(map),
    do: 1 + (map |> Map.values() |> Enum.map(&depth/1) |> Enum.max(fn -> 0 end))

  defp depth(list) when is_list(list),
    do: 1 + (list |> Enum.map(&depth/1) |> Enum.max(fn -> 0 end))

  defp depth(_), do: 0
  defp label?(value), do: is_binary(value) and String.length(value) in 1..200
  defp key?(value), do: is_binary(value) and Regex.match?(~r/^[a-z][a-z0-9_]{0,63}$/, value)

  defp keyed?(list),
    do:
      is_list(list) and Enum.all?(list, &(is_map(&1) and key?(&1["key"]))) and
        length(Enum.uniq_by(list, & &1["key"])) == length(list)

  defp props?(map, keys), do: is_map(map) and Enum.all?(Map.keys(map), &(&1 in keys))

  defp shape(d) do
    valid =
      props?(
        d,
        ~w(format_version template_key template_version locale name description capabilities role_requirements sections stages creation transitions bindings assignment views)
      ) and
        d["format_version"] in ["1.0", "1.0-draft"] and d["locale"] == "pt-BR" and
        key?(d["template_key"]) and
        label?(d["name"]) and
        d["capabilities"] in [["core"], ["core", "finance"]] and keyed?(d["role_requirements"]) and
        length(d["role_requirements"]) in 1..30 and
        keyed?(d["stages"]) and length(d["stages"]) in 1..100 and keyed?(d["sections"]) and
        length(d["sections"]) in 1..100 and
        keyed?(d["transitions"]) and length(d["transitions"]) <= 500 and keyed?(d["bindings"]) and
        Enum.all?(d["stages"], fn s ->
          props?(s, ~w(key label initial terminal)) and label?(s["label"]) and
            is_boolean(s["initial"]) and is_boolean(s["terminal"])
        end) and
        Enum.all?(d["role_requirements"], fn r ->
          props?(r, ~w(key label)) and label?(r["label"])
        end) and
        Enum.all?(d["bindings"], fn b ->
          props?(b, ~w(key type label)) and b["type"] in ~w(department budget) and
            label?(b["label"])
        end) and
        Enum.all?(d["sections"], &valid_section?/1) and map_size(fields(d)) <= 300 and
        Enum.all?(d["transitions"], &valid_transition?/1) and props?(d["creation"], ["roles"]) and
        props?(d["assignment"], ["department_binding"])

    if valid,
      do: :ok,
      else: error("Estrutura inválida: verifique chaves, tipos, rótulos e recursos suportados.")
  end

  defp valid_section?(s) do
    props?(s, ~w(key label classification access fields assignment)) and label?(s["label"]) and
      s["classification"] in ~w(internal restricted) and
      is_list(s["access"]) and s["access"] != [] and
      Enum.uniq_by(s["access"], &{&1["role"], &1["scope"]}) == s["access"] and
      Enum.all?(s["access"], fn a ->
        props?(a, ~w(role scope department_binding assignment_key read edit_stages)) and
          a["scope"] in @scopes and
          is_boolean(a["read"]) and is_list(a["edit_stages"]) and
          (a["edit_stages"] == [] or a["read"])
      end) and
      keyed?(s["fields"]) and
      Enum.all?(s["fields"], fn f ->
        props?(f, ~w(key label type options currency)) and label?(f["label"]) and
          f["type"] in @types and
          (f["type"] not in ~w(single_choice multiple_choice) or
             (is_list(f["options"]) and length(f["options"]) in 1..100 and
                Enum.all?(f["options"], &label?/1) and Enum.uniq(f["options"]) == f["options"])) and
          (not Map.has_key?(f, "options") or f["type"] in ~w(single_choice multiple_choice)) and
          (not Map.has_key?(f, "currency") or f["type"] == "money") and
          (f["type"] != "money" or
             (is_binary(f["currency"]) and Regex.match?(~r/^[A-Z]{3}$/, f["currency"])))
      end)
  end

  defp valid_transition?(t) do
    props?(
      t,
      ~w(key label from to actors required_fields require_reason kind disallow_requester finance_sensitive history_visibility actions guard department_binding finance)
    ) and label?(t["label"]) and
      is_list(t["actors"]) and t["actors"] != [] and
      Enum.all?(
        t["actors"],
        &(props?(&1, ~w(role scope department_binding assignment_key)) and &1["scope"] in @scopes)
      ) and
      is_boolean(t["require_reason"]) and t["kind"] in @kinds and
      (not Map.has_key?(t, "disallow_requester") or is_boolean(t["disallow_requester"])) and
      (not Map.has_key?(t, "finance_sensitive") or is_boolean(t["finance_sensitive"])) and
      Map.get(t, "history_visibility", "participants") in ~w(participants actors) and
      (t["kind"] not in ~w(correction rejection cancellation reopening) or t["require_reason"]) and
      is_list(t["required_fields"]) and is_list(t["actions"]) and length(t["actions"]) <= 10 and
      Enum.uniq(t["actions"]) == t["actions"] and
      Enum.all?(t["actions"], fn a ->
        props?(a, ~w(type behavior)) and a["type"] in @actions and
          a["behavior"] in ~w(success fail_once failure)
      end)
  end

  defp references(d) do
    stages = Enum.map(d["stages"], & &1["key"])
    terminal = d["stages"] |> Enum.filter(& &1["terminal"]) |> Enum.map(& &1["key"])
    roles = Enum.map(d["role_requirements"], & &1["key"])
    fields = fields(d)

    valid =
      is_list(d["creation"]["roles"]) and d["creation"]["roles"] != [] and
        Enum.all?(d["creation"]["roles"], &(&1 in roles)) and
        Enum.any?(
          d["bindings"],
          &(&1["type"] == "department" and &1["key"] == d["assignment"]["department_binding"])
        ) and
        Enum.all?(d["sections"], fn s ->
          valid_assignment?(s["assignment"], d, roles, stages) and
            Enum.all?(s["access"], fn a ->
              valid_actor?(a, roles, d) and
                Enum.all?(a["edit_stages"], &(&1 in stages and &1 not in terminal))
            end)
        end) and
        keyed?(d["views"]) and
        Enum.all?(d["views"], fn v ->
          Enum.all?(
            v["columns"],
            &(&1 in ~w(stage assigned_department) or Map.has_key?(fields, &1))
          )
        end) and
        Enum.all?(d["transitions"], fn t ->
          finance_spec?(t["finance"], d) and t["from"] in stages and t["to"] in stages and
            Enum.all?(t["actors"], &valid_actor?(&1, roles, d)) and
            (not Map.has_key?(t, "department_binding") or
               Enum.any?(
                 d["bindings"],
                 &(&1["type"] == "department" and &1["key"] == t["department_binding"])
               )) and
            Enum.all?(t["required_fields"], &Map.has_key?(fields, &1)) and
            valid_guard?(t["guard"], fields, 0) and valid_resubmission?(t, d)
        end)

    if valid, do: :ok, else: error("Há referências, guardas ou caminhos de correção inválidos.")
  end

  defp finance_spec?(nil, _), do: true

  defp finance_spec?(spec, d) do
    fields = fields(d)

    d["capabilities"] == ["core", "finance"] and
      Enum.any?(d["bindings"], &(&1["type"] == "budget" and &1["key"] == spec["account_binding"])) and
      (spec["operation"] not in ~w(reserve post) or
         (get_in(fields, [spec["amount_field"], "type"]) == "money" and
            get_in(fields, [spec["amount_field"], "currency"]) == "BRL")) and
      (spec["operation"] != "complete" or
         Enum.all?(
           ~w(quantity_field received_field),
           &(get_in(fields, [spec[&1], "type"]) == "integer")
         ))
  end

  defp valid_assignment?(nil, _, _, _), do: true

  defp valid_assignment?(spec, d, roles, stages) do
    spec["role"] in roles and Enum.all?(spec["stages"], &(&1 in stages)) and
      Enum.any?(
        d["bindings"],
        &(&1["type"] == "department" and &1["key"] == spec["department_binding"])
      ) and
      Enum.all?(
        spec["managers"],
        &(&1["scope"] != "assigned_user" and valid_actor?(&1, roles, d))
      )
  end

  defp valid_actor?(a, roles, d) do
    a["role"] in roles and
      case a["scope"] do
        "workflow_department" ->
          not Map.has_key?(a, "assignment_key") and
            Enum.any?(
              d["bindings"],
              &(&1["type"] == "department" and &1["key"] == a["department_binding"])
            )

        "assigned_user" ->
          not Map.has_key?(a, "department_binding") and
            Enum.any?(
              d["sections"],
              &(&1["key"] == a["assignment_key"] and not is_nil(&1["assignment"]))
            )

        _ ->
          not Map.has_key?(a, "department_binding") and not Map.has_key?(a, "assignment_key")
      end
  end

  defp valid_resubmission?(%{"kind" => "resubmission"} = t, d),
    do:
      Enum.any?(
        d["transitions"],
        &(&1["kind"] == "correction" and &1["from"] == t["to"] and &1["to"] == t["from"])
      )

  defp valid_resubmission?(_, _), do: true
  defp valid_guard?(nil, _, _), do: true
  defp valid_guard?(_, _, depth) when depth > 8, do: false

  defp valid_guard?(%{"op" => op, "args" => args} = g, fields, depth) when op in ~w(all any),
    do:
      props?(g, ~w(op args)) and is_list(args) and length(args) in 1..20 and
        Enum.all?(args, &(not is_nil(&1) and valid_guard?(&1, fields, depth + 1)))

  defp valid_guard?(%{"op" => "delivery_succeeded", "kind" => kind} = g, _, _),
    do: props?(g, ~w(op kind)) and kind in @actions

  defp valid_guard?(%{"op" => "present", "field" => ref} = g, fields, _),
    do: props?(g, ~w(op field)) and Map.has_key?(fields, ref)

  defp valid_guard?(%{"op" => "attachment_ready", "field" => ref} = g, fields, _),
    do: props?(g, ~w(op field)) and get_in(fields, [ref, "type"]) == "attachment"

  defp valid_guard?(%{"op" => "in", "field" => ref, "value" => values} = g, fields, _) do
    props?(g, ~w(op field value)) and Map.has_key?(fields, ref) and
      fields[ref]["type"] not in ~w(attachment directory_reference) and is_list(values) and
      length(values) in 1..100 and
      Enum.all?(values, &(not is_nil(&1) and valid_value?(fields[ref], &1)))
  end

  defp valid_guard?(%{"op" => op, "field" => ref, "value" => value} = g, fields, _)
       when op in ~w(eq gt gte lt lte) do
    props?(g, ~w(op field value)) and Map.has_key?(fields, ref) and
      fields[ref]["type"] not in ~w(attachment directory_reference) and not is_nil(value) and
      valid_value?(fields[ref], value) and
      (op == "eq" or fields[ref]["type"] in ~w(integer money date datetime))
  end

  defp valid_guard?(_, _, _), do: false

  defp graph(d) do
    initial = Enum.filter(d["stages"], & &1["initial"])
    terminal = Enum.filter(d["stages"], & &1["terminal"])

    if length(initial) == 1 and terminal != [] do
      [entry] = initial
      reached = walk([entry["key"]], d["transitions"], MapSet.new())

      valid =
        Enum.all?(d["stages"], fn s ->
          reachable = walk([s["key"]], d["transitions"], MapSet.new())

          MapSet.member?(reached, s["key"]) and
            Enum.any?(terminal, &MapSet.member?(reachable, &1["key"])) and
            (not s["terminal"] or
               Enum.all?(
                 Enum.filter(d["transitions"], &(&1["from"] == s["key"])),
                 &(&1["kind"] == "reopening")
               ))
        end)

      if valid,
        do: :ok,
        else:
          error(
            "Todas as etapas devem ser alcançáveis e permitir encerramento; etapas finais só podem reabrir explicitamente."
          )
    else
      error("Defina uma única etapa inicial e pelo menos uma etapa final.")
    end
  end

  defp walk([], _, visited), do: visited

  defp walk([head | rest], transitions, visited) do
    if MapSet.member?(visited, head),
      do: walk(rest, transitions, visited),
      else:
        walk(
          rest ++ (transitions |> Enum.filter(&(&1["from"] == head)) |> Enum.map(& &1["to"])),
          transitions,
          MapSet.put(visited, head)
        )
  end

  defp error(message), do: {:error, [message]}
end
