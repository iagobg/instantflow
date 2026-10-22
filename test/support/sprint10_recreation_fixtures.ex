defmodule Instantflow.Sprint10RecreationFixtures do
  @moduledoc "Independent-key copies of the documented examples, using only shared declarations."

  def definition(name) do
    source =
      Application.app_dir(:instantflow, "priv/workflows/#{name}.json")
      |> File.read!()
      |> Jason.decode!()

    source =
      case name do
        "enrollment" -> enrollment(source)
        "incident" -> incident(source)
        _ -> finance(source, name)
      end

    source |> rename() |> Map.put("template_key", "independent_#{name}")
  end

  def key(key), do: "copy_" <> key
  def ref(ref), do: ref |> String.split(".") |> Enum.map_join(".", &key/1)

  def equipment do
    d = Instantflow.BuilderFixtures.equipment_participant_definition()

    actor = %{
      "role" => "technician",
      "scope" => "workflow_department",
      "department_binding" => "workshop"
    }

    participant = %{"role" => "customer", "scope" => "participant", "relationship" => "owner"}

    d
    |> Map.update!("capabilities", &(&1 ++ ["communications"]))
    |> Map.put("communications", [
      communication("repair_notice", "owner", ["work_order.fault_report"], actor)
    ])
    |> update_in(["interface", "access"], fn _ ->
      %{
        "view" => ["technician"],
        "configure" => ["technician"],
        "operate" => ["technician"]
      }
    end)
    |> update_in(
      ["interface", "pages"],
      &(&1 ++
          [
            page(
              "customer",
              ["customer"],
              [participant],
              ["repair_packet.fault"],
              ["repair_packet.proof"],
              ["send_details"],
              ["repair_notice"]
            )
          ])
    )
    |> update_in(
      ["views", Access.at(0)],
      &Map.merge(&1, %{
        "filters" => ["work_order.fault_report"],
        "sort" => %{"field" => "id", "direction" => "desc"}
      })
    )
  end

  defp enrollment(d) do
    actor = %{
      "role" => "admissions",
      "scope" => "workflow_department",
      "department_binding" => "admissions_department"
    }

    participant = %{"role" => "guardian", "scope" => "participant", "relationship" => "family"}

    d
    |> Map.put("capabilities", ~w(core participants documents communications))
    |> convert_guardian()
    |> Map.put("participants", [
      %{
        "key" => "family",
        "label" => "Família verificada",
        "kind" => "external",
        "candidate_roles" => ["guardian"],
        "managers" => [actor]
      }
    ])
    |> Map.update!("sections", fn sections ->
      Enum.map(sections, fn section ->
        Map.update!(section, "fields", fn fields ->
          Enum.map(fields, fn field ->
            if field["type"] == "attachment",
              do:
                Map.put(field, "document_policy", %{
                  "reviewers" => [actor],
                  "max_bytes" => 4096,
                  "media_types" => ["application/pdf"]
                }),
              else: field
          end)
        end)
      end)
    end)
    |> Map.put("communications", [
      communication("admission_notice", "family", ["identity.display_name"], actor)
    ])
    |> Map.put("interface", %{
      "access" => %{"view" => ~w(admissions academic finance it)},
      "pages" => [
        %{"key" => "staff", "label" => "Equipe", "blocks" => ["records"]},
        page(
          "family_portal",
          ["guardian"],
          [participant],
          ~w(application.student_name application.guardian_name application.school_year),
          ["application.document"],
          ~w(submit resubmit),
          ["admission_notice"]
        )
      ]
    })
  end

  defp incident(d) do
    actor = %{
      "role" => "dean",
      "scope" => "workflow_department",
      "department_binding" => "dean_department"
    }

    d
    |> Map.update!("capabilities", &Enum.uniq(&1 ++ ~w(participants communications documents)))
    |> update_in(
      ["sections", Access.at(2), "fields", Access.at(1)],
      &Map.put(&1, "document_policy", %{
        "reviewers" => [
          %{"role" => "counselor", "scope" => "assigned_user", "assignment_key" => "support"}
        ],
        "max_bytes" => 4096,
        "media_types" => ["application/pdf"]
      })
    )
    |> Map.update!(
      "role_requirements",
      &(&1 ++ [%{"key" => "recipient", "label" => "Destinatário convidado"}])
    )
    |> Map.put("participants", [
      %{
        "key" => "contact",
        "label" => "Contato verificado",
        "kind" => "external",
        "candidate_roles" => ["recipient"],
        "managers" => [actor]
      }
    ])
    |> Map.put("communications", [
      communication("resolution_notice", "contact", ["communication.message"], actor)
    ])
    |> Map.update!("transitions", fn edges ->
      Enum.map(edges, fn edge ->
        case edge["key"] do
          "communicate" ->
            Map.put(edge, "actions", [])

          "close" ->
            Map.put(edge, "guard", %{
              "op" => "communication_succeeded",
              "communication" => "resolution_notice"
            })

          _ ->
            edge
        end
      end)
    end)
    |> Map.put("interface", %{
      "access" => %{"view" => ~w(teacher dean counselor)},
      "pages" => [
        %{"key" => "triage_workspace", "label" => "Acompanhamento", "blocks" => ["records"]}
      ]
    })
  end

  defp finance(d, name) do
    view = %{
      "key" => "configured_work",
      "label" => "Trabalho autorizado",
      "type" => if(name == "field_trip", do: "calendar", else: "board"),
      "columns" => ~w(stage request.summary),
      "filters" => ["request.quantity"],
      "sort" => %{"field" => "id", "direction" => "desc"}
    }

    view =
      if name == "field_trip", do: Map.put(view, "calendar_field", "request.date"), else: view

    d
    |> Map.put("views", [view])
    |> Map.put("interface", %{
      "access" => %{"view" => ~w(requester head finance operations safety reverser)},
      "finance" => %{
        "account_binding" => "shared_budget",
        "scope" => "process",
        "view_roles" => ~w(finance head)
      },
      "pages" => [
        %{
          "key" => "work",
          "label" => "Execução",
          "blocks" => ~w(records finance_summary finance_setup)
        }
      ]
    })
  end

  defp communication(key, relationship, fields, actor),
    do: %{
      "key" => key,
      "label" => "Resultado compartilhado",
      "recipient_relationship" => relationship,
      "fields" => fields,
      "release_actors" => [actor],
      "behavior" => "fail_once"
    }

  defp page(key, roles, audience, fields, documents, actions, messages),
    do: %{
      "key" => key,
      "label" => "Minha participação",
      "blocks" => ["records"],
      "participant" => %{
        "visibility_roles" => roles,
        "audience" => audience,
        "fields" => fields,
        "documents" => documents,
        "actions" => actions,
        "messages" => messages,
        "status" => true,
        "history" => true
      }
    }

  defp convert_guardian(map) when is_map(map) do
    result = Map.new(map, fn {k, v} -> {k, convert_guardian(v)} end)

    if result["scope"] == "guardian",
      do: result |> Map.put("scope", "participant") |> Map.put("relationship", "family"),
      else: result
  end

  defp convert_guardian(list) when is_list(list), do: Enum.map(list, &convert_guardian/1)
  defp convert_guardian(value), do: value

  defp rename(d) do
    keys = collect_keys(d) |> Enum.uniq()
    rewrite(d, keys, nil)
  end

  defp collect_keys(map) when is_map(map),
    do: List.wrap(map["key"]) ++ Enum.flat_map(Map.values(map), &collect_keys/1)

  defp collect_keys(list) when is_list(list), do: Enum.flat_map(list, &collect_keys/1)
  defp collect_keys(_), do: []

  defp rewrite(map, keys, _parent) when is_map(map),
    do: Map.new(map, fn {k, v} -> {k, rewrite(v, keys, k)} end)

  defp rewrite(value, _, parent)
       when parent in ~w(capabilities blocks type kind scope behavior op operation classification locale format_version currency),
       do: value

  defp rewrite(list, keys, parent) when is_list(list),
    do: Enum.map(list, &rewrite(&1, keys, parent))

  defp rewrite(value, _, "field") when value in ~w(id stage urgency), do: value

  defp rewrite(value, keys, _) when is_binary(value),
    do: value |> String.split(".") |> Enum.map_join(".", &if(&1 in keys, do: key(&1), else: &1))

  defp rewrite(value, _, _), do: value
end
