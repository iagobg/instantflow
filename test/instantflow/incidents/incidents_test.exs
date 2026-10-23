defmodule Instantflow.IncidentsTest do
  use Instantflow.DataCase, async: false
  import Instantflow.IncidentFixtures
  import Instantflow.FinanceFixtures, only: [save: 4]
  import Instantflow.WorkflowFixtures, only: [transition: 3]
  alias Instantflow.{Delivery, PrivateDocuments, WorkflowRuntime}
  alias Instantflow.WorkflowCatalog.Views

  test "named counselor alone sees support notes; dean and teacher have separate projections" do
    f = incident_fixture()
    id = report(f)
    assert {:error, :not_found} = WorkflowRuntime.get(f.counselor, id)
    followup(f, id)
    assert {:ok, _} = save(f.counselor, id, "support", %{"notes" => "SEGREDO_ORIENTACAO"})

    assert {:ok, _} =
             save(f.dean, id, "discipline", %{
               "triage" => "Triagem",
               "actions" => "MEDIDA_INTERNA",
               "resolution" => "Resolução fictícia"
             })

    for actor <- [f.teacher, f.dean] do
      {:ok, data} = WorkflowRuntime.get(actor, id)
      refute Enum.any?(data.sections, &(&1.key == "support"))
      refute Enum.any?(data.events, &(&1.operation == "save:support"))
      refute inspect(data) =~ "SEGREDO_ORIENTACAO"
      refute inspect(Views.search(actor, f.version.workflow_id, "triage")) =~ "SEGREDO_ORIENTACAO"
      refute inspect(Views.search(actor, f.version.workflow_id, "triage")) =~ "SEGREDO_ORIENTACAO"
    end

    assert {:error, :not_found} = WorkflowRuntime.get(f.other_counselor, id)

    assert {:error, :not_found} =
             WorkflowRuntime.get(Instantflow.IdentityFixtures.staff_fixture("parent"), id)

    {:ok, counselor} = WorkflowRuntime.get(f.counselor, id)

    assert Enum.find(counselor.sections, &(&1.key == "support")).values["notes"] ==
             "SEGREDO_ORIENTACAO"

    refute Enum.any?(counselor.sections, &(&1.key in ~w(discipline communication)))
    refute inspect(counselor) =~ "MEDIDA_INTERNA"
  end

  test "closure waits for resolution and curated simulated communication outcome" do
    f = incident_fixture()
    id = report(f)
    followup(f, id)
    assert {:error, :required_fields} = transition(f.dean, id, "communicate")

    assert {:ok, _} =
             save(f.dean, id, "discipline", %{
               "triage" => "Triagem",
               "resolution" => "Resolução fictícia"
             })

    assert {:ok, _} =
             save(f.dean, id, "communication", %{
               "recipient" => "Contato fictício",
               "message" => "Mensagem pública curada"
             })

    assert {:ok, _} = transition(f.dean, id, "communicate")
    assert {:error, :guard_failed} = transition(f.dean, id, "close")
    Delivery.drain()
    {:ok, data} = WorkflowRuntime.get(f.dean, id)
    message = Enum.find(data.deliveries, &(&1.kind == "simulate_notification"))
    assert message.status == "failed"
    assert {:ok, _} = Delivery.retry(f.dean, message.id)
    Delivery.drain()
    assert {:ok, _} = transition(f.dean, id, "close")
    assert {:error, :forbidden} = transition(f.teacher, id, "close")
  end

  test "assignment revisions, target grants and revoke reauthorize private documents" do
    f = incident_fixture()
    id = report(f)
    {:ok, data} = WorkflowRuntime.get(f.dean, id)
    command = assignment_command(id, data.ticket.revision, f.counselor.id, "Atribuição fictícia")
    assert {:ok, result} = WorkflowRuntime.command(f.dean, command)
    assert {:ok, ^result} = WorkflowRuntime.command(f.dean, command)

    assert {:error, :conflict} =
             WorkflowRuntime.command(f.dean, %{
               command
               | "key" => Instantflow.WorkflowFixtures.key()
             })

    assert {:error, :invalid_assignee} = assign(f.dean, id, f.teacher.id, "Sem perfil")
    assert {:error, :forbidden} = assign(f.teacher, id, f.teacher.id, "Forjado")
    assert {:ok, _} = save(f.dean, id, "discipline", %{"triage" => "Triagem"})
    assert {:ok, _} = transition(f.dean, id, "triage")
    pdf = "%PDF-1.4\nFICTICIO\n%%EOF"

    assert {:ok, file} =
             PrivateDocuments.upload(
               f.counselor,
               id,
               "support",
               "attachment",
               "ficticio.pdf",
               pdf
             )

    assert {:error, :not_found} = PrivateDocuments.download(f.counselor, file.object_key)
    assert {:error, :forbidden} = PrivateDocuments.review(f.counselor, file.object_key, true)
    assert {:ok, _} = assign(f.dean, id, f.other_counselor.id, "Revisão independente")
    assert {:ok, _} = PrivateDocuments.review(f.other_counselor, file.object_key, true)
    assert {:ok, _} = assign(f.dean, id, f.counselor.id, "Retomar acompanhamento")
    assert {:ok, %{content: ^pdf}} = PrivateDocuments.download(f.counselor, file.object_key)
    assert PrivateDocuments.list(f.dean, id) == []
    assert {:error, :not_found} = PrivateDocuments.download(f.dean, file.object_key)
    assert {:ok, _} = assign(f.dean, id, nil, "Revogar acompanhamento")
    assert {:error, :not_found} = WorkflowRuntime.get(f.counselor, id)
    assert {:error, :not_found} = PrivateDocuments.download(f.counselor, file.object_key)
  end
end
