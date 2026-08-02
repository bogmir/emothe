defmodule EmotheWeb.UserSettingsLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  alias Emothe.Accounts

  describe "active sessions panel" do
    test "given two sessions then both are listed and only one is this device", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      Accounts.generate_user_session_token(user, %{user_agent: "Firefox/141"})

      {:ok, lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Firefox/141"
      assert length(Accounts.list_user_sessions(user)) == 2

      lv |> element("button[phx-click='revoke_other_sessions']") |> render_click()

      assert [only] = Accounts.list_user_sessions(user)
      assert only.token == get_session(conn, :user_token)
    end

    test "given another user's session id then revoking it does nothing", %{conn: conn} do
      theirs = user_fixture()
      Accounts.generate_user_session_token(theirs)
      [their_session] = Accounts.list_user_sessions(theirs)

      {:ok, lv, _html} = live(log_in_user(conn, user_fixture()), ~p"/users/settings")

      render_click(lv, "revoke_session", %{"id" => their_session.id})

      assert length(Accounts.list_user_sessions(theirs)) == 1
    end
  end
end
