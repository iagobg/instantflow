alias Instantflow.Repo
alias Instantflow.Identity.{Department, Membership, Organization, User}

if Application.get_env(:instantflow, :environment) == :prod do
  raise "As contas de demonstração não podem ser criadas em produção."
end

password = System.fetch_env!("DEMO_PASSWORD")

unless String.length(password) in 12..128,
  do: raise("DEMO_PASSWORD deve ter entre 12 e 128 caracteres.")

Repo.transaction(fn ->
  Repo.insert!(%Organization{id: 1, name: "Escola Horizonte (fictícia)"}, on_conflict: :nothing)

  for {slug, name, department, role} <- [
        {"admin", "Ana Martins", "Administração", "admin"},
        {"secretaria", "Bruno Lima", "Secretaria", "staff"},
        {"docente", "Clara Oliveira", "Docência", "staff"},
        {"coordenacao", "Daniel Costa", "Coordenação", "staff"},
        {"financeiro", "Elisa Souza", "Financeiro", "staff"},
        {"operacoes", "Felipe Santos", "Operações", "staff"},
        {"ti", "Gabriela Rocha", "Tecnologia", "staff"},
        {"direcao", "Hugo Almeida", "Direção", "staff"},
        {"orientacao", "Isabela Ribeiro", "Orientação", "staff"}
      ] do
    Repo.insert!(%Department{organization_id: 1, name: department}, on_conflict: :nothing)
    department = Repo.get_by!(Department, organization_id: 1, name: department)
    email = slug <> "@escola.example"

    user =
      Repo.get_by(User, email: email) ||
        Repo.insert!(User.changeset(%User{email: email}, %{name: name, password: password}))

    Repo.insert!(
      %Membership{organization_id: 1, department_id: department.id, user_id: user.id, role: role},
      on_conflict: :nothing
    )
  end
end)

IO.puts(
  "Demonstração preparada. Administração: admin@escola.example. Senha: valor de DEMO_PASSWORD."
)
