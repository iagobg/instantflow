defmodule Mix.Tasks.Instantflow.Organizations do
  use Mix.Task
  @shortdoc "Operator-only provisioning or lifecycle change (separate database credentials)"
  def run(args) do
    {opts, args, []} = OptionParser.parse(args, strict: [operator: :string])
    operator = Keyword.fetch!(opts, :operator)
    Mix.Task.run("app.start")
    {:ok, pid} = Instantflow.OperatorRepo.start_link()

    result =
      case args do
        ["provision", slug, name, email, key] ->
          Instantflow.Organizations.Operator.provision(operator, slug, name, email, key)

        ["suspend", slug, key] ->
          Instantflow.Organizations.Operator.set_status(operator, slug, "suspended", key)

        ["resume", slug, key] ->
          Instantflow.Organizations.Operator.set_status(operator, slug, "active", key)

        ["reissue-bootstrap", slug, email, key] ->
          Instantflow.Organizations.Operator.reissue_bootstrap(operator, slug, email, key)

        _ ->
          Mix.raise(
            "Use provision SLUG NAME EMAIL KEY, suspend SLUG KEY or resume SLUG KEY, with --operator NAME"
          )
      end

    case result do
      {:ok, %{token: token}} when is_binary(token) ->
        Mix.shell().info("Convite inicial (exibido uma vez): #{token}")

      {:ok, _} ->
        Mix.shell().info(
          "Operação registrada. Nenhuma senha ou concessão existente foi alterada."
        )

      {:error, reason} ->
        Mix.raise("Operação não concluída: #{inspect(reason)}")
    end

    GenServer.stop(pid)
  end
end
