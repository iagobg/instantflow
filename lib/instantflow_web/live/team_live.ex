defmodule InstantflowWeb.TeamLive do
  use InstantflowWeb, :live_view
  alias Instantflow.Identity
  alias Instantflow.Identity.Invitation

  def mount(_params, _session, socket) do
    if Identity.admin?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(
         page_title: "Equipe",
         code: nil,
         expires_at: nil,
         departments: Enum.map(Identity.departments(), &{&1.name, &1.id}),
         form: to_form(Invitation.changeset(%Invitation{}, %{}))
       )
       |> stream(:staff, Identity.list_staff(socket.assigns.current_scope))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Apenas administradores podem gerenciar a equipe.")
       |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    case Identity.invite(socket.assigns.current_scope, params) do
      {:ok, result} ->
        {:noreply,
         assign(socket,
           code: result.token,
           expires_at: Instantflow.LocalTime.format(result.invitation.expires_at),
           form: to_form(Invitation.changeset(%Invitation{}, %{}))
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset), code: nil)}

      {:error, :forbidden} ->
        {:noreply,
         socket
         |> put_flash(:error, "Seu acesso foi alterado. Entre novamente.")
         |> push_navigate(to: ~p"/entrar")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Selecione um departamento válido.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">ADMINISTRAÇÃO</p><h1>Equipe e convites</h1><p>
            Conecte as pessoas que fazem a escola acontecer.
          </p>
        </div>
      </div>
      <div class="team-grid">
        <section class="card">
          <h2>Pessoas da organização</h2><p>Acesso interno por departamento.</p><div class="table-scroll">
            <table>
              <thead>
                <tr>
                  <th scope="col">Pessoa</th><th scope="col">Departamento</th><th scope="col">
                    Perfil
                  </th>
                </tr>
              </thead><tbody id="staff" phx-update="stream">
                <tr :for={{id, member} <- @streams.staff} id={id}>
                  <td>
                    <strong>{member.user.name}</strong><small>{member.user.email}</small><span
                      :if={!member.active or !member.user.active}
                      class="badge"
                    >Acesso inativo</span>
                  </td><td>{member.department.name}</td><td>
                    {if member.role == "admin", do: "Administrador", else: "Colaborador"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <section class="card">
          <span class="badge sim">◇ Envio simulado</span><h2>Convidar uma pessoa</h2><p>
            O convite é válido por 48 horas e pode ser usado uma única vez.
          </p><.form for={@form} id="invite-form" phx-submit="invite">
            <.input
              field={@form[:email]}
              type="email"
              label="E-mail institucional"
              required
              maxlength="160"
            /><.input
              name="invitation[department_id]"
              id="invitation_department_id"
              type="select"
              label="Departamento"
              options={@departments}
              prompt="Selecione um departamento"
              value=""
              required
            /><.input
              field={@form[:role]}
              type="select"
              label="Perfil de acesso"
              options={[{"Colaborador", "staff"}, {"Administrador", "admin"}]}
              required
            /><button id="create-invite" class="btn primary" phx-disable-with="Gerando convite…">Gerar convite</button>
          </.form><div :if={@code} id="invitation-result" role="status" class="code-result">
            <strong>Convite criado</strong><p>
              Compartilhe este código no ambiente de teste. Nenhum e-mail foi enviado.
            </p><p>Válido até {@expires_at}.</p><code id="invitation-code">{@code}</code><.link href={
              ~p"/convite"
            }>Abrir aceitação de convite <.icon name="hero-arrow-right" /></.link>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
