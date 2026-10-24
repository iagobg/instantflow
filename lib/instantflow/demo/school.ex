defmodule Instantflow.Demo.School do
  @moduledoc "D01 synthetic installation data; all case mutations use shared runtime commands."
  import Ecto.Query
  alias Instantflow.{Finance, Identity, Repo, Tenant, WorkflowRuntime}
  import Instantflow.Demo.Scenario
  alias Instantflow.Identity.{Department, Organization}
  alias Instantflow.WorkflowCatalog.Version
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

    version = version!(presenter, "requisition", bindings)

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

    {extra_versions, extra_actors} =
      Instantflow.Demo.SchoolScenarios.install!(
        operator,
        org,
        departments,
        presenter,
        author,
        bindings,
        password
      )

    inventory(
      operator,
      org,
      [version | extra_versions],
      [staff, author] ++ extra_actors
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

  defp inventory(operator, org, current_versions, actors) do
    workflow_ids = Enum.map(current_versions, & &1.workflow_id)
    primary_ids = Enum.map(current_versions, & &1.id)

    versions =
      operator.all(
        from v in Version,
          where: v.workflow_id in ^workflow_ids,
          order_by: [v.workflow_id, v.number]
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
            workflow: version.definition["template_key"],
            version: version.number,
            version_id: version.id,
            primary: version.id in primary_ids,
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
end
