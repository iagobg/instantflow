defmodule InstantflowWeb.TeamLive do
  use InstantflowWeb, :live_view
  alias Instantflow.{Access, Identity}
  alias Instantflow.Identity.Invitation

  def mount(_params, _session, socket) do
    if Identity.admin?(socket.assigns.current_scope) do
      {:ok,
       socket
       |> assign(
         page_title: "Equipe",
         code: nil,
         expires_at: nil,
         grant_form: to_form(%{}, as: :grant),
         role_options: role_options(),
         member_options:
           Enum.map(Identity.list_staff(socket.assigns.current_scope), &{&1.user.name, &1.id}),
         departments:
           Enum.map(Identity.departments(socket.assigns.current_scope), &{&1.name, &1.id}),
         form: to_form(Invitation.changeset(%Invitation{}, %{}))
       )
       |> stream(:staff, Identity.list_staff(socket.assigns.current_scope))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Apenas administradores podem gerenciar a equipe.")
       |> push_navigate(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}")}
    end
  end

  def handle_event("grant", %{"grant" => params}, socket) do
    with {member_id, ""} <- Integer.parse(params["membership_id"] || ""),
         {department_id, ""} <- Integer.parse(params["department_id"] || ""),
         {:ok, _} <-
           Access.grant(socket.assigns.current_scope, member_id, department_id, params["role"]) do
      {:noreply,
       socket
       |> put_flash(:info, "Permissão local concedida.")
       |> stream(:staff, Identity.list_staff(socket.assigns.current_scope), reset: true)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível alterar esta permissão.")}
    end
  end

  def handle_event("revoke-grant", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         {:ok, _} <- Access.revoke(socket.assigns.current_scope, id) do
      {:noreply,
       socket
       |> put_flash(:info, "Permissão local removida.")
       |> stream(:staff, Identity.list_staff(socket.assigns.current_scope), reset: true)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível alterar esta permissão.")}
    end
  end

  def handle_event("revoke-member", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         {:ok, _} <- Identity.revoke(socket.assigns.current_scope, id) do
      {:noreply,
       socket
       |> put_flash(:info, "Acesso à organização revogado.")
       |> stream(:staff, Identity.list_staff(socket.assigns.current_scope), reset: true)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Não foi possível revogar este acesso.")}
    end
  end

  def handle_event("invite", %{"invitation" => params}, socket) do
    case Identity.invite(socket.assigns.current_scope, params) do
      {:ok, result} ->
        {:noreply,
         assign(socket,
           code: result.token,
           expires_at:
             Instantflow.LocalTime.format(
               result.invitation.expires_at,
               socket.assigns.current_scope.organization.timezone
             ),
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

  defp role_options,
    do: [
      {"Professor", "teacher"},
      {"Admissões", "admissions"},
      {"Coordenação", "head"},
      {"Financeiro", "finance"},
      {"Alocação financeira", "finance_allocator"},
      {"Estorno financeiro", "finance_reverser"},
      {"Operações", "operations"},
      {"TI", "it"},
      {"Direção", "dean"},
      {"Orientação", "counselor"},
      {"Python: autoria", "python_author"},
      {"Python: revisão e ativação", "python_reviewer"},
      {"Python: vincular ao fluxo", "python_binder"},
      {"Python: executar", "python_execute"},
      {"Python: consultar código", "python_source"}
    ]

  defp role_label(role),
    do: Enum.find_value(role_options(), role, fn {label, key} -> if key == role, do: label end)

  defp department_label(departments, id),
    do: Enum.find_value(departments, "", fn {label, key} -> if key == id, do: label end)

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
                    {case member.role do
                      "admin" -> "Administrador"
                      "external" -> "Participante externo"
                      "parent" -> "Responsável"
                      _ -> "Colaborador"
                    end}
                    <div :for={grant <- member.grants} id={"grant-#{grant.id}"} class="grant-row">
                      <small>{role_label(grant.role)} · {department_label(
                        @departments,
                        grant.department_id
                      )}</small>
                      <button
                        class="btn"
                        phx-click="revoke-grant"
                        phx-value-id={grant.id}
                        aria-label={"Remover permissão #{role_label(grant.role)} de #{member.user.name}"}
                      >Remover</button>
                    </div>
                    <button
                      :if={member.active and member.id != @current_scope.id}
                      id={"revoke-member-#{member.id}"}
                      class="btn"
                      phx-click="revoke-member"
                      phx-value-id={member.id}
                      data-confirm="Revogar o acesso desta pessoa à organização?"
                    >Revogar acesso</button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <section class="card">
          <h2>Permissões por departamento</h2>
          <p>
            Cada perfil se aplica ao departamento escolhido. A administração não concede acesso automático às solicitações.
          </p>
          <.form for={@grant_form} id="grant-form" phx-submit="grant">
            <.input
              field={@grant_form[:membership_id]}
              label="Pessoa"
              type="select"
              options={@member_options}
              prompt="Selecione"
              required
            />
            <.input
              field={@grant_form[:department_id]}
              label="Departamento"
              type="select"
              options={@departments}
              prompt="Selecione"
              required
            />
            <.input
              field={@grant_form[:role]}
              label="Perfil local"
              type="select"
              options={@role_options}
              prompt="Selecione"
              required
            />
            <button class="btn primary" id="grant-access" phx-disable-with="Concedendo…">Conceder permissão</button>
          </.form>
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
              options={[
                {"Colaborador", "staff"},
                {"Administrador", "admin"},
                {"Participante externo", "external"}
              ]}
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
