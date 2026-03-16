defmodule EmotheWeb.Admin.ExportController do
  use EmotheWeb, :controller

  alias Emothe.Catalogue
  alias Emothe.Export
  alias Emothe.ActivityLog

  def compare_html(conn, %{"plays" => play_ids_str}) do
    play_ids = String.split(play_ids_str, ",", trim: true)
    plays = Enum.map(play_ids, &Catalogue.get_play_with_all!/1)
    html = Export.CompareHtml.generate(plays)
    codes = Enum.map_join(plays, "_vs_", & &1.code)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(attachment; filename="compare_#{codes}.html"))
    |> send_resp(200, html)
  end

  def tei(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    xml = Export.TeiXml.generate(play)

    log_export(conn, play, "tei")

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.xml"))
    |> send_resp(200, xml)
  end

  def html(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    html = Export.Html.generate(play)

    log_export(conn, play, "html")

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.html"))
    |> send_resp(200, html)
  end

  def pdf(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)

    case Export.Pdf.generate(play) do
      {:ok, pdf_binary} ->
        log_export(conn, play, "pdf")

        conn
        |> put_resp_content_type("application/pdf")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.pdf"))
        |> send_resp(200, pdf_binary)

      {:error, reason} ->
        conn
        |> put_flash(:error, gettext("PDF generation failed: %{reason}", reason: inspect(reason)))
        |> redirect(to: ~p"/admin/plays/#{id}")
    end
  end

  def epub(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)

    case Export.Epub.generate(play) do
      {:ok, epub_binary} ->
        log_export(conn, play, "epub")

        conn
        |> put_resp_content_type("application/epub+zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.epub"))
        |> send_resp(200, epub_binary)

      {:error, reason} ->
        conn
        |> put_flash(:error, gettext("EPUB generation failed: %{reason}", reason: inspect(reason)))
        |> redirect(to: ~p"/admin/plays/#{id}")
    end
  end

  defp log_export(conn, play, format) do
    user = conn.assigns[:current_user]

    ActivityLog.log!(%{
      user_id: user && user.id,
      play_id: play.id,
      action: "export",
      resource_type: "play",
      resource_id: play.id,
      metadata: %{format: format, title: play.title, code: play.code}
    })
  end
end
