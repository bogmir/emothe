defmodule EmotheWeb.UserResetPasswordLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.Accounts

  defp reset_token(user) do
    Accounts.deliver_user_reset_password_instructions(user, fn token ->
      send(self(), {:reset_token, token})
      "http://localhost/users/reset-password/#{token}"
    end)

    assert_receive {:reset_token, token}
    token
  end

  test "given a valid token then the password is reset", %{conn: conn} do
    user = user_fixture()

    {:ok, lv, _html} = live(conn, ~p"/users/reset-password/#{reset_token(user)}")

    result =
      lv
      |> form("#reset_password_form",
        user: %{"password" => "newverysecure123", "password_confirmation" => "newverysecure123"}
      )
      |> render_submit()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = result
    assert Accounts.get_user_by_email_and_password(user.email, "newverysecure123")
  end

  # Regression: the route sat behind redirect_if_user_is_authenticated, so a
  # user who still held a session was bounced to the catalogue with no
  # explanation. An unconfirmed account can log in but is refused everywhere
  # else, so the reset link was the only way out — and holding a session was
  # exactly what swallowed it.
  test "given an existing session then the reset page still opens", %{conn: conn} do
    user = user_fixture(confirmed_at: nil)

    conn = log_in_user(conn, user)
    {:ok, lv, html} = live(conn, ~p"/users/reset-password/#{reset_token(user)}")

    assert html =~ "reset_password_form"

    lv
    |> form("#reset_password_form",
      user: %{"password" => "newverysecure123", "password_confirmation" => "newverysecure123"}
    )
    |> render_submit()

    assert Accounts.active?(Emothe.Repo.reload!(user))
  end
end
