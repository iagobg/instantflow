defmodule Instantflow.BuilderFixtures do
  @moduledoc "Incremental recreation fixtures installed through import, mapping and publication."
  alias Instantflow.WorkflowCatalog.{Interchange, Templates}

  def install(actor, definition, bindings) do
    {:ok, draft} = Templates.import(actor, Interchange.encode(definition))
    {:ok, saved} = Templates.save(actor, draft.id, draft.revision, definition, bindings)
    {:ok, version} = Templates.publish(actor, saved.id, saved.revision)
    version
  end

  def core_definition, do: Templates.starter("core_baseline", "Processo básico")

  def invite_external(admin, email) do
    {:ok, invitation} =
      Instantflow.Identity.invite(admin, %{
        "email" => email,
        "role" => "external",
        "department_id" => admin.department_id
      })

    {:ok, user} =
      Instantflow.Identity.accept_invitation(
        invitation.token,
        %{"name" => "Participante convidado", "password" => "fictional-password-123"}
      )

    Instantflow.Identity.scope(user.id, admin.organization_id)
  end

  def participant_definition(key \\ "service_intake") do
    definition = Templates.starter(key, "Atendimento externo")

    external_section = %{
      "key" => "customer_details",
      "label" => "Dados do cliente",
      "classification" => "restricted",
      "access" => [
        %{
          "role" => "visitor",
          "scope" => "participant",
          "relationship" => "claimant",
          "read" => true,
          "edit_stages" => ["draft"]
        }
      ],
      "fields" => [%{"key" => "description", "label" => "Relato", "type" => "long_text"}]
    }

    definition
    |> Map.put("capabilities", ["core", "participants"])
    |> Map.update!("role_requirements", &(&1 ++ [%{"key" => "visitor", "label" => "Cliente"}]))
    |> Map.update!("sections", &(&1 ++ [external_section]))
    |> Map.put("participants", [
      %{
        "key" => "claimant",
        "label" => "Cliente verificado",
        "kind" => "external",
        "candidate_roles" => ["visitor"],
        "managers" => [
          %{
            "role" => "reviewer",
            "scope" => "workflow_department",
            "department_binding" => "responsible"
          }
        ]
      }
    ])
  end

  def participant_command(
        ticket_id,
        membership_id,
        operation,
        revision,
        key \\ Ecto.UUID.generate()
      ) do
    %{
      "operation" => operation,
      "ticket_id" => ticket_id,
      "membership_id" => membership_id,
      "relationship" => "claimant",
      "expected_revision" => revision,
      "key" => key
    }
  end

  def directory_definition(key \\ "directory_intake") do
    participant_definition(key)
    |> update_in(["sections", Access.at(0), "access"], fn rules ->
      Enum.map(rules, &Map.put(&1, "edit_stages", ["draft"]))
    end)
    |> update_in(
      ["sections", Access.at(0), "fields"],
      &(&1 ++
          [
            %{
              "key" => "contact",
              "label" => "Contato verificado",
              "type" => "directory_reference",
              "reference" => %{
                "target" => "participant",
                "relationship" => "claimant",
                "cardinality" => "one"
              }
            }
          ])
    )
  end

  def document_definition(key \\ "document_intake") do
    directory_definition(key)
    |> Map.update!("capabilities", &(&1 ++ ["documents"]))
    |> update_in(
      ["sections", Access.at(1), "access"],
      &(&1 ++
          [
            %{
              "role" => "reviewer",
              "scope" => "assigned_department",
              "read" => true,
              "edit_stages" => []
            }
          ])
    )
    |> update_in(
      ["sections", Access.at(1), "fields"],
      &(&1 ++
          [
            %{
              "key" => "evidence",
              "label" => "Comprovante",
              "type" => "attachment",
              "document_policy" => %{
                "reviewers" => [
                  %{
                    "role" => "reviewer",
                    "scope" => "workflow_department",
                    "department_binding" => "responsible"
                  }
                ],
                "max_bytes" => 4096,
                "media_types" => ["application/pdf"]
              }
            }
          ])
    )
    |> update_in(
      ["transitions", Access.at(0), "required_fields"],
      &(&1 ++ ["customer_details.evidence"])
    )
  end

  # Independent participant workflow configured through the shared contracts.
  def participant_page_definition do
    visitor = %{"role" => "visitor", "scope" => "participant", "relationship" => "claimant"}

    reviewer = %{
      "role" => "reviewer",
      "scope" => "workflow_department",
      "department_binding" => "responsible"
    }

    document_definition("repair_authorization")
    |> update_in(
      ["sections", Access.at(1), "fields"],
      &(&1 ++
          [
            %{
              "key" => "private_marker",
              "label" => "Controle fora da projeção",
              "type" => "short_text"
            }
          ])
    )
    |> Map.update!(
      "participants",
      &(&1 ++
          [
            %{
              "key" => "observer",
              "label" => "Pessoa referenciada",
              "kind" => "subject",
              "candidate_roles" => ["visitor"],
              "managers" => [reviewer]
            }
          ])
    )
    |> Map.put("stages", [
      %{
        "key" => "draft",
        "label" => "Documentação solicitada",
        "initial" => false,
        "terminal" => false
      },
      %{
        "key" => "inspection",
        "label" => "Em conferência",
        "initial" => true,
        "terminal" => false
      },
      %{
        "key" => "closed",
        "label" => "Autorização concluída",
        "initial" => false,
        "terminal" => true
      }
    ])
    |> Map.put("transitions", [
      %{
        "key" => "send_packet",
        "label" => "Enviar documentação",
        "from" => "draft",
        "to" => "inspection",
        "actors" => [visitor],
        "required_fields" => ["customer_details.description", "customer_details.evidence"],
        "require_reason" => false,
        "kind" => "resubmission",
        "actions" => []
      },
      %{
        "key" => "request_changes",
        "label" => "Solicitar correção",
        "from" => "inspection",
        "to" => "draft",
        "actors" => [reviewer],
        "required_fields" => [],
        "require_reason" => true,
        "kind" => "correction",
        "actions" => []
      },
      %{
        "key" => "complete",
        "label" => "Concluir autorização",
        "from" => "inspection",
        "to" => "closed",
        "actors" => [reviewer],
        "required_fields" => [],
        "require_reason" => false,
        "kind" => "forward",
        "actions" => []
      }
    ])
    |> Map.put("interface", %{
      "access" => %{"view" => ["requester", "reviewer"]},
      "pages" => [
        %{"key" => "staff", "label" => "Atendimento interno", "blocks" => ["records"]},
        %{
          "key" => "my_packet",
          "label" => "Minha documentação",
          "blocks" => ["records"],
          "participant" => %{
            "visibility_roles" => ["visitor", "reviewer"],
            "audience" => [visitor, reviewer],
            "fields" => ["customer_details.description"],
            "documents" => ["customer_details.evidence"],
            "actions" => ["send_packet", "request_changes"],
            "status" => true,
            "history" => true
          }
        }
      ]
    })
  end

  # Deliberately configured from a blank form, without a school/restaurant starter.
  # Participant correction, attachments and parts are added by their owning sprints.
  def equipment_definition do
    %{
      "format_version" => "1.0",
      "template_key" => "equipment_service_desk",
      "template_version" => "1.0.0",
      "locale" => "pt-BR",
      "name" => "Assistência de equipamentos",
      "description" => "Cenário sintético de composição do construtor.",
      "capabilities" => ["core", "operations"],
      "role_requirements" => [%{"key" => "technician", "label" => "Técnico"}],
      "sections" => [
        %{
          "key" => "work_order",
          "label" => "Ordem de serviço",
          "classification" => "internal",
          "access" => [
            %{
              "role" => "technician",
              "scope" => "assigned_department",
              "read" => true,
              "edit_stages" => ["servicing"]
            }
          ],
          "fields" => [
            %{"key" => "fault_report", "label" => "Defeito informado", "type" => "short_text"}
          ]
        }
      ],
      "stages" => [
        %{"key" => "servicing", "label" => "Em reparo", "initial" => true, "terminal" => false},
        %{"key" => "collected", "label" => "Retirado", "initial" => false, "terminal" => true}
      ],
      "creation" => %{"roles" => ["technician"]},
      "transitions" => [
        %{
          "key" => "handover",
          "label" => "Entregar equipamento",
          "from" => "servicing",
          "to" => "collected",
          "actors" => [%{"role" => "technician", "scope" => "assigned_department"}],
          "required_fields" => [],
          "require_reason" => false,
          "kind" => "forward",
          "actions" => []
        }
      ],
      "bindings" => [%{"key" => "workshop", "label" => "Oficina", "type" => "department"}],
      "assignment" => %{"department_binding" => "workshop"},
      "views" => [
        %{
          "key" => "repairs",
          "label" => "Reparos",
          "type" => "table",
          "columns" => ["work_order.fault_report", "stage"]
        }
      ],
      "interface" => %{
        "operations" => Instantflow.WorkflowCatalog.OperationalContract.defaults(),
        "pages" => [
          %{
            "key" => "counter",
            "label" => "Balcão",
            "blocks" => ["records", "catalog", "resources", "items", "batches", "settlement"]
          }
        ],
        "lifecycle" => %{"close_transition" => "handover"},
        "labels" => %{
          "resource" => "Bancada",
          "resources" => "Bancadas",
          "catalog" => "Peças",
          "actor" => "Técnico",
          "destination" => "Setor"
        }
      }
    }
  end

  def equipment_participant_definition do
    department_actor = %{
      "role" => "technician",
      "scope" => "workflow_department",
      "department_binding" => "workshop"
    }

    customer_actor = %{"role" => "customer", "scope" => "participant", "relationship" => "owner"}

    packet = %{
      "key" => "repair_packet",
      "label" => "Dados para reparo",
      "classification" => "restricted",
      "access" => [
        Map.merge(customer_actor, %{"read" => true, "edit_stages" => ["changes_requested"]}),
        Map.merge(department_actor, %{"read" => true, "edit_stages" => []})
      ],
      "fields" => [
        %{"key" => "fault", "label" => "Defeito", "type" => "long_text"},
        %{
          "key" => "proof",
          "label" => "Comprovante",
          "type" => "attachment",
          "document_policy" => %{
            "reviewers" => [department_actor],
            "max_bytes" => 4096,
            "media_types" => ["application/pdf"]
          }
        }
      ]
    }

    equipment_definition()
    |> Map.put("template_key", "equipment_external_desk")
    |> Map.put("capabilities", ~w(core operations participants documents))
    |> Map.update!("role_requirements", &(&1 ++ [%{"key" => "customer", "label" => "Cliente"}]))
    |> Map.put("participants", [
      %{
        "key" => "owner",
        "label" => "Responsável pelo equipamento",
        "kind" => "external",
        "candidate_roles" => ["customer"],
        "managers" => [department_actor]
      }
    ])
    |> update_in(
      ["sections", Access.at(0), "fields"],
      &(&1 ++
          [
            %{
              "key" => "customer_link",
              "label" => "Cliente verificado",
              "type" => "directory_reference",
              "reference" => %{
                "target" => "participant",
                "relationship" => "owner",
                "cardinality" => "one"
              }
            }
          ])
    )
    |> Map.update!("sections", &(&1 ++ [packet]))
    |> Map.update!(
      "stages",
      &(&1 ++
          [
            %{
              "key" => "changes_requested",
              "label" => "Ajustes solicitados",
              "initial" => false,
              "terminal" => false
            }
          ])
    )
    |> update_in(
      ["transitions", Access.at(0), "required_fields"],
      fn _ -> ["work_order.customer_link", "repair_packet.proof"] end
    )
    |> Map.update!(
      "transitions",
      &(&1 ++
          [
            %{
              "key" => "request_details",
              "label" => "Solicitar dados",
              "from" => "servicing",
              "to" => "changes_requested",
              "actors" => [department_actor],
              "required_fields" => [],
              "require_reason" => true,
              "kind" => "correction",
              "actions" => []
            },
            %{
              "key" => "send_details",
              "label" => "Reenviar dados",
              "from" => "changes_requested",
              "to" => "servicing",
              "actors" => [customer_actor],
              "required_fields" => ["repair_packet.fault", "repair_packet.proof"],
              "require_reason" => false,
              "kind" => "resubmission",
              "actions" => []
            }
          ])
    )
  end
end
