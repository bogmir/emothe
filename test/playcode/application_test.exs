defmodule Playcode.ApplicationTest do
  use ExUnit.Case, async: true

  # AdminBootstrap used to start right after the Repo. It calls
  # PlaycodeWeb.Endpoint.url/0, which raises until the endpoint stores its
  # persistent term — a race the Task usually wins, but losing it creates the
  # invited admins and swallows the mail carrying their only way in.
  test "given the supervision tree then AdminBootstrap starts after the endpoint" do
    ids = Enum.map(Playcode.Application.children(), &child_id/1)

    assert Enum.find_index(ids, &(&1 == Playcode.Accounts.AdminBootstrap)) >
             Enum.find_index(ids, &(&1 == PlaycodeWeb.Endpoint))
  end

  test "given the supervision tree then AdminBootstrap starts after the repo" do
    ids = Enum.map(Playcode.Application.children(), &child_id/1)

    assert Enum.find_index(ids, &(&1 == Playcode.Accounts.AdminBootstrap)) >
             Enum.find_index(ids, &(&1 == Playcode.Repo))
  end

  defp child_id({module, _opts}), do: module
  defp child_id(module), do: module
end
