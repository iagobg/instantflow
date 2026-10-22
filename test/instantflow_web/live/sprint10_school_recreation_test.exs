defmodule InstantflowWeb.Sprint10SchoolRecreationTest do
  use InstantflowWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Instantflow.IdentityFixtures

  alias Instantflow.{
    Access,
    Identity,
    BuilderFixtures,
    Delivery,
    Finance,
    Participants,
    PrivateDocuments,
    Repo,
    WorkflowRuntime
  }

  alias Instantflow.Sprint10RecreationFixtures, as: Copy
  alias Instantflow.WorkflowCatalog.{Templates, Interchange, Version}

  test "copied enrollment: invited family corrects private documents, minimum IT view and simulated retry" do
    admin = staff_fixture()
    admission = actor(admin, "admissions")
    academic = actor(admin, "head")
    finance = actor(admin, "finance")
    it = actor(admin, "it")
    family = BuilderFixtures.invite_external(admin, "family-#{Ecto.UUID.generate()}@example.test")
    other = BuilderFixtures.invite_external(admin, "family-#{Ecto.UUID.generate()}@example.test")
    d = Copy.definition("enrollment")

    v =
      install(admin, d, %{
        "guardian" => ["external"],
        "admissions" => ["admissions"],
        "academic" => ["head"],
        "finance" => ["finance"],
        "it" => ["it"]
      })

    id = create(admission, v)
    link(admission, family, id, Copy.key("family"))

    path =
      ~p"/o/horizonte/processos/#{v.workflow_id}/participacao/copy_family_portal/registros/#{id}"

    {:ok, portal, _} = live(login(build_conn(), family), path)

    for {field, value} <- [
          {"student_name", "Estudante sintético"},
          {"guardian_name", "Família sintética"},
          {"school_year", "Ano fictício"}
        ] do
      portal
      |> form("[id='participant-field-#{Copy.ref("application." <> field)}']",
        field: %{value: value}
      )
      |> render_submit()
    end

    upload =
      file_input(portal, "#participant-upload", :document, [
        %{
          name: "copy.pdf",
          content: Instantflow.EnrollmentFixtures.pdf(),
          type: "application/pdf",
          last_modified: 1
        }
      ])

    render_upload(upload, "copy.pdf")

    portal
    |> form("#participant-upload", upload: %{target: Copy.ref("application.document")})
    |> render_submit()

    portal |> form("#actions-copy_submit") |> render_submit()
    transition(admission, v, id, "correct", "Corrija o documento sintético")
    send(portal.pid, :reconcile)
    assert has_element?(portal, "#actions-copy_resubmit")
    portal |> form("#actions-copy_resubmit") |> render_submit()
    [doc] = PrivateDocuments.list(admission, id)
    staff = record(admission, v, id)
    staff |> element("#release-private-#{doc.id}") |> render_click()
    save(admission, v, id, "identity", %{"display_name" => "Identidade mínima"})
    transition(admission, v, id, "verify")

    save(academic, v, id, "placement", %{
      "class" => "Turma fictícia",
      "assessment" => "INTERNAL-ASSESSMENT"
    })

    transition(academic, v, id, "place")
    process_delivery(finance, id, "simulate_payment")
    save(finance, v, id, "payment", %{"reference" => "DEPOSIT-PRIVATE"})
    transition(finance, v, id, "paid")
    process_delivery(it, id, "simulate_provisioning")
    it_page = record(it, v, id)
    assert has_element?(it_page, "#sections", "Identidade mínima")
    refute has_element?(it_page, "#sections", "INTERNAL-ASSESSMENT")
    refute has_element?(it_page, "#sections", "DEPOSIT-PRIVATE")
    {:ok, it_data} = WorkflowRuntime.get(it, id)
    [failed] = Enum.filter(it_data.deliveries, &(&1.kind == "simulate_provisioning"))
    it_page |> element("#retry-#{failed.id}") |> render_click()
    assert {:ok, _} = Delivery.process(1, failed.id)
    transition(it, v, id, "finish")
    assert_stage(it, id, "complete")
    assert WorkflowRuntime.search(other).total == 0

    assert {:error, :not_found} =
             Instantflow.WorkflowRuntime.ParticipantPages.get(
               other,
               v.workflow_id,
               Copy.key("family_portal"),
               id
             )

    assert {:ok, _} =
             Instantflow.Delivery.Curated.release(
               admission,
               id,
               Copy.key("admission_notice"),
               family.id,
               revision(admission, id),
               Ecto.UUID.generate()
             )

    {:ok, inbox, _} =
      live(login(build_conn(), family), ~p"/o/horizonte/processos/#{v.workflow_id}/comunicacoes")

    assert has_element?(inbox, "#message-count", "1 mensagem")
  end

  test "copied incident: named confidential assignment, bounded triage and curated-only recipient with retry" do
    admin = staff_fixture()
    teacher = actor(admin, "teacher")
    dean = actor(admin, "dean")
    counselor = actor(admin, "counselor")

    family =
      BuilderFixtures.invite_external(admin, "contact-#{Ecto.UUID.generate()}@example.test")

    v =
      install(admin, Copy.definition("incident"), %{
        "teacher" => ["teacher"],
        "dean" => ["dean"],
        "counselor" => ["counselor"],
        "recipient" => ["external"]
      })

    id = create(teacher, v)

    save(teacher, v, id, "report", %{
      "facts" => "Relato factual",
      "students" => "Pessoa fictícia",
      "occurred_at" => "2026-10-22T10:00:00Z",
      "location" => "Local fictício",
      "urgency" => "Urgente"
    })

    transition(teacher, v, id, "submit")
    dean_page = record(dean, v, id)

    dean_page
    |> form("#assignment-form-copy_support",
      assignment: %{membership_id: counselor.id, reason: "Designação explícita"}
    )
    |> render_submit()

    save(dean, v, id, "discipline", %{"triage" => "Revisão"})
    transition(dean, v, id, "triage")
    save(counselor, v, id, "support", %{"notes" => "CONFIDENTIAL-SUPPORT"})
    save(dean, v, id, "discipline", %{"resolution" => "Resolução registrada"})

    save(dean, v, id, "communication", %{
      "recipient" => "Contato fictício",
      "message" => "CURATED-ONLY"
    })

    link(dean, family, id, Copy.key("contact"))
    transition(dean, v, id, "communicate")
    dean_page = record(dean, v, id)

    dean_page
    |> form("#release-copy_resolution_notice", release: %{recipient: family.id})
    |> render_submit()

    [message] = Instantflow.Delivery.Curated.inbox(family, v.workflow_id).rows
    assert {:ok, %{status: "failed"}} = Delivery.process(1, message.id)
    dean_page |> element("#refresh-request") |> render_click()
    dean_page |> element("#retry-curated-#{message.id}") |> render_click()
    assert {:ok, %{status: "succeeded"}} = Delivery.process(1, message.id)
    transition(dean, v, id, "close")
    assert_stage(dean, id, "closed")

    {:ok, inbox, _} =
      live(login(build_conn(), family), ~p"/o/horizonte/processos/#{v.workflow_id}/comunicacoes")

    assert has_element?(inbox, "#curated-inbox dd", "CURATED-ONLY")
    refute has_element?(inbox, "#curated-inbox", "CONFIDENTIAL-SUPPORT")
    assert {:error, :not_found} = WorkflowRuntime.get(family, id)
    assert {:error, :not_found} = WorkflowRuntime.get(admin, id)
    teacher_page = record(teacher, v, id)
    refute has_element?(teacher_page, "#sections", "CONFIDENTIAL-SUPPORT")
    refute has_element?(teacher_page, "#history", "CONFIDENTIAL-SUPPORT")

    {:ok, dashboard, _} =
      live(login(build_conn(), dean), ~p"/o/horizonte/processos/#{v.workflow_id}")

    assert has_element?(dashboard, "#open-process-record-#{id}")
  end

  for name <- ~w(requisition field_trip) do
    @name name
    test "copied #{@name}: generated finance, explicit renewed review and completion" do
      name = @name
      admin = staff_fixture()
      requester = actor(admin, "teacher")
      head = actor(admin, "head")
      finance = actor(admin, "finance")
      {:ok, _} = Access.grant(admin, finance.id, finance.department_id, "finance_allocator")
      finance = Identity.scope(finance.user_id, 1)
      operations = actor(admin, "operations")
      safety = actor(admin, "dean")

      {:ok, account} =
        Finance.create_account(admin, finance.department_id, "Conta da cópia #{name}")

      {:ok, _} =
        Finance.allocate(finance, account.id, 10000, "Dotação sintética", Ecto.UUID.generate())

      v =
        install(
          admin,
          Copy.definition(name),
          %{
            "requester" => ["teacher"],
            "head" => ["head"],
            "finance" => ["finance"],
            "operations" => ["operations"],
            "safety" => ["dean"],
            "reverser" => ["finance_reverser"]
          },
          account.id
        )

      id = create(requester, v)

      values = %{
        "summary" => "Proposta sintética",
        "justification" => "Finalidade",
        "quantity" => "4",
        "amount" => "4000"
      }

      values =
        if name == "field_trip",
          do:
            Map.merge(values, %{
              "date" => "2026-11-12",
              "destination" => "Destino",
              "itinerary" => "Roteiro",
              "risks" => "Supervisão"
            }),
          else: values

      save(requester, v, id, "request", values)
      transition(requester, v, id, "submit")
      transition(head, v, id, "academic_approve")
      transition(finance, v, id, "reserve")
      transition(operations, v, id, "revise_purchase", "Renovar revisão explícita")
      assert_stage(requester, id, "draft")
      transition(requester, v, id, "submit")
      transition(head, v, id, "academic_approve")
      transition(finance, v, id, "reserve")
      save(operations, v, id, "order", %{"reference" => "Transação simulada"})
      transition(operations, v, id, "order")

      if name == "requisition" do
        save(operations, v, id, "delivery", %{"received" => "2"})

        assert {:error, :incomplete_delivery} =
                 Instantflow.WorkflowFixtures.transition(operations, id, Copy.key("finish"))

        save(operations, v, id, "delivery", %{"received" => "4"})
        transition(operations, v, id, "finish")
      else
        save(safety, v, id, "safety", %{"confirmed" => "true"})
        transition(safety, v, id, "approve")
      end

      assert_stage(operations, id, "complete")

      {:ok, dashboard, _} =
        live(login(build_conn(), finance), ~p"/o/horizonte/processos/#{v.workflow_id}")

      assert has_element?(dashboard, "#process-finance-summary", "4000")
      assert has_element?(dashboard, "#open-process-record-#{id}")
    end
  end

  defp actor(admin, role) do
    member = staff_fixture("staff")
    {:ok, _} = Access.grant(admin, member.id, member.department_id, role)
    Identity.scope(member.user_id, member.organization_id)
  end

  defp install(admin, d, roles, account \\ nil) do
    {:ok, draft} = Templates.import(admin, Interchange.encode(d))
    {:ok, editor, _} = live(login(build_conn(), admin), ~p"/o/horizonte/modelos/#{draft.id}")

    departments =
      for b <- d["bindings"],
          b["type"] == "department",
          into: %{},
          do: {b["key"], admin.department_id}

    mapping = %{
      "roles" => Map.new(roles, fn {k, v} -> {Copy.key(k), v} end),
      "departments" => departments,
      "assignment" => d["assignment"]["department_binding"]
    }

    mapping =
      if account,
        do: Map.put(mapping, "budgets", %{Copy.key("shared_budget") => account}),
        else: mapping

    editor |> form("#template-mappings", mapping: mapping) |> render_submit()
    refute has_element?(editor, "#publish-template[disabled]")
    editor |> element("#publish-template") |> render_click()
    {:ok, saved} = Templates.get(admin, draft.id)
    Repo.get!(Version, saved.published_version_id)
  end

  defp create(actor, v) do
    {:ok, result} =
      WorkflowRuntime.command(actor, %{
        "operation" => "create",
        "workflow_id" => v.workflow_id,
        "key" => Ecto.UUID.generate()
      })

    result["ticket_id"]
  end

  defp record(actor, v, id) do
    {:ok, page, _} =
      live(
        login(build_conn(), actor),
        ~p"/o/horizonte/processos/#{v.workflow_id}/registros/#{id}"
      )

    page
  end

  defp save(actor, v, id, section, values) do
    page = record(actor, v, id)

    page
    |> form("#section-form-#{Copy.key(section)}",
      section: Map.new(values, fn {k, v} -> {Copy.key(k), v} end)
    )
    |> render_submit()

    refute has_element?(page, "#flash-error")
  end

  defp transition(actor, v, id, edge, reason \\ "") do
    page = record(actor, v, id)

    page
    |> form("#transition-form", action: %{reason: reason})
    |> render_submit(%{"transition" => Copy.key(edge)})

    refute has_element?(page, "#flash-error")
  end

  defp link(actor, member, id, relationship) do
    for {operation, revision} <- [{"create", 0}, {"verify", 1}] do
      {:ok, _} =
        Participants.command(
          actor,
          BuilderFixtures.participant_command(id, member.id, operation, revision)
          |> Map.put("relationship", relationship)
        )
    end
  end

  defp process_delivery(actor, id, kind) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    message = Enum.find(data.deliveries, &(&1.kind == kind))
    assert {:ok, _} = Delivery.process(1, message.id)
  end

  defp revision(actor, id) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    data.ticket.revision
  end

  defp assert_stage(actor, id, stage) do
    {:ok, data} = WorkflowRuntime.get(actor, id)
    assert data.ticket.stage == Copy.key(stage)
  end
end
