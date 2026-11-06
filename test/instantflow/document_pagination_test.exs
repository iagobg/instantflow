defmodule Instantflow.DocumentPaginationTest do
  use Instantflow.DataCase, async: true
  alias Instantflow.{BuilderFixtures, DocumentHistoryFixtures, Participants, PrivateDocuments}
  alias Instantflow.Diagnostics.QueryProbe

  test "first-page work remains bounded with 1, 1001 and 10001 retained documents" do
    f = DocumentHistoryFixtures.fixture(1)

    for {additional, total, fetched} <- [{0, 1, 1}, {1000, 1001, 51}, {9000, 10001, 51}] do
      DocumentHistoryFixtures.insert(f.template, additional)

      {page, report} =
        QueryProbe.capture(fn -> PrivateDocuments.list_page(f.visitor, f.ticket_id) end)

      assert length(page.rows) == min(total, 50)
      assert report.groups.documents.rows == fetched
      assert report.content_selections == 0
      assert report.binary_bytes < 4 * 1024 * 1024

      if path = System.get_env("DB_EFFICIENCY_REPORT") do
        File.write!(
          path,
          Jason.encode!(Map.put(report, :scenario, "document_page_#{total}")) <> "\n",
          [:append]
        )
      end
    end
  end

  test "visibility precedes limit and exclusive cursors survive newer appends" do
    f = DocumentHistoryFixtures.fixture(103)
    # Newer, valid metadata in the staff-only section must not fill the visitor's page.
    DocumentHistoryFixtures.insert(%{f.template | section_key: "request"}, 70)
    first = PrivateDocuments.list_page(f.visitor, f.ticket_id)
    assert Enum.map(first.rows, & &1.id) == Enum.take(f.ids, 50)
    assert first.next_cursor == Enum.at(f.ids, 49)
    [new_id] = DocumentHistoryFixtures.insert(f.template, 1)
    second = PrivateDocuments.list_page(f.visitor, f.ticket_id, first.next_cursor)
    third = PrivateDocuments.list_page(f.visitor, f.ticket_id, second.next_cursor)
    assert Enum.map(first.rows ++ second.rows ++ third.rows, & &1.id) == f.ids
    assert length(third.rows) == 3
    assert third.next_cursor == nil
    assert hd(PrivateDocuments.list(f.visitor, f.ticket_id)).id == new_id
    assert length(PrivateDocuments.list(f.visitor, f.ticket_id)) == 50
  end

  test "a retained cursor does not authorize a revoked visitor; malformed cursors fail closed" do
    f = DocumentHistoryFixtures.fixture(51)
    cursor = PrivateDocuments.list_page(f.visitor, f.ticket_id).next_cursor

    {:ok, _} =
      Participants.command(
        f.admin,
        BuilderFixtures.participant_command(f.ticket_id, f.visitor.id, "revoke", 2)
      )

    assert PrivateDocuments.list_page(f.visitor, f.ticket_id, cursor) == %{
             rows: [],
             next_cursor: nil
           }

    for cursor <- ["1", -1, 0, 9_223_372_036_854_775_807, %{}] do
      assert PrivateDocuments.list_page(f.admin, f.ticket_id, cursor) == %{
               rows: [],
               next_cursor: nil
             }
    end
  end
end
