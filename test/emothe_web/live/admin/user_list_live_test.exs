defmodule EmotheWeb.Admin.UserListLiveTest do
  use EmotheWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.Accounts

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  test "given the invite form then a user is invited", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    lv
    |> form("#invite_form", invite: %{"email" => "nueva@uv.es", "role" => "researcher"})
    |> render_submit()

    user = Accounts.get_user_by_email("nueva@uv.es")
    assert user.role == :researcher
    refute Accounts.active?(user)
    assert render(lv) =~ "nueva@uv.es"
  end

  test "given an active user then deactivating them ends their sessions", %{conn: conn} do
    victim = user_fixture()
    Accounts.generate_user_session_token(victim)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    lv |> element("button[phx-value-id='#{victim.id}'][phx-click='deactivate']") |> render_click()

    refute Accounts.active?(Emothe.Repo.reload!(victim))
    assert Accounts.list_user_sessions(victim) == []
  end

  test "given a protected admin then demotion is refused", %{conn: conn} do
    Application.put_env(:emothe, :admin_emails, ["jefa@uv.es"])
    on_exit(fn -> Application.put_env(:emothe, :admin_emails, []) end)

    protected = user_fixture(email: "jefa@uv.es", role: :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    render_change(lv, "set_role", %{"id" => protected.id, "role" => "researcher"})

    assert Emothe.Repo.reload!(protected).role == :admin
  end

  test "given a protected admin then deactivation is refused", %{conn: conn} do
    Application.put_env(:emothe, :admin_emails, ["jefa@uv.es"])
    on_exit(fn -> Application.put_env(:emothe, :admin_emails, []) end)

    protected = user_fixture(email: "jefa@uv.es", role: :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    render_click(lv, "deactivate", %{"id" => protected.id})

    assert Accounts.active?(Emothe.Repo.reload!(protected))
  end
end
