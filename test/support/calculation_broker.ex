defmodule Instantflow.CalculationBroker do
  @behaviour Plug
  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 65_536)
    request = Jason.decode!(body)

    send(
      opts[:observer],
      {:broker_request, request, Plug.Conn.get_req_header(conn, "authorization")}
    )

    identity = Map.take(request, ~w(organization_id run_id fence))

    response =
      case opts[:mode] do
        :oversized ->
          String.duplicate("x", 65_536)

        :wrong_tenant ->
          Jason.encode!(
            Map.merge(identity, %{
              "organization_id" => 999,
              "status" => "succeeded",
              "output" => %{"total" => 1}
            })
          )

        _ ->
          Jason.encode!(
            Map.merge(identity, %{"status" => "succeeded", "output" => %{"total" => 1}})
          )
      end

    Plug.Conn.send_resp(conn, 200, response)
  end
end
