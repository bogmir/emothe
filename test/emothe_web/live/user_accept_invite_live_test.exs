defmodule EmotheWeb.UserAcceptInviteLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.Accounts

  test "given a valid token then setting a password logs the user in", %{conn: conn} do
    {user, token} = invited_user_fixture()

    {:ok, lv, _html} = live(conn, ~p"/users/accept-invite/#{token}")

    # The email comes from a hidden input in the real form; LiveViewTest only
    # posts values the test supplies, so it has to be named here too.
    form =
      form(lv, "#accept_invite_form",
        user: %{"email" => user.email, "password" => valid_user_password()}
      )

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/"
    assert Accounts.active?(Emothe.Repo.reload!(user))
  end

  test "given an invalid token then an explanation and no form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/accept-invite/nonsense")

    # Asserted through gettext: the page renders in the session locale, which
    # is Spanish by default.
    assert html =~
             Gettext.gettext(EmotheWeb.Gettext, "This invitation is no longer valid")

    refute html =~ "accept_invite_form"
  end
end
