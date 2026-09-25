defmodule PlaycodeWeb.Admin.ExportControllerTest do
  use PlaycodeWeb.ConnCase, async: true

  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    %{
      conn: log_in_user(conn, user_fixture(role: :researcher)),
      play: play_with_metadata_fixture()
    }
  end

  defp attachment(conn), do: conn |> get_resp_header("content-disposition") |> List.first()

  test "TEI and HTML downloads are named after the play, and each is logged",
       %{conn: conn, play: play} do
    tei = get(conn, ~p"/admin/plays/#{play.id}/export/tei")
    assert xml_texts(response(tei, 200), "title", within: "titleStmt") |> Enum.member?(play.title)
    assert get_resp_header(tei, "content-type") |> List.first() =~ "application/xml"
    assert attachment(tei) == ~s(attachment; filename="#{play.code}.xml")

    html = get(conn, ~p"/admin/plays/#{play.id}/export/html")
    assert response(html, 200) =~ play.title
    assert attachment(html) == ~s(attachment; filename="#{play.code}.html")

    formats =
      [action: "export", play_id: play.id]
      |> Playcode.ActivityLog.list_entries()
      |> Enum.map(& &1.metadata["format"])
      |> Enum.sort()

    assert formats == ["html", "tei"]
  end

  test "the EPUB download is an e-book with the play's title", %{conn: conn, play: play} do
    conn = get(conn, ~p"/admin/plays/#{play.id}/export/epub")

    assert {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
    assert Enum.any?(files, fn {_name, content} -> content =~ play.title end)
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.epub")
  end

  test "two plays compared side by side download as one page", %{conn: conn, play: play} do
    other = play_fixture(%{"title" => "La otra versión"})

    conn = get(conn, ~p"/admin/plays/compare/export/html?#{[plays: "#{play.id},#{other.id}"]}")

    body = response(conn, 200)
    assert body =~ play.title
    assert body =~ "La otra versión"

    assert attachment(conn) ==
             ~s(attachment; filename="compare_#{play.code}_vs_#{other.code}.html")
  end
end
