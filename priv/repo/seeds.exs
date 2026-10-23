import Ecto.Query

if Application.get_env(:instantflow, :environment) == :prod,
  do: raise("Seeds de demonstração são proibidos em produção.")

password = System.fetch_env!("DEMO_PASSWORD")

unless String.length(password) in 12..128,
  do: raise("DEMO_PASSWORD deve ter entre 12 e 128 caracteres.")

{:ok, operator_pid} = Instantflow.OperatorRepo.start_link()
alias Instantflow.OperatorRepo, as: OperatorRepo
alias Instantflow.Identity.{Department, Membership, Organization, User}
alias Instantflow.{Identity, WorkflowCatalog, WorkflowRuntime}
alias Instantflow.WorkflowCatalog.Workflow

ensure_example = fn actor, key, bindings ->
  workflow = OperatorRepo.get_by(Workflow, organization_id: actor.organization_id, key: key)

  latest =
    workflow &&
      OperatorRepo.one(
        from v in Instantflow.WorkflowCatalog.Version,
          where: v.workflow_id == ^workflow.id,
          order_by: [desc: v.number],
          limit: 1
      )

  if is_nil(latest) or
       Instantflow.Tenant.read(actor, fn _ ->
         Instantflow.WorkflowCatalog.Retirement.retired?(latest.id)
       end) do
    {:ok, _} =
      WorkflowCatalog.publish(
        actor,
        Instantflow.Examples.definition(key),
        bindings,
        if(latest, do: latest.number, else: 0)
      )
  end
end

