defmodule EmotheWeb.Admin.PlayListLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Accounts
  alias Emothe.Accounts.User
  alias Emothe.Repo
  alias Emothe.TestFixtures

  defp log_in_admin(conn) do
    email = "admin-#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      Accounts.register_user(%{
        "email" => email,
        "password" => "verysecurepass123"
      })

    {:ok, user} = user |> User.role_changeset(%{role: :admin}) |> Repo.update()
    token = Accounts.generate_user_session_token(user)

    conn
    |> init_test_session(%{})
    |> put_session(:user_token, token)
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
      |> element("form")
      |> render_change(%{"search" => "Alpha"})

      html = render(view)
      assert html =~ alpha.title
      refute html =~ beta.title
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
  end
end
