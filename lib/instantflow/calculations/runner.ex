defmodule Instantflow.Calculations.Runner do
  @moduledoc "Bounded authenticated broker protocol. No shell or Python interpreter in Phoenix."
  def request(script, input, id, fence) do
    %{
      "organization_id" => script.organization_id,
      "run_id" => id,
      "fence" => fence,
      "runtime" => script.runtime,
      "source" => script.source,
      "input" => input
    }
  end

  def identity?(request, response),
    do:
      is_map(response) and
        Map.take(request, ~w(organization_id run_id fence)) ==
          Map.take(response, ~w(organization_id run_id fence))

  def execute(request) do
    adapter = Application.get_env(:instantflow, :calculation_runner, __MODULE__)
    if adapter == __MODULE__, do: http(request), else: adapter.execute(request)
  end

  defp http(request) do
    url = Application.get_env(:instantflow, :calculation_broker_url)
    token = Application.get_env(:instantflow, :calculation_broker_token)

    with false <- Instantflow.Repo.in_transaction?(),
         true <-
           is_binary(url) and String.starts_with?(url, "http://127.0.0.1:") and is_binary(token) and
             byte_size(token) >= 32,
         {:ok, %{status: 200, body: body}} <-
           Req.post(url <> "/run",
             json: request,
             auth: {:bearer, token},
             retry: false,
             redirect: false,
             decode_body: false,
             receive_timeout: 10_000,
             connect_options: [timeout: 1000],
             into: fn {:data, chunk}, {req, resp} ->
               if byte_size(resp.body || "") + byte_size(chunk) <= 32_768,
                 do: {:cont, {req, %{resp | body: (resp.body || "") <> chunk}}},
                 else: {:halt, {req, %{resp | status: 502, body: ""}}}
             end
           ),
         {:ok, response} <- Instantflow.WorkflowCatalog.Interchange.decode(body),
         true <- identity?(request, response) do
      {:ok, response}
    else
      _ -> {:error, :runner_unavailable}
    end
  rescue
    _ -> {:error, :runner_unavailable}
  end
end