for {slug, school} <- [
      {"horizonte", "Escola Horizonte (fictícia)"},
      {"aurora", "Escola Aurora (fictícia)"}
    ] do
  organization =
    OperatorRepo.get_by(Organization, slug: slug) ||
      OperatorRepo.insert!(%Organization{slug: slug, name: school})

  entries =
    if slug == "horizonte",
      do: [
        {"admin@escola.example", "Ana Martins", "Administração", "admin"},
        {"secretaria@escola.example", "Bruno Lima", "Secretaria", "staff"},
        {"docente@escola.example", "Clara Oliveira", "Docência", "staff"},
        {"coordenacao@escola.example", "Daniel Costa", "Coordenação", "staff"},
        {"financeiro@escola.example", "Elisa Souza", "Financeiro", "staff"},
        {"operacoes@escola.example", "Felipe Santos", "Operações", "staff"},
        {"ti@escola.example", "Gabriela Rocha", "Tecnologia", "staff"},
        {"direcao@escola.example", "Hugo Almeida", "Direção", "staff"},
        {"orientacao@escola.example", "Isabela Ribeiro", "Orientação", "staff"}
      ],
      else: [
        {"gestao@aurora.example", "Joana Teixeira", "Administração", "admin"},
        {"admin@escola.example", "Ana Martins", "Docência", "staff"},
        {"financeiro@aurora.example", "Luís Andrade", "Financeiro", "staff"}
      ]

  OperatorRepo.transaction(fn ->
    for {email, name, department_name, role} <- entries do
      OperatorRepo.insert!(%Department{organization_id: organization.id, name: department_name},
        on_conflict: :nothing
      )

      department =
        OperatorRepo.get_by!(Department, organization_id: organization.id, name: department_name)

      user =
        OperatorRepo.get_by(User, email: email) ||
          OperatorRepo.insert!(
            User.changeset(%User{email: email}, %{name: name, password: password})
          )

      OperatorRepo.insert!(
        %Membership{
          organization_id: organization.id,
          department_id: department.id,
          user_id: user.id,
          role: role
        },
        on_conflict: :nothing
      )
    end
  end)

  admin_email = if slug == "horizonte", do: "admin@escola.example", else: "gestao@aurora.example"
  admin = Identity.scope(OperatorRepo.get_by!(User, email: admin_email).id, organization.id)

  if admin &&
       !OperatorRepo.get_by(Workflow, organization_id: organization.id, key: "simple_approval") do
    definition =
      File.read!(Application.app_dir(:instantflow, "priv/workflows/simple_approval.json"))
      |> Jason.decode!()

    finance =
      OperatorRepo.get_by!(Department, organization_id: organization.id, name: "Financeiro")

    bindings = %{
      "roles" => %{"requester" => ["admin", "staff"], "reviewer" => ["staff"]},
      "departments" => %{"review_department" => finance.id}
    }

    {:ok, version} = WorkflowCatalog.publish(admin, definition, bindings)

    requester_email =
      if slug == "horizonte", do: "docente@escola.example", else: "admin@escola.example"

    requester =
      Identity.scope(OperatorRepo.get_by!(User, email: requester_email).id, organization.id)

    {:ok, result} =
      WorkflowRuntime.command(requester, %{
        "operation" => "create",
        "workflow_id" => version.workflow_id,
        "key" => "seed:sample-request"
      })

    {:ok, _} =
      WorkflowRuntime.command(requester, %{
        "operation" => "save_section",
        "ticket_id" => result["ticket_id"],
        "key" => "seed:sample-values",
        "section" => "request",
        "expected_stage_revision" => 1,
        "expected_section_revision" => 1,
        "values" => %{
          "summary" => "Materiais para oficina de leitura",
          "justification" => "Atividade pedagógica fictícia da demonstração."
        }
      })
  end

  # Install independent copies and synthetic families through the same guarded APIs as the UI.
  enrollment_departments =
    for {key, name} <- [
          {"admissions", "Secretaria"},
          {"academic", "Coordenação"},
          {"finance", "Financeiro"},
          {"it", "Tecnologia"}
        ],
        into: %{} do
      department =
        OperatorRepo.get_by(Department, organization_id: organization.id, name: name) ||
          OperatorRepo.insert!(%Department{organization_id: organization.id, name: name})

      {key <> "_department", department.id}
    end

  {:ok, _} =
    Instantflow.Access.grant(
      admin,
      admin.id,
      enrollment_departments["admissions_department"],
      "admissions"
    )

  if slug == "horizonte" do
    for {email, binding, role} <- [
          {"secretaria@escola.example", "admissions", "admissions"},
          {"coordenacao@escola.example", "academic", "head"},
          {"financeiro@escola.example", "finance", "finance"},
          {"ti@escola.example", "it", "it"}
        ] do
      member = Identity.scope(OperatorRepo.get_by!(User, email: email).id, organization.id)

      {:ok, _} =
        Instantflow.Access.grant(
          admin,
          member.id,
          enrollment_departments[binding <> "_department"],
          role
        )
    end
  end

  enrollment_bindings = %{
    "roles" => %{
      "guardian" => ["external", "parent"],
      "admissions" => ["admin", "admissions"],
      "academic" => ["head"],
      "finance" => ["finance"],
      "it" => ["it"]
    },
    "departments" => enrollment_departments
  }

  ensure_example.(admin, "enrollment", enrollment_bindings)

  workflow = OperatorRepo.get_by!(Workflow, organization_id: organization.id, key: "enrollment")

  for {key, email} <- [
        {"a", "responsavel.a@escola.example"},
        {"b", "responsavel.b@escola.example"}
      ] do
    {:ok, result} =
      WorkflowRuntime.command(admin, %{
        "operation" => "create",
        "workflow_id" => workflow.id,
        "key" => "seed:participant-enrollment:" <> key
      })

    existing = OperatorRepo.get_by(User, email: email)

    member =
      existing &&
        OperatorRepo.get_by(Membership, user_id: existing.id, organization_id: organization.id)

    parent =
      if member do
        Identity.scope(existing.id, organization.id)
      else
        {:ok, invitation} =
          Identity.invite(admin, %{
            "email" => email,
            "role" => "external",
            "department_id" => admin.department_id
          })

        {:ok, user} =
          Identity.accept_invitation(
            invitation.token,
            %{"name" => "Responsável fictício " <> String.upcase(key), "password" => password},
            existing
          )

        Identity.scope(user.id, organization.id)
      end

    relationship =
      OperatorRepo.get_by(Instantflow.Participants.Relationship,
        ticket_id: result["ticket_id"],
        membership_id: parent.id,
        relationship: "family"
      )

    relationship =
      if relationship do
        relationship
      else
        {:ok, created} =
          Instantflow.Participants.command(admin, %{
            "operation" => "create",
            "ticket_id" => result["ticket_id"],
            "membership_id" => parent.id,
            "relationship" => "family",
            "expected_revision" => 0,
            "key" => "seed:family:" <> key
          })

        OperatorRepo.get!(Instantflow.Participants.Relationship, created["relationship_id"])
      end

    unless relationship.status == "verified" do
      {:ok, _} =
        Instantflow.Participants.command(admin, %{
          "operation" => "verify",
          "ticket_id" => result["ticket_id"],
          "membership_id" => parent.id,
          "relationship" => "family",
          "expected_revision" => relationship.revision,
          "key" => "seed:verify-family:" <> key
        })
    end
  end

  # Shared within each school only; the same labels never bind another organization's funds.
  finance_departments =
    for {key, name} <- [
          {"head", "Coordenação"},
          {"finance", "Financeiro"},
          {"operations", "Operações"},
          {"safety", "Direção"}
        ],
        into: %{} do
      department =
        OperatorRepo.get_by(Department, organization_id: organization.id, name: name) ||
          OperatorRepo.insert!(%Department{organization_id: organization.id, name: name})

      {key <> "_department", department.id}
    end

  finance_department = finance_departments["finance_department"]
  {:ok, _} = Instantflow.Access.grant(admin, admin.id, finance_department, "finance_allocator")

  account =
    OperatorRepo.get_by(Instantflow.Finance.Account,
      organization_id: organization.id,
      department_id: finance_department,
      name: "Atividades e materiais"
    ) ||
      case Instantflow.Finance.create_account(admin, finance_department, "Atividades e materiais") do
        {:ok, account} -> account
      end

  {:ok, _} =
    Instantflow.Finance.allocate(
      admin,
      account.id,
      100_000,
      "Dotação inicial fictícia",
      "seed:budget:initial"
    )

  staff_roles =
    if slug == "horizonte",
      do: [
        {"docente@escola.example", "head", "teacher"},
        {"coordenacao@escola.example", "head", "head"},
        {"financeiro@escola.example", "finance", "finance"},
        {"operacoes@escola.example", "operations", "operations"},
        {"direcao@escola.example", "safety", "dean"},
        {"direcao@escola.example", "finance", "finance_reverser"}
      ],
      else: [
        {"admin@escola.example", "head", "teacher"},
        {"gestao@aurora.example", "head", "head"},
        {"gestao@aurora.example", "operations", "operations"},
        {"gestao@aurora.example", "safety", "dean"},
        {"gestao@aurora.example", "finance", "finance_reverser"},
        {"financeiro@aurora.example", "finance", "finance"}
      ]

  for {email, department, role} <- staff_roles do
    member = Identity.scope(OperatorRepo.get_by!(User, email: email).id, organization.id)

    {:ok, _} =
      Instantflow.Access.grant(
        admin,
        member.id,
        finance_departments[department <> "_department"],
        role
      )
  end

  for template <- ~w(requisition field_trip) do
    ensure_example.(admin, template, %{
      "roles" => %{
        "requester" => ["teacher"],
        "head" => ["head"],
        "finance" => ["finance"],
        "operations" => ["operations"],
        "safety" => ["dean"],
        "reverser" => ["finance_reverser"]
      },
      "departments" => finance_departments,
      "budgets" => %{"shared_budget" => account.id}
    })
  end

  support_department =
    OperatorRepo.get_by(Department, organization_id: organization.id, name: "Orientação") ||
      OperatorRepo.insert!(%Department{organization_id: organization.id, name: "Orientação"})

  ensure_example.(admin, "incident", %{
    "roles" => %{"teacher" => ["teacher"], "dean" => ["dean"], "counselor" => ["counselor"]},
    "departments" => %{
      "dean_department" => finance_departments["safety_department"],
      "support_department" => support_department.id
    }
  })

  if slug == "horizonte" do
    counselor =
      Identity.scope(
        OperatorRepo.get_by!(User, email: "orientacao@escola.example").id,
        organization.id
      )

    {:ok, _} = Instantflow.Access.grant(admin, counselor.id, support_department.id, "counselor")
  else
    {:ok, _} = Instantflow.Access.grant(admin, admin.id, support_department.id, "counselor")
  end
end

GenServer.stop(operator_pid)

IO.puts(
  "Duas escolas preparadas. Ana é administradora na Horizonte e colaboradora na Aurora. Senhas existentes e dados anteriores foram preservados."
)
