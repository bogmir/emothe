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
    user_fixture(email: "jefa@uv.es", role: :researcher)

    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    assert Accounts.get_user_by_email("jefa@uv.es").role == :admin
  end

  test "given a deactivated admin in the list then they are reactivated" do
    {:ok, _} = Accounts.deactivate_user(user_fixture(email: "jefa@uv.es", role: :admin))

    assert :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    assert Accounts.active?(Accounts.get_user_by_email("jefa@uv.es"))
  end

  test "given two runs then the second changes nothing" do
    :ok = AdminBootstrap.reconcile(["jefa@uv.es"])
    first = Accounts.get_user_by_email("jefa@uv.es")

    :ok = AdminBootstrap.reconcile(["jefa@uv.es"])

    assert Map.take(Accounts.get_user_by_email("jefa@uv.es"), [:id, :role]) ==
             Map.take(first, [:id, :role])
  end
end
