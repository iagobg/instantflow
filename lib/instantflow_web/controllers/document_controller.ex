defmodule InstantflowWeb.DocumentController do
  use InstantflowWeb, :controller

  def download(conn, %{"key" => key}) do
    case Instantflow.PrivateDocuments.download(conn.assigns.current_scope, key) do
      {:ok, file} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
        |> send_download({:binary, file.content},
          filename: file.filename,
          content_type: "application/octet-stream"
        )

      _ ->
        send_resp(conn, 404, "Documento não encontrado.")
    end
  end
end
