defmodule EmotheWeb.Admin.ExportControllerTest do
  use EmotheWeb.ConnCase, async: true

  alias Emothe.TestFixtures

  defp log_in_admin(conn) do
    log_in_user(conn, Emothe.TestFixtures.admin_fixture())
  end

  describe "Export endpoints behaviors" do
    test "given a play when requesting TEI export then XML is returned as attachment", %{
      conn: conn
    } do
      conn = log_in_admin(conn)
      play = TestFixtures.play_with_metadata_fixture()

      conn = get(conn, ~p"/admin/plays/#{play.id}/export/tei")

      assert response(conn, 200) =~ "<TEI"
      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/xml"

      assert get_resp_header(conn, "content-disposition") |> List.first() =~
               "attachment; filename=\"#{play.code}.xml\""
    end

    test "given a play when requesting HTML export then standalone HTML is returned", %{
      conn: conn
    } do
      conn = log_in_admin(conn)
      play = TestFixtures.play_with_metadata_fixture()

      conn = get(conn, ~p"/admin/plays/#{play.id}/export/html")

      body = response(conn, 200)
      assert body =~ "<!DOCTYPE html>"
      assert body =~ play.title
      assert get_resp_header(conn, "content-type") |> List.first() =~ "text/html"

      assert get_resp_header(conn, "content-disposition") |> List.first() =~
               "attachment; filename=\"#{play.code}.html\""
    end
  end
end
