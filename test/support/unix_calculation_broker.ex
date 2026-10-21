defmodule Instantflow.UnixCalculationBroker do
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def init(opts) do
    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {:local, String.to_charlist(opts[:path])}])

    send(self(), :accept)
    {:ok, %{listener: socket, observer: opts[:observer]}}
  end

  def handle_info(:accept, state) do
    {:ok, socket} = :gen_tcp.accept(state.listener)
    {:ok, raw} = :gen_tcp.recv(socket, 0, 5000)
    [headers, body] = String.split(raw, "\r\n\r\n", parts: 2)
    [_, length] = Regex.run(~r/content-length: (\d+)/i, headers)
    body = receive_body(socket, body, String.to_integer(length))
    request = Jason.decode!(body)
    send(state.observer, {:unix_request, request})

    response =
      request
      |> Map.take(~w(organization_id run_id fence))
      |> Map.merge(%{"status" => "succeeded", "output" => %{"total" => 1}})
      |> Jason.encode!()

    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n" <>
          response
      )

    :gen_tcp.close(socket)
    send(self(), :accept)
    {:noreply, state}
  end

  defp receive_body(_, body, size) when byte_size(body) >= size, do: body

  defp receive_body(socket, body, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    receive_body(socket, body <> chunk, size)
  end
end
