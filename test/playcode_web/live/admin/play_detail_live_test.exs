defmodule PlaycodeWeb.Admin.PlayDetailLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp upload_docx(lv, path) do
    lv
    |> file_input("#docx-upload-form", :docx, [
      %{
        name: Path.basename(path),
        content: File.read!(path),
        type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      }
    ])
    |> render_upload(Path.basename(path))

    lv |> element("#docx-upload-form") |> render_submit()
  end

  describe "importing a premarcado Word file" do
    test "replaces the play's text, which the public page then shows with its cast list",
         %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

      assert upload_docx(lv, "test/fixtures/word_files/ejercicio.docx") =~
               t("Content imported successfully.")

      {:ok, public, html} = live(conn, ~p"/plays/#{play.code}")

      assert html =~ "Entran Febo y Ricardo."
      assert html =~ "Será remedio casarte."
      assert has_element?(public, ".cast-list", "FEBO")
      assert has_element?(public, ".cast-list", "RICARDO")
    end

    test "keeps text it cannot place, for review in the content editor",
         %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

      upload_docx(
        lv,
        docx(["PROLOGUE", "{e}Escena 1", "{p}FEBO  {v}Hello.", "THE SCENE: SMITHFIELD"])
      )

      {:ok, editor, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      editor |> element("nav[aria-label='Editor tabs'] button", "structure") |> render_click()

      assert editor |> element("button", "Escena 1") |> render_click() =~
               "THE SCENE: SMITHFIELD"
    end
  end

  test "marking a play complete publishes it in the catalogue, and back to draft withdraws it",
       %{conn: conn, play: play} do
    {:ok, catalogue, _html} = live(conn, ~p"/plays")
    refute render(catalogue) =~ play.title

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    assert lv |> element("button", t("Draft")) |> render_click() =~ t("Marked as complete.")

    {:ok, _catalogue, html} = live(conn, ~p"/plays")
    assert html =~ play.title

    assert lv |> element("button", t("Complete")) |> render_click() =~ t("Marked as draft.")
    {:ok, _catalogue, html} = live(conn, ~p"/plays")
    refute html =~ play.title
  end
end
