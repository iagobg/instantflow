defmodule InstantflowWeb.ProcessLive do
  use InstantflowWeb, :live_view
  import InstantflowWeb.ProcessComponents
  import InstantflowWeb.ProcessRoutes

  alias Instantflow.{Operations, WorkflowCatalog, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.{Workspaces, Views}

  def mount(_, _, socket) do
    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          Instantflow.PubSub,
          Instantflow.Finance.topic(socket.assigns.current_scope.organization_id)
        )

    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          Instantflow.PubSub,
          WorkflowRuntime.list_topic(socket.assigns.current_scope)
        )

    if connected?(socket),
      do:
        Phoenix.PubSub.subscribe(
          Instantflow.PubSub,
          Operations.topic(socket.assigns.current_scope)
        )

    {:ok,
     socket
     |> assign(
       page_title: "Processo",
       process_name: "Processo",
       process_description: "",
       pages: [],
       blocks: [],
       page_key: "overview",
       record_filters: %{},
       record_view: nil,
       finance_account_form: to_form(%{}, as: :finance_account),
       finance_allocation_form: to_form(%{}, as: :finance_allocation),
       record_form: to_form(%{}, as: :record_filter),
       workflow_id: nil,
       labels: Instantflow.WorkflowCatalog.Workspaces.labels(%{}),
       date: Operations.today(socket.assigns.current_scope),
       visit_id: nil,
       visit: nil,
       operational_archived?: false,
       current_workspace?: true,
       cart: %{},
       print_ticket: nil,
       command_key: Ecto.UUID.generate(),
       product_id: nil,
       product_revision: nil,
       product_form:
         to_form(%{"category" => "Geral", "destination" => "", "active" => true},
           as: :product
         ),
       resource_form: to_form(%{}, as: :resource),
       open_form:
         to_form(
           %{"business_date" => Date.to_iso8601(Operations.today(socket.assigns.current_scope))},
           as: :visit
         ),
       item_form: to_form(%{"quantity" => "1"}, as: :item),
       batch_form: to_form(%{}, as: :batch),
       checkout_form: to_form(%{}, as: :checkout),
       day_form:
         to_form(%{"date" => Date.to_iso8601(Operations.today(socket.assigns.current_scope))},
           as: :day
         )
     )
     |> stream(:cart_items, [])}
  end

  def handle_params(params, _, socket) do
    id = number(params["id"])

    workflow_id =
      number(params["workflow_id"]) ||
        Operations.workflow_for_visit(socket.assigns.current_scope, id) ||
        Operations.default_workflow(socket.assigns.current_scope)

    case page_version(socket.assigns.current_scope, workflow_id, id) do
      nil ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos"
         )}

      version ->
        pages = Workspaces.pages(version.definition)

        page =
          Enum.find(pages, &(&1["key"] == params["page_key"])) ||
            if(is_nil(params["page_key"]), do: hd(pages))

        cond do
          page && Map.has_key?(page, "participant") ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{workflow_id}/participacao/#{page["key"]}"
             )}

          page ->
            {:noreply,
             socket
             |> assign(
               visit_id: id,
               workflow_id: workflow_id,
               page_key: page["key"],
               cart:
                 if(socket.assigns.workflow_id == workflow_id and socket.assigns.visit_id == id,
                   do: socket.assigns.cart,
                   else: %{}
                 ),
               print_ticket: nil,
               batch_form: to_form(%{}, as: :batch)
             )
             |> then(fn state ->
               stream(state, :cart_items, Map.values(state.assigns.cart), reset: true)
             end)
             |> load()}

          true ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{workflow_id}"
             )}
        end
    end
  end

  def handle_event("record-filters", %{"record_filter" => params}, socket) do
    {:noreply,
     socket
     |> assign(
       record_filters: Map.take(params, ~w(query stage fields assigned_to)),
       record_view: params["view"],
       record_form: to_form(params, as: :record_filter)
     )
     |> load()}
  end

  def handle_event("record-page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:record_filters, Map.put(socket.assigns.record_filters, "page", page))
     |> load()}
  end

  def handle_event("finance-create-account", %{"finance_account" => params}, socket) do
    result =
      Instantflow.Finance.create_account(
        socket.assigns.current_scope,
        number(params["department_id"]),
        params["name"]
      )

    {:noreply, finance_result(socket, result)}
  end

  def handle_event("finance-allocate", %{"finance_allocation" => params}, socket) do
    result =
      Instantflow.Finance.allocate(
        socket.assigns.current_scope,
        number(params["account_id"]),
        number(params["amount"]),
        params["reason"],
        socket.assigns.command_key
      )

    {:noreply, finance_result(socket, result)}
  end

  def handle_event("record-create", _, socket) do
    case WorkflowRuntime.command(socket.assigns.current_scope, %{
           "operation" => "create",
           "workflow_id" => socket.assigns.workflow_id,
           "key" => socket.assigns.command_key
         }) do
      {:ok, result} ->
        {:noreply,
         socket
         |> assign(:command_key, Ecto.UUID.generate())
         |> push_navigate(
           to:
             ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos/#{socket.assigns.workflow_id}/registros/#{result["ticket_id"]}"
         )}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Seu acesso ou a configuração do processo não permite iniciar este registro."
         )}
    end
  end

  def handle_event("save-product", %{"product" => params}, socket) do
    case Operations.parse_money(params["price"]) do
      {:ok, price} ->
        command = %{
          "operation" => "save_product",
          "name" => params["name"],
          "category" => params["category"],
          "destination" => params["destination"],
          "price" => price,
          "active" => params["active"] == "true"
        }

        command =
          if socket.assigns.product_id,
            do:
              Map.merge(command, %{
                "id" => socket.assigns.product_id,
                "revision" => socket.assigns.product_revision
              }),
            else: command

        case run(socket, command) do
          {:ok, socket, _} ->
            {:noreply,
             socket
             |> assign(
               product_id: nil,
               product_revision: nil,
               product_form:
                 to_form(
                   %{
                     "category" => params["category"],
                     "destination" => params["destination"],
                     "active" => true
                   },
                   as: :product
                 )
             )
             |> load()}

          {:error, socket} ->
            {:noreply, assign(socket, :product_form, to_form(params, as: :product))}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Informe o preço em reais, por exemplo 25,50.")}
    end
  end

  def handle_event("edit-product", %{"id" => id}, socket) do
    product = Map.get(socket.assigns.product_catalog, number(id))

    if product do
      params = %{
        "name" => product.name,
        "category" => product.category,
        "price" => decimal(product.price),
        "destination" => product.destination,
        "active" => product.active
      }

      {:noreply,
       assign(socket,
         product_id: product.id,
         product_revision: product.revision,
         product_form: to_form(params, as: :product)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("new-product", _, socket),
    do:
      {:noreply,
       assign(socket,
         product_id: nil,
         product_revision: nil,
         product_form:
           to_form(%{"category" => "Geral", "destination" => "", "active" => true},
             as: :product
           )
       )}

  def handle_event("add-resource", %{"resource" => p}, socket),
    do: mutation(socket, %{"operation" => "add_resource", "name" => p["name"]})

  def handle_event("open-visit", %{"visit" => p}, socket) do
    case run(socket, %{
           "operation" => "open_session",
           "resource_id" => number(p["resource_id"]),
           "responsible_actor" => p["responsible_actor"],
           "business_date" => p["business_date"]
         }) do
      {:ok, socket, result} ->
        {:noreply,
         push_patch(socket,
           to:
             session_path(
               socket.assigns.current_scope,
               socket.assigns.workflow_id,
               socket.assigns.pages,
               result["id"]
             )
         )}

      {:error, socket} ->
        {:noreply, socket |> assign(:open_form, to_form(p, as: :visit)) |> load()}
    end
  end

  def handle_event("add-item", %{"item" => p}, socket) do
    product =
      Map.get(socket.assigns.product_catalog, number(p["product_id"]))

    quantity = number(p["quantity"])

    revision = number(p["product_revision"])

    if product && product.active && (revision == nil || revision == product.revision) && quantity &&
         quantity in 1..999 &&
         map_size(socket.assigns.cart) < 100 do
      id = Ecto.UUID.generate()

      item = %{
        id: id,
        product_id: product.id,
        product_revision: product.revision,
        name: product.name,
        unit_price: product.price,
        destination: product.destination,
        quantity: quantity,
        notes: String.slice(p["notes"] || "", 0, 300)
      }

      {:noreply,
       socket
       |> assign(:cart, Map.put(socket.assigns.cart, id, item))
       |> stream_insert(:cart_items, item)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Selecione um produto ativo e uma quantidade de 1 a 999 (máximo de 100 linhas)."
       )}
    end
  end

  def handle_event("quick-add", %{"id" => id}, socket) do
    handle_event(
      "add-item",
      %{"item" => %{"product_id" => id, "quantity" => "1", "notes" => ""}},
      socket
    )
  end

  def handle_event("remove-item", %{"id" => id}, socket) do
    case Map.pop(socket.assigns.cart, id) do
      {nil, _} ->
        {:noreply, socket}

      {item, cart} ->
        {:noreply, socket |> assign(:cart, cart) |> stream_delete(:cart_items, item)}
    end
  end

  def handle_event("submit-batch", %{"batch" => p}, socket) do
    lines =
      socket.assigns.cart
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(fn item ->
        %{
          "product_id" => item.product_id,
          "product_revision" => item.product_revision,
          "quantity" => item.quantity,
          "notes" => item.notes
        }
      end)

    case run(socket, %{
           "operation" => "submit_batch",
           "session_id" => socket.assigns.visit_id,
           "responsible_actor" => p["responsible_actor"],
           "lines" => lines
         }) do
      {:ok, socket, _} ->
        {:noreply, socket |> assign(cart: %{}) |> stream(:cart_items, [], reset: true) |> load()}

      {:error, socket} ->
        {:noreply, load(socket)}
    end
  end

  def handle_event("handoff", %{"id" => id}, socket),
    do: mutation(socket, %{"operation" => "handoff", "batch_id" => number(id)})

  def handle_event("cancel-batch", %{"cancel" => p}, socket),
    do:
      mutation(socket, %{
        "operation" => "cancel_batch",
        "batch_id" => number(p["batch_id"]),
        "reason" => p["reason"]
      })

  def handle_event("print-ticket", %{"id" => id}, socket) do
    case run(socket, %{"operation" => "print_ticket", "batch_id" => number(id)}) do
      {:ok, socket, result} ->
        socket = load(socket)

        batch =
          socket.assigns.visit &&
            Enum.find(socket.assigns.visit.batches, &(&1.id == result["id"]))

        if batch do
          {:noreply,
           socket
           |> assign(:print_ticket, Map.put(batch, :copy, result["copy"]))
           |> push_event("operations:print", %{})}
        else
          {:noreply,
           put_flash(socket, :error, "Abra o atendimento deste ticket antes de imprimir.")}
        end

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("settle", %{"checkout" => p}, socket) do
    if map_size(socket.assigns.cart) > 0 do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Envie ou remova os itens ainda não enviados antes de fechar a conta."
       )}
    else
      mutation(socket, %{
        "operation" => "settle",
        "session_id" => socket.assigns.visit_id,
        "expected_total" => socket.assigns.visit.total,
        "payment_method" => p["payment_method"]
      })
    end
  end

  def handle_event("day", %{"day" => p}, socket) do
    case Date.from_iso8601(p["date"] || "") do
      {:ok, date} ->
        {:noreply, socket |> assign(date: date, day_form: to_form(p, as: :day)) |> load()}

      _ ->
        {:noreply, put_flash(socket, :error, "Selecione uma data válida.")}
    end
  end

  def handle_event("close-day", _, socket),
    do:
      mutation(socket, %{
        "operation" => "close_day",
        "business_date" => Date.to_iso8601(socket.assigns.date)
      })

  def handle_event(event, _, socket) when event in ["heartbeat", "reconcile"],
    do: {:noreply, load(socket)}

  def handle_info(:reconcile, socket), do: {:noreply, load(socket)}
  def handle_info(:requests_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:operations_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:budgets_changed, socket), do: {:noreply, load(socket)}
  def handle_info(:permissions_changed, socket), do: {:noreply, load(socket)}

  defp page_version(scope, workflow_id, nil), do: Workspaces.get(scope, workflow_id)

  defp page_version(scope, workflow_id, session_id) do
    Operations.version_for_visit(scope, session_id, workflow_id)
  end

  defp load(socket) do
    version =
      page_version(
        socket.assigns.current_scope,
        socket.assigns.workflow_id,
        socket.assigns.visit_id
      )

    if version == nil do
      push_navigate(socket,
        to: ~p"/o/#{socket.assigns.current_scope.organization.slug}/processos"
      )
    else
      page =
        Enum.find(Workspaces.pages(version.definition), &(&1["key"] == socket.assigns.page_key)) ||
          hd(Workspaces.pages(version.definition))

      data =
        if socket.assigns.visit_id || Workspaces.operational?(version.definition),
          do:
            Operations.workspace(
              socket.assigns.current_scope,
              socket.assigns.date,
              socket.assigns.workflow_id,
              socket.assigns.visit_id
            )

      # A historical session keeps its own pages and business actions. Shared
      # process setup, discovery and new work remain on the current publication.
      blocks =
        cond do
          data && data.archived? && socket.assigns.visit_id &&
              not Workspaces.operational?(version.definition) ->
            ["batches"]

          data && not data.current? ->
            Enum.filter(page["blocks"], &(&1 in ~w(items batches settlement)))

          true ->
            page["blocks"]
        end

      socket =
        socket
        |> assign(
          process_name: version.definition["name"],
          process_description: version.definition["description"],
          page_title: version.definition["name"],
          labels: Workspaces.labels(version.definition),
          pages: Workspaces.pages(version.definition),
          blocks: blocks,
          page_key: page["key"],
          can_configure: Workspaces.allowed?(socket.assigns.current_scope, version, "configure"),
          can_operate: Workspaces.allowed?(socket.assigns.current_scope, version, "operate")
        )
        |> load_records(version)
        |> load_finance(version)

      if data do
        visit =
          if socket.assigns.visit_id,
            do:
              Operations.visit(
                socket.assigns.current_scope,
                socket.assigns.visit_id,
                socket.assigns.workflow_id
              )

        products = data.products
        archived? = if visit, do: visit.archived?, else: data.archived?

        resources =
          Enum.map(data.resources, fn r ->
            Map.put(r, :session, Enum.find(data.sessions, &(&1.resource_id == r.id)))
          end)

        socket
        |> assign(
          authorized: true,
          operational_archived?: archived?,
          current_workspace?: data.current?,
          can_configure:
            data.current? and not data.archived? and
              Workspaces.allowed?(socket.assigns.current_scope, version, "configure"),
          workflow_id: data.version.workflow_id,
          product_catalog: Map.new(data.products, &{&1.id, &1}),
          visit: visit,
          report: data.report,
          timezone: socket.assigns.current_scope.organization.timezone,
          payment_options:
            Instantflow.WorkflowCatalog.OperationalContract.payment_options(
              if(visit, do: visit.version.definition, else: version.definition)
            ),
          labels:
            Workspaces.labels(if(visit, do: visit.version.definition, else: version.definition)),
          can_operate:
            not archived? and
              Workspaces.allowed?(
                socket.assigns.current_scope,
                if(visit, do: visit.version, else: version),
                "operate"
              ),
          resource_options:
            Enum.flat_map(resources, fn r -> if r.session, do: [], else: [{r.name, r.id}] end),
          cart_total:
            Enum.reduce(socket.assigns.cart, 0, fn {_, i}, sum ->
              sum + i.quantity * i.unit_price
            end)
        )
        |> stream(:products, products, reset: true)
        |> stream(:quick_products, Enum.filter(products, & &1.active), reset: true)
        |> stream(:picker_products, Enum.filter(products, & &1.active), reset: true)
        |> stream(:resources, resources, reset: true)
        |> stream(:batches, if(visit, do: visit.batches, else: []), reset: true)
        |> stream(
          :consumption,
          Enum.map(data.report.consumption, &Map.put(&1, :id, &1.product_id)),
          reset: true
        )
        |> then(fn s ->
          if visit && s.assigns.batch_form.params == %{},
            do:
              assign(
                s,
                :batch_form,
                to_form(%{"responsible_actor" => Operations.actor_name(visit.session)},
                  as: :batch
                )
              ),
            else: s
        end)
      else
        socket
        |> assign(
          authorized: false,
          visit: nil,
          product_catalog: %{},
          cart: %{},
          print_ticket: nil
        )
        |> stream(:cart_items, [], reset: true)
        |> stream(:products, [], reset: true)
        |> stream(:quick_products, [], reset: true)
        |> stream(:picker_products, [], reset: true)
        |> stream(:resources, [], reset: true)
        |> stream(:batches, [], reset: true)
        |> stream(:consumption, [], reset: true)
      end
    end
  end

  defp load_records(socket, version) do
    views =
      if "records" in socket.assigns.blocks,
        do: Views.options(socket.assigns.current_scope, %{"workflow_id" => version.workflow_id}),
        else: []

    selected = Enum.find(views, &(&1.key == socket.assigns.record_view)) || List.first(views)

    result =
      if selected && "records" in socket.assigns.blocks do
        Views.search(
          socket.assigns.current_scope,
          version.workflow_id,
          selected.key,
          socket.assigns.record_filters
        )
      else
        %{
          columns: [],
          total: 0,
          stages: [],
          rows: [],
          page: 1,
          pages: 1,
          filters: [],
          urgent: 0,
          assignment?: false
        }
      end

    socket
    |> assign(
      record_columns: result.columns,
      record_total: result.total,
      record_filter_options: result.filters,
      record_urgent: result.urgent,
      record_assignments?: result.assignment?,
      record_page: result.page,
      record_pages: result.pages,
      record_view_options: Enum.map(views, &{&1.view_label, &1.key}),
      record_stage_options: Enum.map(result.stages, &{&1.label, &1.id}),
      record_view_type: if(selected, do: selected.type, else: "table"),
      can_create_record:
        !Workspaces.operational?(version.definition) &&
          Enum.any?(
            WorkflowCatalog.available(socket.assigns.current_scope),
            &(&1.workflow_id == version.workflow_id)
          )
    )
    |> stream(:process_records, result.rows, reset: true)
  end

  defp finance_result(socket, {:ok, _}),
    do: socket |> assign(:command_key, Ecto.UUID.generate()) |> load()

  defp finance_result(socket, {:error, reason}),
    do: socket |> put_flash(:error, message(reason)) |> load()

  defp load_finance(socket, version) do
    data =
      if Enum.any?(socket.assigns.blocks, &(&1 in ~w(finance_setup finance_summary))),
        do: Instantflow.Finance.Surfaces.load(socket.assigns.current_scope, version.workflow_id),
        else: Instantflow.Finance.Surfaces.empty()

    socket
    |> assign(finance_surface: Map.delete(data, :summaries))
    |> stream(:finance_summaries, data.summaries, reset: true)
  end

  defp run(socket, command) do
    command =
      Map.merge(command, %{
        "key" => socket.assigns.command_key,
        "workflow_id" => socket.assigns.workflow_id
      })

    case Operations.command(socket.assigns.current_scope, command) do
      {:ok, result} -> {:ok, assign(socket, :command_key, Ecto.UUID.generate()), result}
      {:error, error} -> {:error, put_flash(socket, :error, message(error))}
    end
  end

  defp mutation(socket, command) do
    case run(socket, command) do
      {:ok, socket, _} -> {:noreply, load(socket)}
      {:error, socket} -> {:noreply, load(socket)}
    end
  end

  defp number(value) when is_binary(value) and byte_size(value) <= 18 do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp number(_), do: nil

  defp decimal(cents),
    do: "#{div(cents, 100)},#{String.pad_leading(Integer.to_string(rem(cents, 100)), 2, "0")}"

  defp message(:forbidden), do: "Seu perfil não tem permissão para esta operação."
  defp message(:duplicate_name), do: "Este nome já está cadastrado."
  defp message(:occupied), do: "Este recurso já tem um atendimento aberto."

  defp message(:pending_handoff),
    do: "Confirme a entrega de todos os pedidos e cancelamentos antes de fechar."

  defp message(:catalog_changed),
    do: "O catálogo mudou. Remova e adicione novamente os itens para revisar preços e destinos."

  defp message(:day_closed),
    do: "Este dia operacional já foi encerrado. Selecione um dia posterior."

  defp message(:open_sessions), do: "Feche os atendimentos deste dia antes de encerrá-lo."

  defp message(:conflict),
    do: "Os dados mudaram. Revise os valores atualizados e tente novamente."

  defp message(:template_changed),
    do: "O modelo operacional foi alterado. Solicite revisão do operador."

  defp message(_), do: "Não foi possível concluir. Revise os dados e o estado do atendimento."

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} unsaved={map_size(@cart) > 0}>
      <div class="page-heading">
        <div>
          <p class="eyebrow">PROCESSO DA ORGANIZAÇÃO</p><h1>{@process_name}</h1><p>
            {@process_description}
          </p>
        </div>
      </div>
      <nav id="process-pages" aria-label="Páginas do processo" class="process-page-tabs">
        <.link
          :for={page <- @pages}
          id={"process-page-#{page["key"]}"}
          patch={page_path(@current_scope, @workflow_id, page["key"], @visit_id)}
          aria-current={if page["key"] == @page_key, do: "page"}
          class="btn"
        >{page["label"]}</.link>
      </nav>
      <p
        :if={!@authorized && Enum.any?(@blocks, &(&1 in Workspaces.operational_blocks()))}
        id="operations-denied"
      >
        Seu perfil não tem acesso aos blocos operacionais deste processo.
      </p>
      <div id="operations-workspace">
        <p :if={@visit && !@current_workspace?} id="pinned-session-rules" role="status">
          Este atendimento usa as regras publicadas na abertura.
          <.link navigate={~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}"}>
            Abra o processo atual para novos atendimentos e configurações.
          </.link>
        </p>
        <p :if={@operational_archived?} id="archived-operations" role="status">
          Atendimento histórico arquivado. Os dados foram preservados e não aceitam novas alterações.
        </p>
        <div id="operations-print-hook" phx-hook="OperationsPrint" phx-update="ignore"></div>
        <div id="operations-connection" phx-hook="Collaboration" phx-update="ignore"></div>
        <p :if={@visit_id && !@visit} id="visit-not-found">Atendimento indisponível.</p>
        <section :if={@visit} id="active-visit" class="card template-section">
          <h2>{@visit.session.resource_name} · Atendimento #{@visit.session.id}</h2>
          <p>
            {@labels["actor"]}: {Operations.actor_name(@visit.session)} · Dia operacional: {@visit.session.business_date}
          </p>
          <.link navigate={
            ~p"/o/#{@current_scope.organization.slug}/processos/#{@workflow_id}/registros/#{@visit.session.ticket_id}"
          }>Histórico do fluxo</.link>
          <p :if={@visit.session.status == "archived"} id="visit-archived">
            Atendimento arquivado sem quitação. O valor histórico foi preservado; o recurso está disponível para um novo atendimento.
          </p>
          <p :if={@visit.session.status == "settled"} id="visit-settled">
            Conta encerrada. O recurso está disponível para um novo atendimento.
          </p>
        </section>
        <%= for block <- @blocks do %>
          <%= case block do %>
            <% "records" -> %>
              <.records_block {assigns} />
            <% "catalog" -> %>
              <.catalog_block :if={@authorized && @can_configure} {assigns} />
            <% "resources" -> %>
              <.resources_block :if={@authorized} {assigns} />
            <% "items" -> %>
              <.items_block :if={@authorized && @can_operate && @visit} {assigns} />
            <% "batches" -> %>
              <.batches_block :if={@authorized && @visit} {assigns} />
            <% "settlement" -> %>
              <.settlement_block :if={@authorized && @visit} {assigns} />
            <% "daily_summary" -> %>
              <.daily_summary_block :if={@authorized} {assigns} />
            <% "finance_setup" -> %>
              <.finance_setup_block {assigns} />
            <% "finance_summary" -> %>
              <.finance_summary_block {assigns} />
          <% end %>
        <% end %>
        <.print_block {assigns} />
      </div>
    </Layouts.app>
    """
  end
end
