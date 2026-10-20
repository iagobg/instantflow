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
end

GenServer.stop(operator_pid)

IO.puts(
  "Duas escolas preparadas. Ana é administradora na Horizonte e colaboradora na Aurora. Senhas existentes e dados anteriores foram preservados."
)
