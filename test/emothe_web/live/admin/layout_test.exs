defmodule EmotheWeb.Admin.LayoutTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Emothe.TestFixtures

  describe "admin sidebar" do
    test "given an admin then every group is rendered", %{conn: conn} do
      {:ok, _lv, html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays")

      assert html =~ ~p"/admin/plays/import"
      assert html =~ ~p"/admin/export"
      assert html =~ ~p"/admin/activity-log"
      assert html =~ ~p"/admin/users"
      assert html =~ "/admin/dashboard"
    end

    test "given a researcher then only the content group is rendered", %{conn: conn} do
      {:ok, _lv, html} =
        live(log_in_user(conn, user_fixture(role: :researcher)), ~p"/admin/plays")

      assert html =~ ~p"/admin/plays/import"
      refute html =~ ~p"/admin/users"
      refute html =~ ~p"/admin/activity-log"
      refute html =~ "/admin/dashboard"
    end

    test "given the import page then only its entry is marked active", %{conn: conn} do
      {:ok, _lv, html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays/import")

      assert html =~ ~r/href="#{~p"/admin/plays/import"}"[^>]*class="active"/
      refute html =~ ~r/href="#{~p"/admin/plays"}"[^>]*class="active"/
    end

    test "given a play page then the sidebar starts collapsed", %{conn: conn} do
      play = play_fixture()

      {:ok, _lv, html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays/#{play.id}")

      assert html =~ ~r/id="admin-sidebar"[^>]*checked/
    end

    test "given a non-play page then the sidebar starts open", %{conn: conn} do
      {:ok, _lv, html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays")

      refute html =~ ~r/id="admin-sidebar"[^>]*checked/
    end
  end
end
