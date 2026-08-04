defmodule Emothe.AuthzTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Authz

  @researcher_actions ~w(view_admin manage_plays edit_content manage_editors
                         manage_sources manage_places import_tei download_export
                         archive_play)a

  @admin_only_actions ~w(purge_play manage_users view_activity_log
                         deploy_site view_dashboard import_filemaker)a

  describe "an active researcher" do
    setup do: %{user: user_fixture(role: :researcher)}

    test "may do every content action", %{user: user} do
      for action <- @researcher_actions do
        assert Authz.can?(user, action), "expected researcher to be allowed #{action}"
      end
    end

    test "may do no admin-only action", %{user: user} do
      for action <- @admin_only_actions do
        refute Authz.can?(user, action), "expected researcher to be denied #{action}"
      end
    end
  end

  describe "an active admin" do
    setup do: %{user: admin_fixture()}

    test "may do everything", %{user: user} do
      for action <- @researcher_actions ++ @admin_only_actions do
        assert Authz.can?(user, action), "expected admin to be allowed #{action}"
      end
    end
  end

  describe "inactive accounts" do
    test "a deactivated admin may do nothing" do
      user = admin_fixture(deactivated_at: DateTime.utc_now(:second))

      for action <- Authz.actions() do
        refute Authz.can?(user, action), "expected deactivated admin to be denied #{action}"
      end
    end

    test "an unconfirmed admin may do nothing" do
      user = admin_fixture(confirmed_at: nil)

      for action <- Authz.actions() do
        refute Authz.can?(user, action)
      end
    end

    test "nil may do nothing" do
      for action <- Authz.actions() do
        refute Authz.can?(nil, action)
      end
    end
  end

  test "an unknown action is denied even for an admin" do
    refute Authz.can?(admin_fixture(), :launch_missiles)
  end
end
