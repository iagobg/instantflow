defmodule Instantflow.WorkflowCatalog.Templates do
  @moduledoc "Admin-only, organization-scoped authoring. Imports never invoke the workflow runtime."
  import Ecto.Query
  alias Instantflow.{Repo, Tenant, WorkflowCatalog}

  alias Instantflow.WorkflowCatalog.{
    Definition,
    Diff,
    Draft,
    Interchange,
    TemplateEvent,
    Version,
    Workflow
  }

  @empty_bindings %{"roles" => %{}, "departments" => %{}}

  def list(actor) do
    authorized(actor, fn _ ->
      %{
        workflows: Repo.all(from w in Workflow, order_by: w.key, limit: 200),
        drafts: Repo.all(from d in Draft, order_by: [desc: d.id], limit: 200),
        versions:
          Repo.all(
            from v in Version,
              distinct: v.workflow_id,
              order_by: [asc: v.workflow_id, desc: v.number],
              preload: [:workflow],
              limit: 200
          )
      }
    end)
  end

  def get(actor, id), do: authorized(actor, fn _ -> draft!(id) end)

  def new(actor, key, name, type \\ "form") do
    authorized(actor, fn a ->
      definition = starter(key, name, type)
      validate!(definition, :complete)
      workflow = new_workflow!(a, definition)

      bindings =
        if Instantflow.WorkflowCatalog.Workspaces.operational?(definition),
          do: %{
            "roles" => %{"operator" => ["admin"]},
            "departments" => %{"service_department" => a.department_id}
          },
          else: @empty_bindings

      insert_draft!(a, workflow, definition, nil, nil, "created", bindings)
    end)
  end

  def clone(actor, version_id) do
    authorized(actor, fn a ->
      version = version!(version_id)
      workflow = Repo.get!(Workflow, version.workflow_id)
      definition = Map.put(version.definition, "format_version", "1.0")
      validate!(definition, :draft)
      # Old pinned contracts can be repaired in a draft before re-publication.
      # Cloning within this workflow preserves its already-local configuration.
      draft = insert_draft!(a, workflow, definition, version, nil, "cloned", version.bindings)
      draft
    end)
  end

  def save(actor, id, expected_revision, definition, bindings) do
    authorized(actor, fn a ->
      draft = editable!(id, expected_revision)
      workflow = Repo.get!(Workflow, draft.workflow_id)
      validate!(definition, :draft)
      unless definition["template_key"] == workflow.key, do: Repo.rollback(:key_mismatch)

      unless WorkflowCatalog.valid_bindings?(definition, bindings, a.organization_id, :partial),
        do: Repo.rollback(:invalid_bindings)

      saved =
        draft
        |> Ecto.Changeset.change(
          definition: definition,
          bindings: bindings,
          revision: draft.revision + 1,
          updated_by_id: a.user_id
        )
        |> Repo.update!()

      audit!(a, saved, "saved", %{
        "digest" => Interchange.digest(definition),
        "bindings" => bindings
      })

      saved
    end)
  end

  def publish(actor, id, expected_revision) do
    authorized(actor, fn a ->
      draft = editable!(id, expected_revision)
      base = if draft.base_version_id, do: version!(draft.base_version_id).number, else: 0

      version = WorkflowCatalog.publish_scoped!(a, draft.definition, draft.bindings, base)

      saved =
        draft
        |> Ecto.Changeset.change(
          published_version_id: version.id,
          revision: draft.revision + 1,
          updated_by_id: a.user_id
        )
        |> Repo.update!()

      audit!(a, saved, "published", %{
        "version_id" => version.id,
        "number" => version.number,
        "digest" => Interchange.digest(draft.definition),
        "source_digest" => draft.source_digest,
        "bindings" => draft.bindings
      })

      version
    end)
    |> WorkflowCatalog.notify_publication()
  end

  # An existing target must be selected by ID. Names never choose update targets.
  def import(actor, json, options \\ %{}) do
    authorized(actor, fn a ->
      definition =
        case Interchange.decode(json) do
          {:ok, d} -> d
          _ -> Repo.rollback(:invalid_json)
        end

      unless is_map(definition) and definition["format_version"] == "1.0",
        do: Repo.rollback(:unsupported_format)

      validate!(definition, :complete)
      source_digest = Interchange.digest(definition)

      {workflow, base, definition} =
        case options["workflow_id"] do
          id when is_integer(id) ->
            workflow = Repo.get(Workflow, id) || Repo.rollback(:not_found)
            unless workflow.key == definition["template_key"], do: Repo.rollback(:key_mismatch)

            base =
              Repo.one(
                from v in Version,
                  where: v.workflow_id == ^id,
                  order_by: [desc: v.number],
                  limit: 1
              )

            {workflow, base, definition}

          nil ->
            definition =
              if options["template_key"] in [nil, ""],
                do: definition,
                else: Map.put(definition, "template_key", options["template_key"])

            validate!(definition, :complete)
            {new_workflow!(a, definition), nil, definition}

          _ ->
            Repo.rollback(:not_found)
        end

      insert_draft!(a, workflow, definition, base, source_digest, "imported")
    end)
  end

  # Dedicated export command: only active local administrators can export definitions.
  def export(actor, kind, id) do
    authorized(actor, fn _ ->
      {definition, status} =
        case kind do
          :draft -> {draft!(id).definition, "Rascunho não publicado"}
          :version -> {version!(id).definition, "Versão publicada"}
          _ -> Repo.rollback(:not_found)
        end

      definition = Map.put(definition, "format_version", "1.0")
      validate!(definition, :draft)

      %{
        json: Interchange.encode(definition),
        digest: Interchange.digest(definition),
        status: status
      }
    end)
  end

  def review(actor, id) do
    authorized(actor, fn a ->
      draft = draft!(id)
      base = if draft.base_version_id, do: version!(draft.base_version_id), else: nil
      validation = Definition.validate(draft.definition)

      mapping_errors =
        Instantflow.WorkflowCatalog.Bindings.errors(
          draft.definition,
          draft.bindings,
          a.organization_id
        )

      %{
        draft: draft,
        changes:
          Diff.compare(if(base, do: base.definition, else: %{}), draft.definition) ++
            Diff.compare(
              if(base, do: base.bindings, else: @empty_bindings),
              draft.bindings,
              "mapeamentos"
            ),
        errors:
          case validation do
            :ok -> []
            {:error, errors} -> errors
          end ++
            mapping_errors,
        warnings: warnings(draft.definition),
        roles: role_preview(draft.definition)
      }
    end)
  end

  defp role_preview(d) do
    Enum.map(d["role_requirements"], fn role ->
      %{
        id: role["key"],
        label: role["label"],
        creates?: role["key"] in d["creation"]["roles"],
        sections:
          for(
            s <- d["sections"],
            access <- s["access"],
            access["role"] == role["key"],
            do: %{
              label: s["label"],
              classification: s["classification"],
              scope: access["scope"],
              read?: access["read"],
              edits: access["edit_stages"]
            }
          ),
        transitions:
          for(
            t <- d["transitions"],
            actor <- t["actors"],
            actor["role"] == role["key"],
            do: %{label: t["label"], from: t["from"], to: t["to"], scope: actor["scope"]}
          )
      }
    end)
  end

  defp warnings(d) do
    [
      "A revisão usa apenas a definição e pessoas fictícias; não concede acesso nem prova as regras de negócio."
    ] ++
      if(Enum.any?(d["sections"], &(&1["classification"] == "restricted")),
        do: ["Há seções restritas. Confira cada regra de leitura e edição."],
        else: []
      ) ++
      if(Enum.any?(d["transitions"], &(not Map.get(&1, "disallow_requester", false))),
        do: [
          "Algumas transições permitem atuação do solicitante. Revise possíveis caminhos de aprovação própria ou desvios de análise."
        ],
        else: []
      ) ++
      if Enum.any?(
           d["transitions"],
           &(&1["actions"] != [] or Map.get(&1, "finance_sensitive", false))
         ),
         do: ["Há ações simuladas ou decisões financeiras. Confira os atores e as condições."],
         else: []
  end

  defp authorized(actor, fun) do
    Tenant.transaction(actor, fn a ->
      unless a.role == "admin", do: Repo.rollback(:forbidden)
      fun.(a)
    end)
  end

  defp draft!(id), do: Repo.get(Draft, id) || Repo.rollback(:not_found)
  defp version!(id), do: Repo.get(Version, id) || Repo.rollback(:not_found)

  defp editable!(id, revision) do
    draft =
      Repo.one(from d in Draft, where: d.id == ^id, lock: "FOR UPDATE") ||
        Repo.rollback(:not_found)

    if draft.published_version_id, do: Repo.rollback(:already_published)
    unless draft.revision == revision, do: Repo.rollback(:conflict)
    draft
  end

  defp validate!(definition, mode) do
    result =
      if mode == :draft,
        do: Definition.validate_draft(definition),
        else: Definition.validate(definition)

    case result do
      :ok -> :ok
      {:error, errors} -> Repo.rollback({:invalid_definition, errors})
    end
  end

  defp new_workflow!(a, definition) do
    Repo.query!("SELECT pg_advisory_xact_lock($1)", [a.organization_id])

    if Repo.exists?(from w in Workflow, where: w.key == ^definition["template_key"]),
      do: Repo.rollback(:key_taken)

    Repo.insert!(%Workflow{
      organization_id: a.organization_id,
      key: definition["template_key"],
      name: definition["name"]
    })
  end

  defp insert_draft!(
         a,
         workflow,
         definition,
         base,
         source_digest,
         operation,
         bindings \\ @empty_bindings
       ) do
    draft =
      Repo.insert!(%Draft{
        organization_id: a.organization_id,
        workflow_id: workflow.id,
        definition: definition,
        bindings: bindings,
        base_version_id: if(base, do: base.id),
        source_digest: source_digest,
        created_by_id: a.user_id,
        updated_by_id: a.user_id
      })

    audit!(a, draft, operation, %{
      "digest" => Interchange.digest(definition),
      "source_digest" => source_digest,
      "base_version_id" => draft.base_version_id
    })

    draft
  end

  defp audit!(a, draft, operation, details) do
    Repo.insert!(%TemplateEvent{
      organization_id: a.organization_id,
      draft_id: draft.id,
      actor_id: a.user_id,
      operation: operation,
      revision: draft.revision,
      details: details
    })
  end

  def starter(key, name, "form"), do: starter(key, name)

  def starter(key, name, type)
      when type in ~w(item_service restaurant enrollment incident requisition field_trip) do
    file = if type in ~w(item_service restaurant), do: "resource_service", else: type

    definition =
      Application.app_dir(:instantflow, "priv/workflows/#{file}.json")
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("template_key", key)
      |> Map.put("name", name)

    if type == "item_service" do
      put_in(
        definition,
        ["interface", "labels"],
        Instantflow.WorkflowCatalog.Workspaces.labels(%{"interface" => %{"labels" => %{}}})
      )
    else
      definition
    end
  end

  def starter(_, _, _), do: Repo.rollback(:unsupported_workspace)

  def starter(key, name) do
    %{
      "format_version" => "1.0",
      "template_key" => key,
      "template_version" => "1.0.0",
      "locale" => "pt-BR",
      "name" => name,
      "description" => "Processo configurado pela organização.",
      "capabilities" => ["core"],
      "role_requirements" => [
        %{"key" => "requester", "label" => "Solicitante"},
        %{"key" => "reviewer", "label" => "Responsável"}
      ],
      "sections" => [
        %{
          "key" => "request",
          "label" => "Solicitação",
          "classification" => "internal",
          "access" => [
            %{
              "role" => "requester",
              "scope" => "requester",
              "read" => true,
              "edit_stages" => ["draft"]
            },
            %{
              "role" => "reviewer",
              "scope" => "assigned_department",
              "read" => true,
              "edit_stages" => []
            }
          ],
          "fields" => [%{"key" => "summary", "label" => "Resumo", "type" => "short_text"}]
        }
      ],
      "stages" => [
        %{"key" => "draft", "label" => "Em preparação", "initial" => true, "terminal" => false},
        %{"key" => "closed", "label" => "Concluída", "initial" => false, "terminal" => true}
      ],
      "creation" => %{"roles" => ["requester"]},
      "transitions" => [
        %{
          "key" => "complete",
          "label" => "Concluir",
          "from" => "draft",
          "to" => "closed",
          "actors" => [%{"role" => "reviewer", "scope" => "assigned_department"}],
          "required_fields" => ["request.summary"],
          "require_reason" => false,
          "kind" => "forward",
          "disallow_requester" => true,
          "actions" => []
        }
      ],
      "bindings" => [
        %{"key" => "responsible", "label" => "Departamento responsável", "type" => "department"}
      ],
      "assignment" => %{"department_binding" => "responsible"},
      "views" => [
        %{
          "key" => "requests",
          "label" => "Solicitações",
          "type" => "table",
          "columns" => ["request.summary", "stage"]
        }
      ]
    }
  end
end
