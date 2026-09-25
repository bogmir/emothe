defmodule PlaycodeWeb.ExportControllerTest do
  @moduledoc "The public downloads at /export/:id/*, open to anyone."
  use PlaycodeWeb.ConnCase, async: true

  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup do
    play =
      import_tei!(
        tei(
          title: "Obra descargable",
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso de prueba</l></sp></div1>)
        )
      )

    %{play: play}
  end

  defp attachment(conn), do: conn |> get_resp_header("content-disposition") |> List.first()

  test "the TEI download is the play's TEI, as a named attachment", %{conn: conn, play: play} do
    conn = get(conn, ~p"/export/#{play.id}/tei")

    assert xml_texts(response(conn, 200), "l") == ["Verso de prueba"]
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.xml")
  end

  test "the HTML download is a standalone page with the text", %{conn: conn, play: play} do
    conn = get(conn, ~p"/export/#{play.id}/html")

    body = response(conn, 200)
    assert body =~ "<!DOCTYPE html>"
    assert body =~ "Obra descargable"
    assert body =~ "Verso de prueba"
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.html")
  end

  test "the EPUB download is an e-book carrying the text", %{conn: conn, play: play} do
    conn = get(conn, ~p"/export/#{play.id}/epub")

    assert {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
    text = Enum.map_join(files, fn {_name, content} -> content end)
    assert text =~ "Obra descargable"
    assert text =~ "Verso de prueba"
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.epub")
  end

  test "an archived play cannot be downloaded", %{conn: conn, play: play} do
    {:ok, _} = Playcode.Catalogue.delete_play(play)

    assert_error_sent 404, fn -> get(conn, ~p"/export/#{play.id}/tei") end
  end
end
