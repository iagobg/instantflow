defmodule Instantflow.PrivateDocumentsTest do
  use Instantflow.DataCase, async: true
  import Instantflow.EnrollmentFixtures
  alias Instantflow.{Enrollment, PrivateDocuments, Repo}
  alias Instantflow.Enrollment.Document

  test "private lifecycle rejects spoofed bytes, enforces quarantine and deletes retained content" do
    f = enrollment_fixture()

    assert {:error, :invalid_file} =
             Enrollment.upload(f.parent, f.enrollment.id, "fake.pdf", "<html>unsafe</html>")

    assert {:error, :invalid_file} =
             Enrollment.upload(f.parent, f.enrollment.id, "../x.pdf", pdf())

    assert {:error, :invalid_file} =
             Enrollment.upload(f.parent, f.enrollment.id, "x.pdf", "%PDF-1.4 /JavaScript %%EOF")

    assert {:error, :invalid_file} =
             Enrollment.upload(f.parent, f.enrollment.id, "x.pdf", :binary.copy("x", 5_242_881))

    {:ok, doc} = Enrollment.upload(f.parent, f.enrollment.id, "x.pdf", pdf())
    assert {:error, :not_found} = PrivateDocuments.download(f.parent, doc.object_key)
    assert {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    assert {:ok, %{content: bytes}} = PrivateDocuments.download(f.parent, doc.object_key)
    assert bytes == pdf()
    assert {:error, :invalid_state} = PrivateDocuments.review(f.admin, doc.object_key, true)
    assert {:ok, :ok} = PrivateDocuments.delete(f.parent, doc.object_key)
    assert Repo.get_by!(Document, object_key: doc.object_key).content == <<>>
    assert {:error, :not_found} = PrivateDocuments.download(f.parent, doc.object_key)
    {:ok, doc2} = Enrollment.upload(f.parent, f.enrollment.id, "other.pdf", pdf())
    assert {:ok, _} = PrivateDocuments.review(f.admin, doc2.object_key, false)
    assert Repo.get_by!(Document, object_key: doc2.object_key).content == <<>>
    assert {:error, :invalid_attachment} = parent_save(f, parent_values(doc2.object_key))
    {:ok, doc3} = Enrollment.upload(f.parent, f.enrollment.id, "expired.pdf", pdf())
    record = Repo.get_by!(Document, object_key: doc3.object_key)

    Repo.update!(
      Ecto.Changeset.change(record, expires_at: DateTime.add(DateTime.utc_now(:second), -1))
    )

    assert {:error, :not_found} = PrivateDocuments.download(f.parent, doc3.object_key)
    assert {:ok, {1, nil}} = PrivateDocuments.purge_expired(f.admin.organization_id)
    assert Repo.get!(Document, record.id).content == <<>>
  end

  test "a ready document cannot be assigned to a different ticket or field" do
    f = enrollment_fixture()
    {:ok, another} = Enrollment.create(f.admin, f.version.workflow_id, Ecto.UUID.generate())

    {:ok, doc} =
      PrivateDocuments.upload(
        f.admin,
        another.ticket_id,
        "application",
        "document",
        "other.pdf",
        pdf()
      )

    {:ok, _} = PrivateDocuments.review(f.admin, doc.object_key, true)
    assert {:error, :invalid_attachment} = parent_save(f, parent_values(doc.object_key))

    assert {:error, :not_found} =
             PrivateDocuments.upload(
               f.parent,
               f.enrollment.ticket_id,
               "placement",
               "assessment",
               "x.pdf",
               pdf()
             )
  end
end
