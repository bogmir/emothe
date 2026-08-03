defmodule EmotheWeb.Admin.FilemakerSyncLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  describe "access" do
    test "given an admin then the upload form is rendered", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      assert has_element?(lv, "#upload-form")
    end

    test "given a researcher then the page is refused", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: :researcher))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/filemaker")
      assert flash["error"] == t("You do not have access to that page.")
    end
  end

  defp t(msgid, bindings \\ []) do
    Gettext.gettext(EmotheWeb.Gettext, msgid, bindings)
  end
end
