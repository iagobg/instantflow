defmodule Instantflow.Demo.School do
  @moduledoc "D01 synthetic installation data; all case mutations use shared runtime commands."
  import Ecto.Query
  alias Instantflow.{Access, Finance, Identity, Repo, Tenant, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.Identity.{Department, Membership, Organization, User}
  alias Instantflow.WorkflowCatalog.{Retirement, Version, Workflow}
  alias Instantflow.WorkflowRuntime.{Receipt, Ticket}

  @scenario "demo:d01:purchasing:1"
  @cases [
    {"Cadernos para oficina de escrita", "draft"},
    {"Livros para a biblioteca itinerante", "academic"},
    {"Tintas para o ateliê de artes", "finance"},
    {"Jogos de lógica para o 6º ano", "purchase"},
    {"Sementes para a horta pedagógica", "receiving"},
    {"Mapas para a sala de geografia", "complete"},
    {"Tecidos para a mostra cultural", "corrected"},
    {"Pastas para o arquivo escolar", "cancelled"}
  ]

  def validate_password!(password) do
    unless is_binary(password) and String.length(password) in 12..128,
      do: raise(ArgumentError, "DEMO_PASSWORD must contain 12–128 characters")

    :ok
  end

  # The task validates its target before starting repos. The repo argument permits
  # sandboxed acceptance tests; it is used only for operator bootstrap/inventory.
  def install!(password, operator \\ Instantflow.OperatorRepo) do
    if Application.get_env(:instantflow, :environment) == :prod,
      do: raise("Synthetic demo installation is forbidden in production")

    validate_password!(password)

    org =
      ensure(operator, Organization, [slug: "horizonte"], %{name: "Escola Horizonte (fictícia)"})

    departments =
      Map.new(
        [
          {"head", "Coordenação"},
          {"finance", "Financeiro"},
          {"operations", "Operações"},
          {"safety", "Direção"}
        ],
        fn {key, name} ->
          department = ensure(operator, Department, [organization_id: org.id, name: name], %{})
          {key <> "_department", department.id}
        end
      )

    presenter =
      member!(
        operator,
        org,
        departments["head_department"],
        "admin@escola.example",
        "Ana Martins — apresentação",
        "admin",
        password
      )

    staff =
      member!(
        operator,
        org,
        departments["head_department"],
        "docente@escola.example",
        "Clara Oliveira — solicitante",
        "staff",
        password
      )

    author =
      member!(
        operator,
        org,
        departments["head_department"],
        "compras@escola.example",
        "Bruno Lima — projetos pedagógicos",
        "staff",
        password
      )

    grant!(presenter, author, departments["head_department"], "teacher")
    author = Identity.scope(author.user_id, org.id)

    grant!(presenter, presenter, departments["head_department"], "teacher")
    grant!(presenter, presenter, departments["head_department"], "head")
    grant!(presenter, presenter, departments["finance_department"], "finance")
    grant!(presenter, presenter, departments["finance_department"], "finance_allocator")
    grant!(presenter, presenter, departments["operations_department"], "operations")
    grant!(presenter, staff, departments["head_department"], "teacher")
    presenter = Identity.scope(presenter.user_id, org.id)
    staff = Identity.scope(staff.user_id, org.id)

    account =
      operator.get_by(Finance.Account,
        organization_id: org.id,
        department_id: departments["finance_department"],
        name: "Materiais pedagógicos — demo"
      ) ||
        ok!(
          Finance.create_account(
            presenter,
            departments["finance_department"],
            "Materiais pedagógicos — demo"
          )
        )

    ok!(
      Finance.allocate(
        presenter,
        account.id,
        1_000_000,
        "Dotação fictícia da demonstração D01",
        @scenario <> ":budget"
      )
    )

    bindings = %{
      "roles" => %{
        "requester" => ["teacher"],
        "head" => ["head"],
        "finance" => ["finance"],
        "operations" => ["operations"],
        "safety" => ["dean"],
        "reverser" => ["finance_reverser"]
      },
      "departments" => departments,
      "budgets" => %{"shared_budget" => account.id}
    }

    version = version!(presenter, bindings)

    @cases
    |> Enum.with_index(1)
    |> Enum.each(fn {{title, target}, index} ->
      requester =
        case index do
          1 -> staff
          7 -> presenter
          _ -> author
        end

      key = "#{@scenario}:v#{version.id}:case#{index}"

      # A case and its entire initial history commit together. A repeat never
      # reapplies fixture steps over edits made during a presentation.
      ok!(
        Tenant.transaction(presenter, fn _ ->
          Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

          unless Repo.get_by(Receipt,
                   organization_id: org.id,
                   actor_id: requester.user_id,
                   operation: "create",
                   key: key
                 ) do
            id =
              ok!(
                WorkflowRuntime.command(requester, %{
                  "operation" => "create",
                  "workflow_id" => version.workflow_id,
                  "key" => key
                })
              )["ticket_id"]

            values = %{
              "summary" => title,
              "justification" =>
                "Projeto pedagógico fictício de novembro de 2026. Sem compra ou fornecedor real.",
              "quantity" => index + 3,
              "amount" => 2500 + index * 750
            }

            save!(requester, id, "request", values, key <> ":request")
            advance!(presenter, requester, id, target, index, key)
          end
        end)
      )
    end)

    inventory(operator, org, version, [presenter, staff, author])
  end

  defp ensure(operator, schema, keys, attrs) do
    operator.get_by(schema, keys) ||
      operator.insert!(struct(schema, Map.merge(Map.new(keys), attrs)))
  end

  defp member!(operator, org, department_id, email, name, role, password) do
    user =
      operator.get_by(User, email: email) ||
        operator.insert!(User.changeset(%User{email: email}, %{name: name, password: password}))

    member =
      ensure(operator, Membership, [organization_id: org.id, user_id: user.id], %{
        department_id: department_id,
        role: role
      })

    unless member.active and member.role == role and user.active,
      do: raise("Demo identity changed or revoked: #{email}; not reactivating it")

    Identity.scope(user.id, org.id) || raise("Demo identity unavailable: #{email}")
  end

  defp grant!(admin, member, department, role) do
    exists? =
      Tenant.read(admin, fn _ ->
        Repo.exists?(
          from g in Access.Grant,
            where:
              g.membership_id == ^member.id and
                g.department_id == ^department and g.role == ^role
        )
      end)

    unless exists?, do: ok!(Access.grant(admin, member.id, department, role))
  end

  defp version!(actor, bindings) do
    definition = Instantflow.Examples.definition("requisition")

    ok!(
      Tenant.transaction(actor, fn _ ->
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [actor.organization_id])

        latest =
          Repo.one(
            from v in Version,
              join: w in Workflow,
              on: w.id == v.workflow_id,
              where: w.key == "requisition",
              order_by: [desc: v.number],
              limit: 1
          )

        cond do
          is_nil(latest) or Retirement.retired?(latest.id) ->
            ok!(
              WorkflowCatalog.publish(
                actor,
                definition,
                bindings,
                if(latest, do: latest.number, else: 0)
              )
            )

          latest.definition == definition and latest.bindings == bindings ->
            latest

          true ->
            raise(
              "Demo publication differs from the fixture; preserve its pins and review explicitly"
            )
        end
      end)
    )
  end

  defp advance!(_presenter, _requester, _id, "draft", _index, _key), do: :ok

  defp advance!(presenter, requester, id, target, index, key) do
    transition!(requester, id, "submit", key <> ":submit")

    if target not in ["academic"] do
      if target == "corrected" do
        transition!(
          presenter,
          id,
          "revise_academic",
          key <> ":return",
          "Detalhar os materiais antes de renovar a aprovação (exemplo fictício)."
        )
      else
        advance_finance!(presenter, id, target, index, key)
      end
    end
  end

  defp advance_finance!(actor, id, "cancelled", _index, key) do
    transition!(
      actor,
      id,
      "cancel_academic",
      key <> ":cancel",
      "Atividade fictícia cancelada antes da compra."
    )
  end

  defp advance_finance!(actor, id, target, index, key) do
    transition!(actor, id, "academic_approve", key <> ":approve")

    if target != "finance" do
      transition!(actor, id, "reserve", key <> ":reserve")

      if target != "purchase" do
        save!(
          actor,
          id,
          "order",
          %{"reference" => "PEDIDO-SIMULADO-#{index}"},
          key <> ":order-values"
        )

        transition!(actor, id, "order", key <> ":order")

        save!(
          actor,
          id,
          "delivery",
          %{"received" => if(target == "complete", do: index + 3, else: 2)},
          key <> ":delivery"
        )

        if target == "complete", do: transition!(actor, id, "finish", key <> ":finish")
      end
    end
  end

  defp save!(actor, id, section_key, values, key) do
    data = ok!(WorkflowRuntime.get(actor, id))
    section = Enum.find(data.sections, &(&1.key == section_key))

    ok!(
      WorkflowRuntime.command(actor, %{
        "operation" => "save_section",
        "ticket_id" => id,
        "section" => section_key,
        "values" => values,
        "key" => key,
        "expected_stage_revision" => data.ticket.stage_revision,
        "expected_section_revision" => section.revision
      })
    )
  end

  defp transition!(actor, id, edge, key, reason \\ nil) do
    data = ok!(WorkflowRuntime.get(actor, id))

    ok!(
      WorkflowRuntime.command(actor, %{
        "operation" => "transition",
        "ticket_id" => id,
        "transition" => edge,
        "key" => key,
        "reason" => reason,
        "expected_revision" => data.ticket.revision,
        "section_revisions" => Map.new(data.sections, &{&1.key, &1.revision})
      })
    )
  end

  defp inventory(operator, org, current, actors) do
    versions =
      operator.all(
        from v in Version,
          where: v.workflow_id == ^current.workflow_id,
          order_by: v.number
      )

    %{
      database: operator.config()[:database],
      organization: org.slug,
      scenario: @scenario,
      versions:
        Enum.map(versions, fn version ->
          counts =
            operator.all(
              from t in Ticket,
                where: t.workflow_version_id == ^version.id,
                group_by: t.stage,
                select: {t.stage, count(t.id)}
            )
            |> Map.new()

          %{
            workflow: "requisition",
            version: version.number,
            version_id: version.id,
            primary: version.id == current.id,
            total: Enum.sum(Map.values(counts)),
            stages: counts
          }
        end),
      roles:
        Enum.map(actors, fn actor ->
          %{
            email: actor.user.email,
            role: actor.role,
            grants: Enum.map(actor.grants, &Map.take(&1, [:role, :department_id]))
          }
        end)
    }
  end

  defp ok!({:ok, value}), do: value
  defp ok!({:error, reason}), do: raise("Demo fixture failed: #{inspect(reason)}")
end
