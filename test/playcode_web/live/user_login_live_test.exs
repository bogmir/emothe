defmodule PlaycodeWeb.UserLoginLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Accounts

  # Login is rate limited per IP across the whole suite; each test gets its own.
  setup %{conn: conn} do
    %{conn: %{conn | remote_ip: {10, 9, rem(System.unique_integer([:positive]), 250), 1}}}
  end

  defp log_in(conn, email, password) do
    post(conn, ~p"/users/log-in", user: %{"email" => email, "password" => password})
  end

  defp flash(conn, key), do: Phoenix.Flash.get(conn.assigns.flash, key)

  test "the log-in page offers the form and the way back from a lost password", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, "#login_form input[name='user[email]']")
    assert has_element?(lv, "#login_form input[name='user[password]']")
    assert has_element?(lv, "a[href='/users/reset-password']")
  end

  test "a researcher logs in and lands on the admin play list", %{conn: conn} do
    user = user_fixture(role: :researcher)

    conn = log_in(conn, user.email, valid_user_password())

    assert redirected_to(conn) == ~p"/admin/plays"
    assert flash(conn, :info) == t("Welcome back!")
    assert html_response(get(recycle(conn), ~p"/admin/plays"), 200)
  end

  test "a wrong password gets the same answer as an unknown address", %{conn: conn} do
    user = user_fixture()

    for {email, password} <- [{user.email, "wrong password!"}, {"nobody@uv.es", "whatever123"}] do
      conn = log_in(conn, email, password)

      assert redirected_to(conn) == ~p"/users/log-in"
      assert flash(conn, :error) == t("Invalid email or password")
      refute get_session(conn, :user_token)
    end
  end

  test "a deactivated account can authenticate but gets no further", %{conn: conn} do
    {:ok, user} = Accounts.deactivate_user(user_fixture())

    conn = log_in(conn, user.email, valid_user_password()) |> recycle() |> get(~p"/admin/plays")

    assert redirected_to(conn) == ~p"/users/log-in"

    assert flash(conn, :error) ==
             t("Your account is not active. Please contact an administrator.")
  end

  test "guessing one account's password is stopped after ten tries", %{conn: conn} do
    user = user_fixture()

    for _ <- 1..10, do: log_in(conn, user.email, "wrong password!")
    conn = log_in(conn, user.email, valid_user_password())

    assert flash(conn, :error) ==
             t("Too many login attempts. Please wait a few minutes and try again.")

    refute get_session(conn, :user_token)
  end

  test "logging out ends the session", %{conn: conn} do
    user = user_fixture()
    conn = log_in(conn, user.email, valid_user_password())
    token = get_session(conn, :user_token)

    conn = conn |> recycle() |> delete(~p"/users/log-out")

    assert redirected_to(conn) == ~p"/"
    assert flash(conn, :info) == t("Logged out successfully.")
    refute Accounts.get_user_by_session_token(token)
  end
end
