defmodule Instantflow.PrivateDocumentEfficiencyTest do
  use Instantflow.DataCase, async: true
  import Instantflow.EnrollmentFixtures
  alias Instantflow.{PrivateDocuments, WorkflowRuntime}
  alias Instantflow.Diagnostics.QueryProbe
  alias Instantflow.Enrollment.Document
  @max_size 5_242_880

  setup do
    f = enrollment_fixture()
    bytes = "%PDF-1.4\n" <> String.duplicate("x", @max_size - 15) <> "\n%%EOF"
    key = Ecto.UUID.generate()

    {:ok, doc} =
      PrivateDocuments.upload(
        f.parent,
        f.enrollment.id,
        "application",
        "document",
        "maximum.pdf",
        bytes,
        key
      )

    Map.merge(f, %{bytes: bytes, doc: doc, upload_key: key})
  end

  test "maximum-size metadata stays below the ordinary-read budget; denied rows stay in SQL", f do
    {documents, report} =
      measure("document_metadata_max_size", fn ->
        PrivateDocuments.list(f.parent, f.enrollment.id)
      end)

    assert [%{object_key: key, size: @max_size, can_review: false}] = documents
    assert key == f.doc.object_key
    assert report.groups.documents.rows == 1
    assert_metadata_only(report)
    assert report.binary_bytes < 4 * 1024 * 1024

    {[], denied} =
      measure("document_metadata_denied", fn ->
        PrivateDocuments.list(f.members["it"], f.enrollment.id)
      end)

    assert_metadata_only(denied)
    assert denied.groups.documents.rows == 0
    assert [%{can_review: true}] = PrivateDocuments.list(f.admin, f.enrollment.id)
  end

  test "authorization and quarantine are checked before fetching a body", f do
    for {scenario, fun, expected} <- [
          {"document_download_quarantined",
           fn -> PrivateDocuments.download(f.parent, f.doc.object_key) end, {:error, :not_found}},
          {"document_review_denied",
           fn -> PrivateDocuments.review(f.parent, f.doc.object_key, true) end,
           {:error, :forbidden}},
          {"document_download_denied",
           fn -> PrivateDocuments.download(f.members["it"], f.doc.object_key) end,
           {:error, :not_found}}
        ] do
      {result, report} = measure(scenario, fun)
      assert result == expected
      assert_metadata_only(report)
    end
  end

  test "review and authorized download fetch one body; review replay fetches none", f do
    key = Ecto.UUID.generate()

    {{:ok, ready}, review} =
      measure("document_review_max_size", fn ->
        PrivateDocuments.review(f.admin, f.doc.object_key, true, key)
      end)

    assert ready.status == "ready"
    assert review.content_bytes == @max_size
    assert review.content_selections == 1

    {{:ok, ^ready}, replay} =
      measure("document_review_replay", fn ->
        PrivateDocuments.review(f.admin, f.doc.object_key, true, key)
      end)

    assert_metadata_only(replay)

    {{:ok, downloaded}, download} =
      measure("document_download_max_size", fn ->
        PrivateDocuments.download(f.parent, f.doc.object_key)
      end)

    assert byte_size(downloaded.content) == @max_size
    assert :crypto.hash(:sha256, downloaded.content) == :crypto.hash(:sha256, f.bytes)
    assert download.content_bytes == @max_size
    assert download.content_selections == 1

    {:ok, _} = revoke(f)

    {{:error, :not_found}, revoked} =
      measure("document_download_revoked", fn ->
        PrivateDocuments.download(f.parent, f.doc.object_key)
      end)

    assert_metadata_only(revoked)
  end

  test "upload replay and deletion do not read the stored body", f do
    {{:ok, doc}, replay} =
      measure("document_upload_replay", fn ->
        PrivateDocuments.upload(
          f.parent,
          f.enrollment.id,
          "application",
          "document",
          "maximum.pdf",
          f.bytes,
          f.upload_key
        )
      end)

    assert doc == f.doc
    assert_metadata_only(replay)

    {{:ok, :ok}, deletion} =
      measure("document_delete_max_size", fn ->
        PrivateDocuments.delete(f.parent, f.doc.object_key)
      end)

    assert_metadata_only(deletion)
    assert Repo.get_by!(Document, object_key: f.doc.object_key).content == <<>>
  end

  test "attachment validation and transition readiness never fetch content", f do
    {{:ok, _}, save} =
      measure("document_attachment_save", fn ->
        parent_save(f, parent_values(f.doc.object_key))
      end)

    assert_metadata_only(save)
    prepare_review(f)

    {{:error, :attachment_not_ready}, guarded} =
      measure("document_guard_quarantined", fn ->
        Instantflow.WorkflowFixtures.transition(f.admin, f.enrollment.id, "verify")
      end)

    assert_metadata_only(guarded)

    {:ok, _} = PrivateDocuments.review(f.admin, f.doc.object_key, true)

    {{:ok, _}, ready} =
      measure("document_guard_ready", fn ->
        Instantflow.WorkflowFixtures.transition(f.admin, f.enrollment.id, "verify")
      end)

    assert_metadata_only(ready)
  end

  test "expired files are rejected before physical retention cleanup", f do
    {:ok, _} = parent_save(f, parent_values(f.doc.object_key))
    prepare_review(f)
    {:ok, _} = PrivateDocuments.review(f.admin, f.doc.object_key, true)
    expires = DateTime.add(DateTime.utc_now(:second), -1)

    Repo.update_all(from(d in Document, where: d.object_key == ^f.doc.object_key),
      set: [expires_at: expires]
    )

    {{:error, :attachment_not_ready}, guarded} =
      measure("document_guard_expired", fn ->
        Instantflow.WorkflowFixtures.transition(f.admin, f.enrollment.id, "verify")
      end)

    assert_metadata_only(guarded)

    {{:error, :not_found}, download} =
      measure("document_download_expired", fn ->
        PrivateDocuments.download(f.parent, f.doc.object_key)
      end)

    assert_metadata_only(download)
    assert {:ok, {1, nil}} = PrivateDocuments.purge_expired(f.admin.organization_id)
    assert Repo.get_by!(Document, object_key: f.doc.object_key).content == <<>>
  end

  test "accepting a corrupt file still verifies its checksum and clears the content", f do
    Repo.update_all(from(d in Document, where: d.object_key == ^f.doc.object_key),
      set: [sha256: <<0::256>>]
    )

    {{:ok, doc}, report} =
      measure("document_review_corrupt", fn ->
        PrivateDocuments.review(f.admin, f.doc.object_key, true)
      end)

    assert doc.status == "rejected"
    assert report.content_bytes == @max_size
    assert Repo.get_by!(Document, object_key: f.doc.object_key).content == <<>>
  end

  test "explicit rejection clears content without fetching it", f do
    {{:ok, doc}, report} =
      measure("document_review_reject", fn ->
        PrivateDocuments.review(f.admin, f.doc.object_key, false)
      end)

    assert doc.status == "rejected"
    assert_metadata_only(report)
    assert Repo.get_by!(Document, object_key: f.doc.object_key).content == <<>>
  end

  test "a shared user in another organization cannot fetch a stored body", f do
    other = second_school(f)

    {{:error, :not_found}, report} =
      measure("document_download_wrong_tenant", fn ->
        PrivateDocuments.download(other.parent, f.doc.object_key)
      end)

    assert_metadata_only(report)
    assert report.groups.documents.rows == 0
  end

  defp prepare_review(f) do
    assert {:ok, _} = parent_submit(f)

    assert {:ok, _} =
             staff_save(f.admin, f.enrollment.id, "identity", %{"display_name" => "Synthetic"})

    assert {:ok, _} = WorkflowRuntime.get(f.admin, f.enrollment.id)
  end

  defp assert_metadata_only(report) do
    assert report.content_bytes == 0
    assert report.content_selections == 0
  end

  defp measure(scenario, fun) do
    {result, report} = QueryProbe.capture(fun)

    if path = System.get_env("DB_EFFICIENCY_REPORT") do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Jason.encode!(Map.put(report, :scenario, scenario)) <> "\n", [:append])
    end

    {result, report}
  end
end
