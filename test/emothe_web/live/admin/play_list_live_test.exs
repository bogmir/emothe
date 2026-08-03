defmodule EmotheWeb.Admin.PlayListLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.TestFixtures

  defp log_in_admin(conn) do
    log_in_user(conn, Emothe.TestFixtures.admin_fixture())
  end

  describe "Play management list behaviors" do
    test "given plays when searching then only matching plays are shown", %{conn: conn} do
      conn = log_in_admin(conn)

      alpha =
        TestFixtures.play_fixture(%{"title" => "Alpha Tragedy", "author_name" => "Author A"})

      beta = TestFixtures.play_fixture(%{"title" => "Beta Comedy", "author_name" => "Author B"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert render(view) =~ alpha.title
      assert render(view) =~ beta.title

      view
      |> element("form[phx-change=search]")
      |> render_change(%{"search" => "Alpha"})

      html = render(view)
      assert html =~ alpha.title
      refute html =~ beta.title
    end

    # Regression: the archived list offered Edit, the title link and the public
    # page, all of which load through readers that hide archived plays — every
    # one of them raised Ecto.NoResultsError.
    test "given an archived play then no link points at a page that cannot load it", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture(%{"title" => "Archived Play"})
      {:ok, _} = Emothe.Catalogue.delete_play(play)

      {:ok, view, html} = live(conn, ~p"/admin/plays?archived=1")

      assert html =~ play.title
      refute html =~ ~p"/admin/plays/#{play.id}/edit"
      refute html =~ ~p"/admin/plays/#{play.id}"
      refute html =~ ~p"/plays/#{play.code}"

      assert has_element?(view, "button[phx-click='restore'][phx-value-id='#{play.id}']")
    end

    test "given a play when deleting from list then it disappears", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture(%{"title" => "Delete Me"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert render(view) =~ "Delete Me"

      view
      |> element("button[phx-value-id='#{play.id}']")
      |> render_click()

      refute render(view) =~ "Delete Me"
    end

    test "an archived play is listed under the archived filter and can be restored", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture(%{"title" => "Archive Me"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      view |> element("button[phx-click=delete][phx-value-id='#{play.id}']") |> render_click()
      refute render(view) =~ "Archive Me"

      {:ok, archived_view, html} = live(conn, ~p"/admin/plays?archived=1")
      assert html =~ "Archive Me"

      archived_view
      |> element("button[phx-click=restore][phx-value-id='#{play.id}']")
      |> render_click()

      refute render(archived_view) =~ "Archive Me"

      {:ok, _view, html} = live(conn, ~p"/admin/plays")
      assert html =~ "Archive Me"
    end
  end
end
