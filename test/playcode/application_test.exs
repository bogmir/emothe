defmodule Playcode.ApplicationTest do
  use ExUnit.Case, async: true

  # AdminBootstrap used to start right after the Repo. It calls
  # PlaycodeWeb.Endpoint.url/0, which raises until the endpoint stores its
  # persistent term — a race the Task usually wins, but losing it creates the
  # invited admins and swallows the mail carrying their only way in.
  test "AdminBootstrap starts after both the repo and the endpoint" do
    ids = Enum.map(Playcode.Application.children(), &child_id/1)
    position = &Enum.find_index(ids, fn id -> id == &1 end)

    assert position.(Playcode.Accounts.AdminBootstrap) > position.(PlaycodeWeb.Endpoint)
    assert position.(Playcode.Accounts.AdminBootstrap) > position.(Playcode.Repo)
  end

  defp child_id({module, _opts}), do: module
  defp child_id(module), do: module
end
