defmodule EmotheWeb.ExportController do
  use EmotheWeb, :controller

  alias Emothe.Catalogue
  alias Emothe.Export

  def tei(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    xml = Export.TeiXml.generate(play)

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.xml"))
    |> send_resp(200, xml)
  end

  def html(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    html = Export.Html.generate(play)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.html"))
    |> send_resp(200, html)
  end

  def pdf(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)

    case Export.Pdf.generate(play) do
      {:ok, pdf_binary} ->
        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.pdf"))
        |> send_resp(200, pdf_binary)

      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "PDF generation failed")
    end
  end
end
