defmodule Playcode.Accounts.AdminBootstrapTest do
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Accounts
  alias Playcode.Accounts.AdminBootstrap

  test "given an unknown email then an invited admin is created" do
    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])

    user = Accounts.get_user_by_email("jefa@uv.es")
    assert user.role == :admin
    refute Accounts.active?(user)
  end

  test "given a researcher in the list then they are promoted" do
    user = user_fixture(email: "jefa@uv.es", role: :researcher)

    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    assert Playcode.Repo.reload!(user).role == :admin
  end

  test "given a deactivated admin in the list then they are reactivated" do
    user = user_fixture(email: "jefa@uv.es", role: :admin)
    {:ok, _} = Accounts.deactivate_user(user)

    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    assert Accounts.active?(Playcode.Repo.reload!(user))
  end

  test "given two runs then the second changes nothing" do
    :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    first = Accounts.get_user_by_email("jefa@uv.es")

    :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    second = Accounts.get_user_by_email("jefa@uv.es")

    assert first.id == second.id
    assert first.role == second.role
  end

  test "given an empty list then nothing happens" do
    assert :ok = AdminBootstrap.reconcile([])
    assert Playcode.Repo.aggregate(Playcode.Accounts.User, :count) == 0
  end

  test "given a configured email then it is a protected admin" do
    Application.put_env(:playcode, :admin_emails, ["Jefa@UV.es"])
    on_exit(fn -> Application.put_env(:playcode, :admin_emails, []) end)

    user = user_fixture(email: "jefa@uv.es", role: :admin)
    other = user_fixture(role: :admin)

    assert Accounts.protected_admin?(user)
    refute Accounts.protected_admin?(other)
  end
end
