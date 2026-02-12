defmodule EmotheWeb.Admin.PlayFormLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.Accounts
  alias Emothe.Accounts.User
  alias Emothe.Catalogue
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

  describe "Play form behaviors" do
    test "given valid data when creating a play then user is redirected to detail", %{conn: conn} do
      conn = log_in_admin(conn)
      code = TestFixtures.unique_code()

      {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

      params = %{
        "play" => %{
          "title" => "BDD Play",
          "code" => code,
          "author_name" => "Behavior Author",
          "language" => "es",
          "is_verse" => "true"
        }
      }

      view
      |> element("form")
      |> render_submit(params)

      created = Catalogue.get_play_by_code!(code)
      assert_redirect(view, ~p"/admin/plays/#{created.id}")
    end

    test "given invalid data when creating a play then errors are shown and no redirect", %{
      conn: conn
    } do
      conn = log_in_admin(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

      view
      |> element("form")
      |> render_submit(%{"play" => %{"title" => "", "code" => ""}})

      html = render(view)
      assert html =~ "can&#39;t be blank"
      assert html =~ "New Play"
    end

    test "given existing play when editing then updated data is persisted", %{conn: conn} do
      conn = log_in_admin(conn)
      play = TestFixtures.play_fixture(%{"title" => "Original Title"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

      view
      |> element("form")
      |> render_submit(%{"play" => %{"title" => "Updated Title", "code" => play.code}})

      assert_redirect(view, ~p"/admin/plays/#{play.id}")
      assert Catalogue.get_play!(play.id).title == "Updated Title"
    end
  end
end
