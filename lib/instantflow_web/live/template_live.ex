defmodule InstantflowWeb.TemplateLive do
  use InstantflowWeb, :live_view
  import InstantflowWeb.WorkflowGraphComponents
  import InstantflowWeb.AuthoringPanels, only: [workspace_panel: 1, participant_preview_panel: 1]
  alias Instantflow.{Identity, WorkflowCatalog.Templates}
  alias Instantflow.WorkflowCatalog.{Authoring, Definition, Diff, Graph, Interchange}
  alias InstantflowWeb.TemplatesLive

  @labels %{
    "stages" => "Etapa",
    "transitions" => "Transição",
    "sections" => "Seção",
    "fields" => "Campo",
    "access" => "Permissão de seção",
    "actions" => "Ação simulada",
    "roles" => "Papel simbólico",
    "bindings" => "Vínculo de departamento",
    "views" => "Visualização",
    "participants" => "Relacionamento verificado",
    "communications" => "Comunicação selecionada"
  }
  @field_labels %{
    "short_text" => "Texto curto",
    "long_text" => "Texto longo",
    "integer" => "Inteiro",
    "money" => "Dinheiro (centavos)",
    "date" => "Data",
    "datetime" => "Instante ISO 8601",
    "boolean" => "Sim/não",
    "single_choice" => "Escolha única",
    "multiple_choice" => "Múltipla escolha",
    "directory_reference" => "Referência de participante ou sujeito",
    "attachment" => "Documento privado"
  }

  def mount(_, _, socket) do
    if Identity.admin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         page_title: "Editor de modelo",
         draft: nil,
         unsaved: false,
         pending_forms: %{},
         conflict: nil,
         export: nil,
         graph_focus: "",
         selected_page_key: nil,
         preview: nil,
         preview_form: to_form(%{}, as: :preview),
         collection: "stages",
         parent: nil,
         original: nil,
         item_form: to_form(Authoring.form(), as: :item),
         picker: to_form(%{}, as: :picker),
         finance_account_form: to_form(%{}, as: :new_finance_account),
         budget_options: Instantflow.Finance.binding_options(socket.assigns.current_scope),
         department_options:
           Enum.map(Identity.departments(socket.assigns.current_scope), &{&1.name, &1.id})
       )}
    else
      {:ok, denied(socket)}
    end
  end

  def handle_params(%{"id" => id}, _, socket) do
    case Templates.review(socket.assigns.current_scope, TemplatesLive.integer(id)) do
      {:ok, review} -> {:noreply, load(socket, review)}
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event("focus-stage", %{"graph" => %{"stage" => stage}}, socket) do
    if stage == "" or Enum.any?(socket.assigns.draft.definition["stages"], &(&1["key"] == stage)) do
      {:noreply,
       socket
       |> assign(graph_focus: stage)
       |> load_graph(socket.assigns.draft.definition)
       |> push_event("workflow-graph-focus", %{stage: stage})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pick", %{"picker" => p}, socket) do
    collection = p["collection"]
    parent = if collection == "actions", do: p["transition"], else: p["section"]

    if collection in Authoring.collections() and
         valid_parent?(socket.assigns.draft.definition, collection, parent),
       do: {:noreply, select_item(socket, collection, parent, nil)},
       else:
         {:noreply,
          put_flash(socket, :error, "Escolha uma seção ou transição válida para este item.")}
  end

  def handle_event("edit", %{"collection" => c, "parent" => p, "key" => key}, socket) do
    if c in Authoring.collections() and valid_parent?(socket.assigns.draft.definition, c, p),
      do: {:noreply, select_item(socket, c, p, key)},
      else: {:noreply, put_flash(socket, :error, TemplatesLive.message(:not_found))}
  end

  def handle_event("dirty", params, socket) do
    pending =
      Map.merge(
        socket.assigns.pending_forms,
        Map.take(params, ~w(metadata mapping item interface_page workspace advanced))
      )

    {:noreply, socket |> assign(pending_forms: pending) |> restore_pending_forms()}
  end

  def handle_event("discard-form", _, %{assigns: %{conflict: conflict}} = socket)
      when not is_nil(conflict) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Compare o conflito e preserve suas alterações antes de recarregar a versão salva."
     )}
  end

  def handle_event("discard-form", %{"form" => name}, socket) do
    {:noreply,
     socket |> assign(pending_forms: Map.delete(socket.assigns.pending_forms, name)) |> reload()}
  end

  def handle_event("preview-picker", %{"picker" => params}, socket) do
    {:noreply, assign(socket, picker: to_form(params, as: :picker))}
  end

  def handle_event("preview-participant", %{"preview" => params}, socket) do
    preview =
      Instantflow.WorkflowRuntime.ParticipantPreview.project(
        socket.assigns.draft.definition,
        params
      )

    {:noreply, assign(socket, preview: preview, preview_form: to_form(params, as: :preview))}
  end

  def handle_event("save-item", %{"item" => p}, socket) do
    socket =
      assign(socket,
        pending_forms: Map.put(socket.assigns.pending_forms, "item", p),
        saving_form: "item",
        unsaved: true
      )
      |> restore_pending_forms()

    a = socket.assigns

    socket =
      assign(socket,
        unsaved: true,
        item_form:
          to_form(Authoring.form() |> Ecto.Changeset.cast(p, Map.keys(Authoring.form().types)),
            as: :item
          )
      )

    case Authoring.change(a.draft.definition, a.collection, a.parent, a.original, p) do
      {:ok, definition} ->
        key =
          case a.collection do
            "access" -> p["role"] <> ":" <> p["scope"]
            "actions" -> p["type"] <> ":" <> p["behavior"]
            _ -> p["key"]
          end

        persist(socket, definition, a.draft.bindings, key)

      {:error, reason} ->
        {:noreply,
         put_flash(assign(socket, saving_form: nil), :error, TemplatesLive.message(reason))}
    end
  end

  def handle_event("remove", %{"collection" => c, "parent" => p, "key" => key}, socket) do
    case Authoring.remove(socket.assigns.draft.definition, c, p, key) do
      {:ok, definition} ->
        persist(socket, definition, prune_bindings(socket.assigns.draft.bindings, definition))

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, TemplatesLive.message(reason))}
    end
  end

  def handle_event("move-stage", %{"key" => key, "direction" => direction}, socket) do
    if socket.assigns.unsaved or socket.assigns.conflict != nil do
      {:noreply,
       put_flash(
         socket,
         :error,
         "Salve ou revise as alterações pendentes antes de reorganizar as etapas."
       )}
    else
      case Authoring.move_stage(socket.assigns.draft.definition, key, direction) do
        {:ok, definition} -> persist(socket, definition, socket.assigns.draft.bindings)
        {:error, reason} -> {:noreply, put_flash(socket, :error, TemplatesLive.message(reason))}
      end
    end
  end

  def handle_event("metadata", %{"metadata" => p}, socket) do
    socket =
      assign(socket,
        pending_forms: Map.put(socket.assigns.pending_forms, "metadata", p),
        saving_form: "metadata",
        unsaved: true
      )
      |> restore_pending_forms()

    d = socket.assigns.draft

    persist(
      socket,
      Map.merge(d.definition, Map.take(p, ~w(name description template_version))),
      d.bindings
    )
  end

  def handle_event("workspace-labels", %{"workspace" => params}, socket) do
    socket =
      assign(socket,
        pending_forms: Map.put(socket.assigns.pending_forms, "workspace", params),
        saving_form: "workspace",
        unsaved: true
      )
      |> restore_pending_forms()

    draft = socket.assigns.draft

    interface =
      Instantflow.WorkflowCatalog.Workspaces.configuration(draft.definition)
      |> Map.put("labels", Map.take(params, ~w(resource resources catalog actor destination)))

    persist(
      socket,
      Map.put(
        draft.definition,
        "interface",
        Map.merge(Map.get(draft.definition, "interface", %{}), interface)
      ),
      draft.bindings
    )
  end

  def handle_event(
        "pick-page",
        _,
        %{assigns: %{pending_forms: %{"interface_page" => _}}} = socket
      ) do
    {:noreply,
     put_flash(socket, :error, "Salve a página atual antes de trocar ou reorganizar páginas.")}
  end

  def handle_event("pick-page", %{"key" => key}, socket) do
    {:noreply, socket |> assign(:selected_page_key, key) |> load_review()}
  end

  def handle_event("create-finance-account", %{"new_finance_account" => params}, socket) do
    case Instantflow.Finance.create_account(
           socket.assigns.current_scope,
           TemplatesLive.integer(params["department_id"]),
           params["name"]
         ) do
      {:ok, _} ->
        {:noreply,
         assign(socket,
           budget_options: Instantflow.Finance.binding_options(socket.assigns.current_scope),
           finance_account_form: to_form(%{}, as: :new_finance_account)
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, InstantflowWeb.RuntimeErrors.message(reason))}
    end
  end

  def handle_event("new-page", _, %{assigns: %{pending_forms: %{"interface_page" => _}}} = socket) do
    {:noreply,
     put_flash(socket, :error, "Salve a página atual antes de trocar ou reorganizar páginas.")}
  end

  def handle_event("new-page", _, socket) do
    params =
      interface_page(socket.assigns.draft.definition, nil)
      |> Map.merge(%{"key" => "", "label" => "", "blocks" => ["records"]})

    {:noreply,
     assign(socket,
       selected_page_key: "",
       interface_page_form: to_form(params, as: :interface_page)
     )}
  end

  def handle_event("save-interface-page", %{"interface_page" => params}, socket) do
    socket =
      assign(socket,
        pending_forms: Map.put(socket.assigns.pending_forms, "interface_page", params),
        saving_form: "interface_page",
        unsaved: true
      )
      |> restore_pending_forms()

    draft = socket.assigns.draft
    interface = Instantflow.WorkflowCatalog.Workspaces.configuration(draft.definition)

    page = %{
      "key" => params["key"],
      "label" => params["label"],
      "blocks" => List.wrap(params["blocks"]) |> Enum.reject(&(&1 == ""))
    }

    page =
      if params["participant_enabled"] == "true" do
        audience =
          for value <- List.wrap(params["participant_audience"]), value != "" do
            case Jason.decode(value) do
              {:ok, actor} when is_map(actor) -> actor
              _ -> %{}
            end
          end

        projection = %{
          "visibility_roles" => selections(params["participant_visibility"]),
          "audience" => audience,
          "fields" => selections(params["participant_fields"]),
          "documents" => selections(params["participant_documents"]),
          "actions" => selections(params["participant_actions"]),
          "status" => params["participant_status"] == "true",
          "history" => params["participant_history"] == "true"
        }

        projection =
          if selections(params["participant_messages"]) == [],
            do: projection,
            else: Map.put(projection, "messages", selections(params["participant_messages"]))

        Map.put(page, "participant", projection)
      else
        page
      end

    pages =
      if Enum.any?(interface["pages"], &(&1["key"] == page["key"])),
        do:
          Enum.map(interface["pages"], fn old ->
            if old["key"] == page["key"], do: page, else: old
          end),
        else: interface["pages"] ++ [page]

    interface = Map.put(interface, "pages", pages)

    access =
      Map.new(~w(view configure operate), fn key ->
        {key,
         List.wrap(params["access_" <> key] || draft.definition["creation"]["roles"])
         |> Enum.reject(&(&1 == ""))}
      end)

    interface = Map.put(interface, "access", access)

    interface =
      if params["close_transition"] in [nil, ""],
        do: Map.delete(interface, "lifecycle"),
        else: Map.put(interface, "lifecycle", %{"close_transition" => params["close_transition"]})

    interface =
      if "operations" in draft.definition["capabilities"] or
           Enum.any?(pages, fn p ->
             Enum.any?(
               p["blocks"],
               &(&1 in Instantflow.WorkflowCatalog.Interface.operational_blocks())
             )
           end) do
        contract =
          Instantflow.WorkflowCatalog.OperationalContract.resolve(draft.definition) ||
            Instantflow.WorkflowCatalog.OperationalContract.defaults()

        methods =
          if Map.has_key?(params, "payment_methods"),
            do: selections(params["payment_methods"]),
            else: contract["payment_methods"]

        Map.put(interface, "operations", Map.put(contract, "payment_methods", methods))
      else
        interface
      end

    required =
      Enum.flat_map(pages, fn p ->
        Enum.map(p["blocks"], &Instantflow.WorkflowCatalog.Interface.required_capability/1)
      end)

    capabilities =
      Enum.filter(
        Instantflow.WorkflowCatalog.Capabilities.supported(),
        &(&1 in draft.definition["capabilities"] or &1 in required)
      )

    interface =
      if params["finance_binding"] in [nil, ""],
        do: Map.delete(interface, "finance"),
        else:
          Map.put(interface, "finance", %{
            "account_binding" => params["finance_binding"],
            "scope" => params["finance_scope"] || "process",
            "view_roles" => selections(params["finance_roles"])
          })

    definition =
      draft.definition |> Map.put("interface", interface) |> Map.put("capabilities", capabilities)

    persist(assign(socket, :selected_page_key, page["key"]), definition, draft.bindings)
  end

  def handle_event(
        "move-interface-block",
        _,
        %{assigns: %{pending_forms: %{"interface_page" => _}}} = socket
      ) do
    {:noreply,
     put_flash(socket, :error, "Salve a página atual antes de trocar ou reorganizar páginas.")}
  end

  def handle_event("move-interface-block", %{"index" => raw, "direction" => direction}, socket) do
    draft = socket.assigns.draft
    config = Instantflow.WorkflowCatalog.Workspaces.configuration(draft.definition)
    page_key = socket.assigns.selected_page_key || hd(config["pages"])["key"]

    with {index, ""} <- Integer.parse(raw), true <- direction in ["up", "down"] do
      pages =
        Enum.map(config["pages"], fn page ->
          if page["key"] == page_key do
            target = index + if(direction == "up", do: -1, else: 1)

            if index >= 0 and target >= 0 and index < length(page["blocks"]) and
                 target < length(page["blocks"]) do
              blocks = page["blocks"]

              Map.put(
                page,
                "blocks",
                blocks
                |> List.replace_at(index, Enum.at(blocks, target))
                |> List.replace_at(target, Enum.at(blocks, index))
              )
            else
              page
            end
          else
            page
          end
        end)

      persist(
        socket,
        Map.put(draft.definition, "interface", Map.put(config, "pages", pages)),
        draft.bindings
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("bindings", %{"mapping" => p}, socket) do
    socket =
      assign(socket,
        pending_forms: Map.put(socket.assigns.pending_forms, "mapping", p),
        saving_form: "mapping",
        unsaved: true
      )
      |> restore_pending_forms()

    roles =
      Map.new(p["roles"] || %{}, fn {key, values} ->
        {key, List.wrap(values) |> Enum.reject(&(&1 == ""))}
      end)
      |> Map.reject(fn {_, values} -> values == [] end)

    departments =
      (p["departments"] || %{})
      |> Map.reject(fn {_, id} -> id == "" end)
      |> Map.new(fn {key, id} -> {key, TemplatesLive.integer(id)} end)

    d =
      put_in(
        socket.assigns.draft.definition,
        ["assignment", "department_binding"],
        p["assignment"]
      )

    budgets =
      Map.new(p["budgets"] || %{}, fn {k, id} -> {k, TemplatesLive.integer(id)} end)
      |> Map.reject(fn {_, id} -> is_nil(id) end)

    bindings = %{"roles" => roles, "departments" => departments}
    bindings = if budgets == %{}, do: bindings, else: Map.put(bindings, "budgets", budgets)
    persist(socket, d, bindings)
  end

  def handle_event("advanced", %{"advanced" => p}, socket) do
    socket =
      assign(socket,
        pending_forms: Map.put(socket.assigns.pending_forms, "advanced", p),
        saving_form: "advanced",
        unsaved: true
      )
      |> restore_pending_forms()

    case Interchange.decode(p["json"]) do
      {:ok, definition} ->
        persist(socket, definition, socket.assigns.draft.bindings)

      _ ->
        {:noreply,
         put_flash(assign(socket, saving_form: nil), :error, TemplatesLive.message(:invalid_json))}
    end
  end

  def handle_event("reload", _, socket) do
    {:noreply,
     socket |> assign(pending_forms: %{}) |> reload() |> assign(conflict: nil, unsaved: false)}
  end

  def handle_event("review-publication", _, socket) do
    {:noreply, assign(socket, publication_confirmation: true)}
  end

  def handle_event("cancel-publication", _, socket) do
    {:noreply, assign(socket, publication_confirmation: false)}
  end

  def handle_event("publish", _, %{assigns: %{publication_confirmation: false}} = socket),
    do: {:noreply, socket}

  def handle_event("publish", _, %{assigns: %{unsaved: true}} = socket),
    do: {:noreply, put_flash(socket, :error, "Salve os formulários pendentes antes de publicar.")}

  def handle_event("publish", _, %{assigns: %{conflict: conflict}} = socket)
      when not is_nil(conflict),
      do: {:noreply, put_flash(socket, :error, "Resolva o conflito antes de publicar.")}

  def handle_event("publish", _, socket) do
    case Templates.publish(
           socket.assigns.current_scope,
           socket.assigns.draft.id,
           socket.assigns.draft.revision
         ) do
      {:ok, version} ->
        {:noreply,
         reload(socket)
         |> clear_flash(:error)
         |> put_flash(
           :info,
           "Versão #{version.number} publicada. Solicitações existentes preservam sua versão."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, TemplatesLive.message(reason))}
    end
  end

  def handle_event("export", _, socket) do
    case Templates.export(socket.assigns.current_scope, :draft, socket.assigns.draft.id) do
      {:ok, exported} -> {:noreply, assign(socket, export: exported)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, TemplatesLive.message(reason))}
    end
  end

  defp persist(socket, definition, bindings, saved_selection \\ nil) do
    saved_form = socket.assigns[:saving_form]
    socket = assign(socket, saving_form: nil)

    case Templates.save(
           socket.assigns.current_scope,
           socket.assigns.draft.id,
           socket.assigns.draft.revision,
           definition,
           bindings
         ) do
      {:ok, _} ->
        socket = if saved_selection, do: assign(socket, original: saved_selection), else: socket

        socket =
          assign(socket,
            pending_forms: Map.delete(socket.assigns.pending_forms, saved_form),
            saving_form: nil
          )

        {:noreply,
         reload(socket)
         |> clear_flash(:error)
         |> put_flash(:info, "Rascunho salvo. Revise antes de publicar.")}

      {:error, :conflict} ->
        case Templates.get(socket.assigns.current_scope, socket.assigns.draft.id) do
          {:ok, current} ->
            {:noreply,
             socket
             |> assign(
               conflict: %{json: Interchange.encode(definition), revision: current.revision},
               unsaved: true
             )
             |> stream(
               :conflicts,
               Enum.with_index(
                 Diff.compare(
                   %{"definition" => current.definition, "bindings" => current.bindings},
                   %{"definition" => definition, "bindings" => bindings}
                 )
               )
               |> Enum.map(fn {change, i} -> Map.put(change, :id, i) end),
               reset: true
             )
             |> put_flash(:error, TemplatesLive.message(:conflict))}

          _ ->
            {:noreply, denied(socket)}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, TemplatesLive.message(reason))}
    end
  end

  defp reload(socket) do
    case Templates.review(socket.assigns.current_scope, socket.assigns.draft.id) do
      {:ok, review} -> load(socket, review)
      _ -> denied(socket)
    end
  end

  defp load(socket, review) do
    d = review.draft.definition

    socket
    |> assign(
      draft: review.draft,
      preview: nil,
      review_errors: review.errors,
      publication_confirmation: false,
      review_warnings: review.warnings,
      unsaved: false,
      conflict: nil,
      export: nil,
      interface_pages: Instantflow.WorkflowCatalog.Workspaces.pages(d),
      interface_page_form:
        to_form(interface_page(d, socket.assigns.selected_page_key), as: :interface_page),
      interface_blocks: Instantflow.WorkflowCatalog.Workspaces.blocks(),
      participant_audience_options: participant_audience_options(d),
      communication_options:
        Enum.map(Map.get(d, "communications", []), &{&1["label"], &1["key"]}),
      relationship_options: Enum.map(Map.get(d, "participants", []), &{&1["label"], &1["key"]}),
      budget_binding_options:
        for(
          binding <- d["bindings"],
          binding["type"] == "budget",
          do: {binding["label"], binding["key"]}
        ),
      close_options: Enum.map(d["transitions"], &{&1["label"], &1["key"]}),
      workspace_form: to_form(Instantflow.WorkflowCatalog.Workspaces.labels(d), as: :workspace),
      metadata_form: to_form(Map.take(d, ~w(name description template_version)), as: :metadata),
      mapping_form: to_form(%{}, as: :mapping),
      advanced_form: to_form(%{"json" => Interchange.encode(d)}, as: :advanced),
      role_options: Enum.map(d["role_requirements"], &{&1["label"], &1["key"]}),
      stage_options: Enum.map(d["stages"], &{&1["label"], &1["key"]}),
      field_options:
        Enum.map(Definition.fields(d), fn {key, field} ->
          {field["label"] <> " · " <> key, key}
        end)
        |> Enum.sort(),
      section_options: Enum.map(d["sections"], &{&1["label"], &1["key"]}),
      transition_options: Enum.map(d["transitions"], &{&1["label"], &1["key"]}),
      local_roles:
        Enum.map(Instantflow.Access.binding_roles(), &{TemplatesLive.role_label(&1), &1}),
      collection_options: Enum.map(@labels, fn {k, v} -> {v, k} end) |> Enum.sort(),
      field_types: Enum.map(Authoring.field_types(), &{@field_labels[&1], &1})
    )
    |> stream(:items, rows(d), reset: true)
    |> load_graph(d)
    |> stream(
      :changes,
      Enum.with_index(review.changes) |> Enum.map(fn {c, i} -> Map.put(c, :id, i) end),
      reset: true
    )
    |> stream(:roles, review.roles, reset: true)
    |> restore_selection()
    |> restore_pending_forms()
  end

  defp load_graph(socket, definition) do
    focus =
      if Enum.any?(definition["stages"], &(&1["key"] == socket.assigns.graph_focus)),
        do: socket.assigns.graph_focus,
        else: ""

    graph = Graph.layout(definition, focus)

    socket
    |> assign(
      graph_width: graph.width,
      graph_height: graph.height,
      graph_focus: focus,
      graph_form: to_form(%{"stage" => focus}, as: :graph)
    )
    |> stream(:graph_nodes, graph.nodes, reset: true)
    |> stream(:graph_edges, graph.edges, reset: true)
  end

  defp restore_selection(socket) do
    a = socket.assigns

    if valid_parent?(a.draft.definition, a.collection, a.parent) do
      key =
        if Enum.any?(
             Authoring.items(a.draft.definition, a.collection, a.parent),
             &(Authoring.identity(&1, a.collection) == a.original)
           ),
           do: a.original

      select(socket, a.collection, a.parent, key)
    else
      select(socket, "stages", nil, nil)
    end
  end

  defp rows(d) do
    for c <- Authoring.collections(), {p, items} <- groups(d, c), item <- items do
      key = Authoring.identity(item, c)

      %{
        id: c <> "-" <> (p || "root") <> "-" <> String.replace(key, ":", "-"),
        collection: c,
        parent: p || "",
        key: key,
        kind: @labels[c],
        first?: item == List.first(items),
        last?: item == List.last(items),
        label: item_label(d, c, item, key),
        detail: if(c == "transitions", do: "#{item["from"]} → #{item["to"]}", else: p || key)
      }
    end
  end

  defp item_label(d, "access", item, _) do
    role = Enum.find(d["role_requirements"], &(&1["key"] == item["role"]))
    if(role, do: role["label"], else: item["role"]) <> " · " <> scope_label(item["scope"])
  end

  defp item_label(_, "actions", item, _),
    do: action_label(item["type"]) <> " · " <> behavior_label(item["behavior"])

  defp item_label(_, _, item, key), do: item["label"] || key

  defp groups(d, c) when c in ~w(fields access), do: Enum.map(d["sections"], &{&1["key"], &1[c]})
  defp groups(d, "actions"), do: Enum.map(d["transitions"], &{&1["key"], &1["actions"]})
  defp groups(d, c), do: [{nil, Authoring.items(d, c, nil)}]

  defp select_item(socket, collection, parent, key) do
    socket
    |> assign(pending_forms: Map.delete(socket.assigns.pending_forms, "item"))
    |> select(collection, parent, key)
    |> restore_pending_forms()
  end

  defp restore_pending_forms(socket) do
    forms = %{
      "metadata" => :metadata_form,
      "mapping" => :mapping_form,
      "item" => :item_form,
      "interface_page" => :interface_page_form,
      "workspace" => :workspace_form,
      "advanced" => :advanced_form
    }

    Enum.reduce(socket.assigns.pending_forms, socket, fn {name, params}, state ->
      form =
        if name == "item" do
          to_form(Ecto.Changeset.cast(Authoring.form(), params, Map.keys(Authoring.form().types)),
            as: :item
          )
        else
          to_form(params, as: name)
        end

      assign(state, Map.fetch!(forms, name), form)
    end)
    |> assign(unsaved: map_size(socket.assigns.pending_forms) > 0)
  end

  defp select(socket, c, p, key) do
    item =
      Enum.find(
        Authoring.items(socket.assigns.draft.definition, c, p),
        &(Authoring.identity(&1, c) == key)
      ) || %{}

    assign(socket,
      collection: c,
      collection_label: @labels[c],
      parent: p,
      original: key,
      picker: to_form(%{"collection" => c}, as: :picker),
      item_form: to_form(Authoring.form(item, socket.assigns.draft.definition), as: :item),
      unsaved: false
    )
  end

  defp valid_parent?(d, c, p) when c in ~w(fields access),
    do: Enum.any?(d["sections"], &(&1["key"] == p))

  defp valid_parent?(d, "actions", p), do: Enum.any?(d["transitions"], &(&1["key"] == p))
  defp valid_parent?(_, _, _), do: true

  defp load_review(socket) do
    {:ok, review} = Templates.review(socket.assigns.current_scope, socket.assigns.draft.id)
    load(socket, review)
  end

  defp interface_page(definition, key) do
    page =
      Enum.find(Instantflow.WorkflowCatalog.Workspaces.pages(definition), &(&1["key"] == key)) ||
        hd(Instantflow.WorkflowCatalog.Workspaces.pages(definition))

    projection = page["participant"] || %{}

    page =
      Map.merge(page, %{
        "participant_enabled" => Map.has_key?(page, "participant"),
        "participant_visibility" => projection["visibility_roles"] || [],
        "participant_audience" => Enum.map(projection["audience"] || [], &Jason.encode!/1),
        "participant_fields" => projection["fields"] || [],
        "participant_documents" => projection["documents"] || [],
        "participant_actions" => projection["actions"] || [],
        "participant_messages" => projection["messages"] || [],
        "participant_status" => Map.get(projection, "status", true),
        "participant_history" => Map.get(projection, "history", false),
        "finance_binding" =>
          get_in(definition, ["interface", "finance", "account_binding"]) || "",
        "finance_scope" => get_in(definition, ["interface", "finance", "scope"]) || "process",
        "finance_roles" => get_in(definition, ["interface", "finance", "view_roles"]) || []
      })

    params =
      Enum.reduce(~w(view configure operate), page, fn action, values ->
        Map.put(
          values,
          "access_" <> action,
          get_in(definition, ["interface", "access", action]) || definition["creation"]["roles"]
        )
      end)

    params =
      Map.put(
        params,
        "payment_methods",
        (Instantflow.WorkflowCatalog.OperationalContract.resolve(definition) ||
           Instantflow.WorkflowCatalog.OperationalContract.defaults())["payment_methods"]
      )

    Map.put(
      params,
      "close_transition",
      Instantflow.WorkflowCatalog.Workspaces.close_transition(definition)
    )
  end

  defp review_error_anchor(error) do
    cond do
      String.starts_with?(error, "mapeamentos") ->
        "#authoring-people"

      String.contains?(error, "interface") ->
        "#workspace-configuration"

      String.starts_with?(error, ["name", "description", "template_version"]) ->
        "#authoring-overview"

      true ->
        "#authoring-items"
    end
  end

  defp form_anchor("metadata"), do: "#authoring-overview"
  defp form_anchor("mapping"), do: "#authoring-people"
  defp form_anchor("item"), do: "#authoring-items"
  defp form_anchor("interface_page"), do: "#workspace-configuration"
  defp form_anchor("workspace"), do: "#workspace-labels-form"
  defp form_anchor(_), do: "#template-review"

  defp form_label("metadata"), do: "Identificação do processo"
  defp form_label("mapping"), do: "Pessoas e permissões"
  defp form_label("item"), do: "Item em edição"
  defp form_label("interface_page"), do: "Página em edição"
  defp form_label("workspace"), do: "Nomes dos recursos"
  defp form_label(_), do: "Definição avançada"

  defp selections(value), do: List.wrap(value) |> Enum.reject(&(&1 == ""))

  defp participant_audience_options(definition) do
    options =
      for role <- definition["role_requirements"],
          spec <-
            [%{"scope" => "requester"}, %{"scope" => "assigned_department"}] ++
              for(
                participant <- Map.get(definition, "participants", []),
                do: %{"scope" => "participant", "relationship" => participant["key"]}
              ) ++
              for(
                binding <- definition["bindings"],
                binding["type"] == "department",
                do: %{"scope" => "workflow_department", "department_binding" => binding["key"]}
              ) do
        actor = Map.put(spec, "role", role["key"])

        {role["label"] <>
           " · " <>
           spec["scope"] <> " " <> (spec["relationship"] || spec["department_binding"] || ""),
         Jason.encode!(actor)}
      end

    imported =
      for page <- Instantflow.WorkflowCatalog.ParticipantPages.pages(definition),
          actor <- page["participant"]["audience"],
          do: {actor["role"] <> " · " <> actor["scope"], Jason.encode!(actor)}

    Enum.uniq_by(options ++ imported, &elem(&1, 1))
  end

  defp prune_bindings(b, d),
    do: %{
      "roles" => Map.take(b["roles"], Enum.map(d["role_requirements"], & &1["key"])),
      "departments" =>
        Map.take(
          b["departments"],
          Enum.map(Enum.filter(d["bindings"], &(&1["type"] == "department")), & &1["key"])
        ),
      "budgets" =>
        Map.take(
          b["budgets"] || %{},
          Enum.map(Enum.filter(d["bindings"], &(&1["type"] == "budget")), & &1["key"])
        )
    }

  defp denied(socket),
    do:
      socket
      |> put_flash(:error, "Modelo indisponível ou sem permissão nesta organização.")
      |> push_navigate(to: ~p"/o/#{socket.assigns.current_scope.organization.slug}")

  defp json(value), do: Interchange.encode(value)
  defp classification_label("restricted"), do: "Restrita"
  defp classification_label(_), do: "Interna"
  defp scope_label("assigned_user"), do: "Pessoa atribuída ao formulário"
  defp scope_label("participant"), do: "Participante com relacionamento verificado"
  defp scope_label("workflow_department"), do: "Departamento fixo do fluxo"
  defp scope_label("requester"), do: "Próprio solicitante"
  defp scope_label(_), do: "Departamento atribuído"
  defp action_label("simulate_notification"), do: "Notificação simulada"
  defp action_label(_), do: "Provisionamento simulado"
  defp behavior_label("success"), do: "Sucesso"
  defp behavior_label("fail_once"), do: "Falha na primeira tentativa"
  defp behavior_label(_), do: "Falha"

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      navigation={@workspace_navigation}
      unsaved={@unsaved}
    >
      <div :if={@draft} id="workflow-editor">
        <div class="page-heading" id="authoring-heading">
          <div>
            <p class="eyebrow">EDITOR DE MODELOS</p><h1>{@draft.definition["name"]}</h1><p>
              Revisão {@draft.revision} · {if @draft.published_version_id,
                do: "Publicado",
                else: "Rascunho não publicado"}
            </p>
            <p id="authoring-save-state" role="status">
              <%= cond do %>
                <% @conflict != nil -> %>
                  Conflito: compare as alterações antes de continuar.
                <% @unsaved -> %>
                  Alterações não salvas. Salve cada formulário antes de publicar.
                <% @draft.published_version_id != nil -> %>
                  Versão publicada. Clone o modelo para editar uma nova versão.
                <% true -> %>
                  Sem alterações locais pendentes.
              <% end %>
            </p>
          </div><.link
            navigate={~p"/o/#{@current_scope.organization.slug}/modelos"}
            class="btn"
            data-confirm={if @unsaved, do: "Descartar alterações não salvas?"}
          >Todos os modelos</.link>
        </div>
        <section
          :if={map_size(@pending_forms) > 0}
          id="pending-authoring-forms"
          class="card template-section"
          aria-label="Formulários com alterações pendentes"
        >
          <h2>Alterações não salvas</h2>
          <p>Salvar um formulário mantém as alterações dos demais.</p>
          <div :for={{name, _params} <- @pending_forms} id={"pending-form-#{name}"}>
            <.link href={form_anchor(name)}>{form_label(name)}</.link>
            <button
              id={"discard-form-#{name}"}
              type="button"
              class="btn"
              phx-click="discard-form"
              phx-value-form={name}
              data-confirm="Descartar somente as alterações deste formulário?"
            >Descartar alterações</button>
          </div>
        </section>
        <nav id="authoring-navigation" class="authoring-navigation" aria-label="Seções do editor">
          <.link href="#authoring-overview" class="btn">Visão geral</.link>
          <.link href="#authoring-items" class="btn">Formulário e regras</.link>
          <.link href="#authoring-stages" class="btn">Etapas e caminhos</.link>
          <.link href="#authoring-people" class="btn">Pessoas e permissões</.link>
          <.link href="#workspace-configuration" class="btn">Páginas e visualizações</.link>
          <.link href="#template-review" class="btn">Revisar e publicar</.link>
        </nav>
        <section :if={@conflict} id="draft-conflict" role="alert" class="card template-section">
          <h2>O rascunho foi alterado</h2><p>
            A versão salva está na revisão {@conflict.revision}. Suas alterações não foram aplicadas. Compare e copie o que deseja preservar antes de recarregar.
          </p>
          <div id="conflict-diff" phx-update="stream">
            <article :for={{id, change} <- @streams.conflicts} id={id}>
              <strong>{change.path}</strong><div class="diff-pair">
                <pre aria-label="Salvo no servidor">{json(change.before)}</pre><pre aria-label="Sua alteração">{json(change.after)}</pre>
              </div>
            </article>
          </div>
          <details>
            <summary>Sua definição para recuperar</summary><pre id="conflict-local-json">{@conflict.json}</pre>
          </details>
          <button
            id="reload-draft"
            class="btn"
            phx-click="reload"
            data-confirm="Suas alterações locais serão descartadas. Recarregar?"
          >Recarregar versão salva</button>
        </section>
        <div class="template-grid">
          <section class="card">
            <h2 id="authoring-overview">Visão geral</h2><.form
              for={@metadata_form}
              id="template-metadata"
              phx-submit="metadata"
              phx-change="dirty"
            >
              <.input field={@metadata_form[:name]} label="Nome" required maxlength="200" /><.input
                field={@metadata_form[:description]}
                type="textarea"
                label="Descrição"
                maxlength="10000"
              /><.input
                field={@metadata_form[:template_version]}
                label="Versão do autor (ex.: 1.0.0)"
                required
                pattern="[0-9]+\.[0-9]+\.[0-9]+"
              />
              <button id="save-metadata" class="btn" disabled={@draft.published_version_id != nil}>Salvar identificação</button>
            </.form>
          </section>
          <section class="card">
            <h2 id="authoring-people">Quem desempenha cada papel</h2><p>
              Mapear papéis não concede permissões às pessoas. Somente departamentos locais são aceitos.
            </p><.form
              for={@mapping_form}
              id="template-mappings"
              phx-submit="bindings"
              phx-change="dirty"
            >
              <.input
                :for={role <- @draft.definition["role_requirements"]}
                name={"mapping[roles][#{role["key"]}][]"}
                id={"mapping-role-#{role["key"]}"}
                type="select"
                multiple
                label={role["label"]}
                options={@local_roles}
                value={
                  get_in(@mapping_form.params, ["roles", role["key"]]) ||
                    @draft.bindings["roles"][role["key"]] || []
                }
              />
              <.input
                :for={
                  binding <- Enum.filter(@draft.definition["bindings"], &(&1["type"] == "department"))
                }
                name={"mapping[departments][#{binding["key"]}]"}
                id={"mapping-department-#{binding["key"]}"}
                type="select"
                label={binding["label"]}
                options={@department_options}
                prompt="Não resolvido"
                value={
                  get_in(@mapping_form.params, ["departments", binding["key"]]) ||
                    @draft.bindings["departments"][binding["key"]]
                }
              />
              <.input
                :for={
                  binding <- Enum.filter(@draft.definition["bindings"], &(&1["type"] == "budget"))
                }
                name={"mapping[budgets][#{binding["key"]}]"}
                id={"mapping-budget-#{binding["key"]}"}
                type="select"
                label={binding["label"]}
                options={@budget_options}
                prompt="Selecione um orçamento local"
                value={
                  get_in(@mapping_form.params, ["budgets", binding["key"]]) ||
                    get_in(@draft.bindings, ["budgets", binding["key"]])
                }
              />
              <.input
                name="mapping[assignment]"
                id="mapping-assignment"
                type="select"
                label="Departamento de atribuição inicial"
                options={
                  Enum.map(
                    Enum.filter(@draft.definition["bindings"], &(&1["type"] == "department")),
                    &{&1["label"], &1["key"]}
                  )
                }
                value={
                  @mapping_form.params["assignment"] ||
                    @draft.definition["assignment"]["department_binding"]
                }
              />
              <button id="save-mappings" class="btn" disabled={@draft.published_version_id != nil}>Salvar mapeamentos</button>
            </.form>
          </section>
        </div>
        <section id="authoring-stages" class="card template-section">
          <h2>Etapas e caminhos</h2><p>
            Acompanhe o fluxo de cima para baixo. Escolha uma etapa para destacar suas entradas e saídas.
          </p>
          <div class="graph-toolbar">
            <.form for={@graph_form} id="graph-focus-form" phx-change="focus-stage">
              <.input
                field={@graph_form[:stage]}
                type="select"
                label="Destacar conexões da etapa"
                options={@stage_options}
                prompt="Todas as etapas"
              />
            </.form>
            <div class="graph-legend" aria-label="Legenda das conexões">
              <span><i class="graph-swatch"></i>Avanço</span><span><i class="graph-swatch secondary"></i>Correção e outros caminhos</span>
            </div>
          </div>
          <.workflow_graph graph_width={@graph_width} graph_height={@graph_height} streams={@streams} />
        </section>
        <section class="card template-section">
          <h2 id="authoring-items">Formulário e regras do processo</h2>
          <.link
            :if={Instantflow.WorkflowCatalog.Capabilities.enabled?(@draft.definition, "finance")}
            id="configure-process-budgets"
            href="#template-finance-account"
            class="btn"
          >Configurar contas de orçamento para os vínculos deste processo</.link>
          <.form for={@picker} id="authoring-picker" phx-submit="pick" phx-change="preview-picker">
            <div class="template-grid">
              <.input
                field={@picker[:collection]}
                type="select"
                label="Tipo de item"
                options={@collection_options}
                value={@picker.params["collection"] || @collection}
              />
              <div hidden={(@picker.params["collection"] || @collection) not in ~w(fields access)}>
                <.input
                  field={@picker[:section]}
                  type="select"
                  label="Seção (para campos e permissões)"
                  options={@section_options}
                  value={@parent}
                />
              </div>
              <div hidden={(@picker.params["collection"] || @collection) != "actions"}>
                <.input
                  field={@picker[:transition]}
                  type="select"
                  label="Transição (para ações)"
                  options={@transition_options}
                  value={@parent}
                />
              </div>
            </div><button
              id="add-template-item"
              class="btn"
              data-confirm={
                if Map.has_key?(@pending_forms, "item"), do: "Descartar alterações deste item?"
              }
            >Preparar novo item</button>
          </.form>
          <h3>{if @original, do: "Editar", else: "Adicionar"} {@collection_label}</h3>
          <p id="selected-item">
            {@collection_label} {if @parent, do: "· #{@parent}"} {if @original, do: "· #{@original}"}
          </p>
          <.form for={@item_form} id="template-item-form" phx-submit="save-item" phx-change="dirty">
            <div class="template-grid">
              <div :if={@collection not in ~w(access actions)}>
                <.input
                  field={@item_form[:key]}
                  label="Chave estável"
                  required
                  maxlength="64"
                  pattern="[a-z][a-z0-9_]{0,63}"
                  readonly={@original != nil}
                />
                <.input field={@item_form[:label]} label="Rótulo" required maxlength="200" />
              </div>
              <div :if={@collection == "stages"}>
                <.input field={@item_form[:initial]} type="checkbox" label="Etapa inicial" /><.input
                  field={@item_form[:terminal]}
                  type="checkbox"
                  label="Etapa final"
                />
              </div>
              <div :if={@collection == "roles"}>
                <.input
                  field={@item_form[:creates]}
                  type="checkbox"
                  label="Papel pode criar solicitações"
                />
              </div>
              <div :if={@collection == "communications"} id="communication-authoring">
                <.input
                  field={@item_form[:recipient_relationship]}
                  type="select"
                  label="Vínculo destinatário"
                  options={@relationship_options}
                />
                <.input
                  field={@item_form[:message_fields]}
                  type="select"
                  multiple
                  label="Somente estes campos serão compartilhados"
                  options={@field_options}
                />
                <.input
                  field={@item_form[:manager_roles]}
                  type="select"
                  multiple
                  label="Papéis autorizados a liberar"
                  options={@role_options}
                />
                <.input
                  field={@item_form[:department_binding]}
                  label="Chave do departamento vinculado"
                />
                <.input
                  field={@item_form[:behavior]}
                  type="select"
                  label="Simulação"
                  options={Enum.map(~w(success fail_once failure ambiguous), &{&1, &1})}
                />
              </div>
              <div :if={@collection == "participants"}>
                <.input
                  field={@item_form[:kind]}
                  type="select"
                  label="Tipo de participante"
                  options={[
                    {"Externo", "external"},
                    {"Solicitante", "requester"},
                    {"Sujeito", "subject"}
                  ]}
                />
                <.input
                  field={@item_form[:candidate_roles]}
                  type="select"
                  multiple
                  label="Papéis elegíveis para o relacionamento (sem conceder acesso)"
                  options={@role_options}
                />
                <.input
                  field={@item_form[:manager_roles]}
                  type="select"
                  multiple
                  label="Papéis que verificam o relacionamento"
                  options={@role_options}
                />
                <.input
                  field={@item_form[:department_binding]}
                  label="Chave do departamento verificador"
                />
              </div>
              <div :if={@collection == "sections"}>
                <.input
                  field={@item_form[:classification]}
                  type="select"
                  label="Classificação"
                  options={[{"Interna", "internal"}, {"Restrita", "restricted"}]}
                />
              </div>
              <div :if={@collection == "fields"}>
                <.input
                  field={@item_form[:type]}
                  type="select"
                  label="Tipo do campo"
                  options={@field_types}
                /><.input
                  field={@item_form[:options]}
                  type="textarea"
                  label="Opções (uma por linha; apenas para escolhas)"
                /><.input
                  field={@item_form[:currency]}
                  label="Moeda (apenas para dinheiro)"
                  maxlength="3"
                /><p>
                  Referências exigem um relacionamento declarado e verificado. Arquivos exigem envio privado, vínculo autorizado e revisão manual.
                </p>
                <.input
                  field={@item_form[:reference_target]}
                  type="select"
                  label="Alvo (apenas para referência de diretório)"
                  options={[
                    {"Não configurado", ""},
                    {"Participante", "participant"},
                    {"Sujeito autenticado", "subject"}
                  ]}
                />
                <.input
                  field={@item_form[:reference_relationship]}
                  label="Chave do relacionamento de referência"
                />
                <.input
                  field={@item_form[:document_reviewers]}
                  type="select"
                  multiple
                  label="Papéis revisores (apenas para documento privado)"
                  options={@role_options}
                />
                <.input
                  field={@item_form[:document_department]}
                  label="Chave do departamento revisor do documento"
                />
                <.input
                  field={@item_form[:document_max_bytes]}
                  type="number"
                  label="Limite do documento em bytes"
                  min="1"
                  max="5242880"
                />
                <.input
                  field={@item_form[:document_media_types]}
                  type="select"
                  multiple
                  label="Formatos do documento"
                  options={[{"PDF", "application/pdf"}, {"PNG", "image/png"}, {"JPEG", "image/jpeg"}]}
                />
              </div>
              <div :if={@collection == "access"}>
                <.input field={@item_form[:role]} type="select" label="Papel" options={@role_options} /><.input
                  field={@item_form[:scope]}
                  type="select"
                  label="Escopo"
                  options={[
                    {"Próprio solicitante", "requester"},
                    {"Departamento atribuído", "assigned_department"},
                    {"Responsável verificado", "guardian"},
                    {"Participante verificado", "participant"},
                    {"Pessoa atribuída", "assigned_user"},
                    {"Departamento fixo do fluxo", "workflow_department"}
                  ]}
                /><.input field={@item_form[:read]} type="checkbox" label="Pode ler a seção" /><.input
                  field={@item_form[:edit_stages]}
                  type="select"
                  multiple
                  label="Etapas que permitem edição"
                  options={@stage_options}
                />
              </div>
              <.input
                :if={@collection == "access"}
                field={@item_form[:relationship]}
                label="Chave do relacionamento (escopo participante)"
              />
              <.input
                :if={@collection in ["access", "transitions"]}
                field={@item_form[:department_binding]}
                label="Chave do departamento local (escopo fixo ou destino da transição)"
              />
              <div :if={@collection == "views"}>
                <.input
                  field={@item_form[:visibility_roles]}
                  type="select"
                  multiple
                  label="Visibilidade (vazio usa acesso ao registro)"
                  options={@role_options}
                />
                <.input
                  field={@item_form[:view_filters]}
                  type="select"
                  multiple
                  label="Filtros por campos escalares"
                  options={@field_options}
                />
                <.input
                  field={@item_form[:sort_field]}
                  type="select"
                  label="Ordenar por"
                  options={[
                    {"Registro", "id"},
                    {"Etapa", "stage"},
                    {"Urgência declarada", "urgency"} | @field_options
                  ]}
                />
                <.input
                  field={@item_form[:sort_direction]}
                  type="select"
                  label="Direção"
                  options={[{"Crescente", "asc"}, {"Decrescente", "desc"}]}
                />
                <.input
                  field={@item_form[:calendar_field]}
                  type="select"
                  label="Data/instante do calendário"
                  prompt="Não configurado"
                  options={@field_options}
                />
                <.input
                  field={@item_form[:urgency_field]}
                  type="select"
                  label="Campo de urgência"
                  prompt="Não configurado"
                  options={@field_options}
                />
                <.input
                  field={@item_form[:urgency_values]}
                  type="textarea"
                  label="Urgências em ordem (a primeira é a mais alta)"
                />
                <.input
                  field={@item_form[:assignment_section]}
                  type="select"
                  label="Seção com atribuição nominal"
                  prompt="Não configurado"
                  options={@section_options}
                />
                <.input
                  field={@item_form[:type]}
                  type="select"
                  label="Visualização"
                  options={[
                    {"Tabela", "table"},
                    {"Quadro por etapa", "board"},
                    {"Calendário", "calendar"},
                    {"Atribuições", "assignments"}
                  ]}
                /><.input
                  field={@item_form[:columns]}
                  type="select"
                  multiple
                  label="Colunas"
                  options={[{"Etapa", "stage"} | @field_options]}
                />
              </div>
              <div :if={@collection == "actions"}>
                <.input
                  field={@item_form[:type]}
                  type="select"
                  label="Ação simulada"
                  options={[
                    {"Notificação simulada", "simulate_notification"},
                    {"Provisionamento simulado", "simulate_provisioning"},
                    {"Pagamento simulado", "simulate_payment"}
                  ]}
                /><.input
                  field={@item_form[:behavior]}
                  type="select"
                  label="Resultado simulado"
                  options={[
                    {"Sucesso", "success"},
                    {"Falha na primeira tentativa", "fail_once"},
                    {"Falha", "failure"}
                  ]}
                />
              </div>
              <div :if={@collection == "transitions"}>
                <.input
                  field={@item_form[:from]}
                  type="select"
                  label="Origem"
                  options={@stage_options}
                /><.input
                  field={@item_form[:to]}
                  type="select"
                  label="Destino"
                  options={@stage_options}
                /><.input
                  field={@item_form[:kind]}
                  type="select"
                  label="Tipo de transição"
                  options={[
                    {"Avançar", "forward"},
                    {"Pedir correção", "correction"},
                    {"Reenviar", "resubmission"},
                    {"Rejeitar", "rejection"},
                    {"Cancelar", "cancellation"},
                    {"Reabrir", "reopening"}
                  ]}
                /><.input
                  field={@item_form[:requester_roles]}
                  type="select"
                  multiple
                  label="Papéis do próprio solicitante"
                  options={@role_options}
                /><.input
                  field={@item_form[:department_roles]}
                  type="select"
                  multiple
                  label="Papéis no departamento atribuído"
                  options={@role_options}
                /><.input
                  field={@item_form[:required_fields]}
                  type="select"
                  multiple
                  label="Campos obrigatórios para avançar"
                  options={@field_options}
                />
              </div>
              <div :if={@collection == "transitions"}>
                <.input
                  field={@item_form[:reset_enabled]}
                  type="checkbox"
                  label="Invalidação explícita nesta transição"
                />
                <.input
                  field={@item_form[:reset_sections]}
                  type="select"
                  multiple
                  label="Seções a limpar"
                  options={@section_options}
                />
                <.input
                  field={@item_form[:invalidate_approvals]}
                  type="select"
                  multiple
                  label="Seções de aprovação a invalidar"
                  options={@section_options}
                />
                <.input field={@item_form[:require_reason]} type="checkbox" label="Exigir motivo" /><.input
                  field={@item_form[:disallow_requester]}
                  type="checkbox"
                  label="Impedir aprovação pelo próprio solicitante"
                /><.input
                  field={@item_form[:finance_sensitive]}
                  type="checkbox"
                  label="Decisão financeira sensível"
                /><.input
                  field={@item_form[:history_visibility]}
                  type="select"
                  label="Visibilidade do histórico"
                  options={[{"Participantes", "participants"}, {"Somente atores", "actors"}]}
                />
                <.input
                  field={@item_form[:guard_communication]}
                  type="select"
                  label="Comunicação exigida"
                  prompt="Selecione"
                  options={@communication_options}
                />
                <.input
                  field={@item_form[:guard_op]}
                  type="select"
                  label="Condição para avançar"
                  options={[
                    {"Sem condição adicional", ""},
                    {"Campo preenchido", "present"},
                    {"Igual", "eq"},
                    {"Maior que", "gt"},
                    {"Maior ou igual", "gte"},
                    {"Menor que", "lt"},
                    {"Menor ou igual", "lte"},
                    {"Pertence à lista", "in"},
                    {"Entrega simulada concluída", "delivery_succeeded"},
                    {"Comunicação selecionada concluída", "communication_succeeded"},
                    {"Arquivo disponível", "attachment_ready"},
                    {"Todas as condições", "all"},
                    {"Qualquer condição", "any"}
                  ]}
                />
                <.input
                  field={@item_form[:guard_field]}
                  type="select"
                  label="Campo da condição"
                  options={@field_options}
                  prompt="Selecione"
                /><.input
                  field={@item_form[:guard_value]}
                  label="Valor (número, true/false, texto ou lista JSON)"
                /><.input
                  field={@item_form[:guard_kind]}
                  type="select"
                  label="Entrega da condição"
                  options={[
                    {"Notificação simulada", "simulate_notification"},
                    {"Provisionamento simulado", "simulate_provisioning"},
                    {"Pagamento simulado", "simulate_payment"}
                  ]}
                />
                <details>
                  <summary>Condições agrupadas (JSON declarativo)</summary><.input
                    field={@item_form[:guard_json]}
                    type="textarea"
                    label="Grupo all/any; máximo de 8 níveis e 20 condições por grupo"
                  />
                </details>
              </div>
            </div><button
              id="save-template-item"
              class="btn primary"
              disabled={@draft.published_version_id != nil or @conflict != nil}
              phx-disable-with="Salvando…"
            >Salvar item no rascunho</button>
          </.form>
          <div id="template-items" phx-update="stream" class="template-items">
            <article :for={{id, item} <- @streams.items} id={id} class="request-row">
              <div>
                <small>{item.kind}</small><strong>{item.label}</strong><small>{item.detail}</small>
              </div>
              <div :if={item.collection == "stages"} class="flex gap-2">
                <button
                  id={"move-up-#{item.id}"}
                  class="btn"
                  phx-click="move-stage"
                  phx-value-key={item.key}
                  phx-value-direction="up"
                  aria-label={"Mover #{item.label} para cima"}
                  disabled={item.first? or @draft.published_version_id != nil}
                >
                  Subir
                </button>
                <button
                  id={"move-down-#{item.id}"}
                  class="btn"
                  phx-click="move-stage"
                  phx-value-key={item.key}
                  phx-value-direction="down"
                  aria-label={"Mover #{item.label} para baixo"}
                  disabled={item.last? or @draft.published_version_id != nil}
                >
                  Descer
                </button>
              </div><button
                id={"edit-#{item.id}"}
                class="btn"
                phx-click="edit"
                phx-value-collection={item.collection}
                phx-value-parent={item.parent}
                phx-value-key={item.key}
                data-confirm={
                  if Map.has_key?(@pending_forms, "item"), do: "Descartar alterações deste item?"
                }
              >Editar</button><button
                id={"remove-#{item.id}"}
                class="btn"
                phx-click="remove"
                phx-value-collection={item.collection}
                phx-value-parent={item.parent}
                phx-value-key={item.key}
                disabled={@draft.published_version_id != nil}
                data-confirm="Remover este item? Referências pendentes impedirão a publicação."
              >Remover</button>
            </article>
          </div>
        </section>
        <.workspace_panel
          pending_forms={@pending_forms}
          budget_binding_options={@budget_binding_options}
          close_options={@close_options}
          communication_options={@communication_options}
          department_options={@department_options}
          draft={@draft}
          field_options={@field_options}
          finance_account_form={@finance_account_form}
          interface_blocks={@interface_blocks}
          interface_page_form={@interface_page_form}
          interface_pages={@interface_pages}
          participant_audience_options={@participant_audience_options}
          role_options={@role_options}
          transition_options={@transition_options}
          workspace_form={@workspace_form}
        />
        <section class="card template-section" id="template-review">
          <h2>Revisão antes de publicar</h2><p :for={warning <- @review_warnings}>{warning}</p><div
            id="publication-errors"
            role="status"
          >
            <p :if={@review_errors != []}>Corrija os pontos abaixo antes de publicar:</p>
            <p :for={error <- @review_errors}>
              <.link href={review_error_anchor(error)}>{error}</.link>
            </p>
          </div>
          <.participant_preview_panel
            draft={@draft}
            preview={@preview}
            preview_form={@preview_form}
            role_options={@role_options}
            stage_options={@stage_options}
          />
          <h3>Comparação com a versão de origem</h3><div id="template-diff" phx-update="stream">
            <p id="template-diff-empty" class="empty-state">Nenhuma alteração.</p><article
              :for={{id, change} <- @streams.changes}
              id={id}
            >
              <strong>{change.path}</strong><div class="diff-pair">
                <pre aria-label="Antes">{json(change.before)}</pre><pre aria-label="Depois">{json(change.after)}</pre>
              </div>
            </article>
          </div>
          <h3>Prévia de papéis — somente definição, sem registros reais</h3><div
            id="role-preview"
            phx-update="stream"
          >
            <article :for={{id, role} <- @streams.roles} id={id} class="role-preview">
              <h4>{role.label}</h4><p>
                {if role.creates?,
                  do: "Pode iniciar solicitações conforme o mapeamento local.",
                  else: "Não inicia solicitações."}
              </p><p :for={section <- role.sections}>
                {section.label} · {classification_label(section.classification)} · {scope_label(
                  section.scope
                )} · Leitura: {if section.read?,
                  do: "sim",
                  else: "não"} · Edição: {Enum.join(section.edits, ", ")}
              </p><p :for={transition <- role.transitions}>
                {transition.label}: {transition.from} → {transition.to} · {scope_label(
                  transition.scope
                )}
              </p>
            </article>
          </div>
          <p id="publication-availability" role="status">
            <%= cond do %>
              <% @draft.published_version_id != nil -> %>
                Esta versão já está publicada. Clone-a na lista de modelos para continuar editando.
              <% @conflict != nil -> %>
                Resolva o conflito de revisão antes de publicar.
              <% @unsaved -> %>
                Salve ou descarte cada formulário pendente antes de publicar.
              <% @review_errors != [] -> %>
                A publicação ficará disponível após corrigir os pontos da revisão.
              <% true -> %>
                Pronto para revisar e confirmar a publicação.
            <% end %>
          </p>
          <button
            id="publish-template"
            class="btn primary"
            phx-click="review-publication"
            disabled={
              @draft.published_version_id != nil or @review_errors != [] or @unsaved or
                @conflict != nil
            }
          >Publicar versão revisada</button>
          <section
            :if={@publication_confirmation}
            id="publication-confirmation"
            role="group"
            aria-labelledby="publication-confirmation-title"
            class="card"
          >
            <h3 id="publication-confirmation-title">Confirmar publicação</h3>
            <p>
              Publicar a definição e os mapeamentos revisados? Solicitações existentes manterão suas versões.
            </p>
            <button
              id="confirm-publish-template"
              class="btn primary"
              phx-click="publish"
              disabled={
                @draft.published_version_id != nil or @review_errors != [] or @unsaved or
                  @conflict != nil
              }
              phx-disable-with="Publicando…"
            >Confirmar publicação</button>
            <button id="cancel-publish-template" class="btn" phx-click="cancel-publication">Continuar revisão</button>
          </section>
          <button id="export-draft" class="btn" phx-click="export">Revisar exportação do rascunho</button>
        </section>
        <section :if={@export} id="draft-export-preview" class="card template-section">
          <h2>Exportação: {@export.status}</h2><p>
            Somente a definição. Rótulos e regras podem revelar práticas internas; revise antes de compartilhar.
          </p><p>SHA-256: <code>{@export.digest}</code></p><pre id="draft-export-json">{@export.json}</pre><a
            id="download-draft"
            class="btn"
            href={"data:application/json;charset=utf-8," <> URI.encode(@export.json, &URI.char_unreserved?/1)}
            download="modelo-rascunho.json"
          >Baixar rascunho revisado</a>
        </section>
        <details class="card template-section">
          <summary>Definição completa (JSON declarativo)</summary><p>
            Todos os recursos do modelo podem ser revisados aqui. Código executável e propriedades desconhecidas são rejeitados.
          </p><.form
            for={@advanced_form}
            id="advanced-template-form"
            phx-submit="advanced"
            phx-change="dirty"
          >
            <.input
              field={@advanced_form[:json]}
              type="textarea"
              label="Definição"
              maxlength="1048576"
            /><button
              id="save-advanced-template"
              class="btn"
              disabled={@draft.published_version_id != nil}
            >Validar e salvar rascunho</button>
          </.form>
        </details>
      </div>
    </Layouts.app>
    """
  end
end
