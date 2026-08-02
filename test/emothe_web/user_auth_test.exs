defmodule EmotheWeb.UserAuthTest do
  use EmotheWeb.ConnCase, async: true

  import Emothe.TestFixtures

  describe "require_authenticated_user/2" do
    test "given an unconfirmed user then access is refused", %{conn: conn} do
      user = user_fixture(confirmed_at: nil)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/settings")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "given a deactivated user then access is refused", %{conn: conn} do
      user = user_fixture(deactivated_at: DateTime.utc_now(:second))

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/settings")

      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "given an active user then access is allowed", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture())
        |> get(~p"/users/settings")

      assert html_response(conn, 200)
    end
  end

  describe "require_admin_user/2" do
    test "given an unconfirmed admin then the admin area is refused", %{conn: conn} do
      admin = admin_fixture(confirmed_at: nil)

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/plays")

      refute redirected_to(conn) == ~p"/admin/plays"
    end

    test "given a deactivated admin then the admin area is refused", %{conn: conn} do
      admin = admin_fixture(deactivated_at: DateTime.utc_now(:second))

      conn =
        conn
        |> log_in_user(admin)
        |> get(~p"/admin/plays")

      refute redirected_to(conn) == ~p"/admin/plays"
    end
  end

  describe "public registration" do
    # The plan expected Phoenix.Router.NoRouteError, but the endpoint's
    # render_errors turns an unmatched route into a plain 404 in test.
    test "given the registration path then it no longer exists", %{conn: conn} do
      assert get(conn, "/users/register").status == 404
    end
  end
end
