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

  defp local_url?(url) when is_binary(url) do
    uri = URI.parse(url)

    uri.scheme == "http" and uri.host == "127.0.0.1" and is_integer(uri.port) and
      uri.port in 1..65535 and uri.userinfo == nil and uri.path in [nil, ""] and
      uri.query == nil and uri.fragment == nil
  end

  defp local_url?(_), do: false

  defp http(request) do
    url = Application.get_env(:instantflow, :calculation_broker_url)
    token = Application.get_env(:instantflow, :calculation_broker_token)
    socket = Application.get_env(:instantflow, :calculation_broker_socket)

    with false <- Instantflow.Repo.in_transaction?(),
         true <-
           local_url?(url) and
             (is_nil(socket) or (is_binary(socket) and Path.type(socket) == :absolute)) and
             is_binary(token) and byte_size(token) >= 32,
         {:ok, %{status: 200, body: body}} <-
           Req.post(url <> "/run",
             json: request,
             unix_socket: socket,
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
