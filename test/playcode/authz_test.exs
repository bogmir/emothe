defmodule Playcode.AuthzTest do
  # Who may open which page is asserted route by route in
  # test/playcode_web/authorization_test.exs. What is left here is the one rule
  # no route can show: an action the policy has never heard of is refused.
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Authz

  test "an unknown action is denied even for an admin" do
    refute Authz.can?(admin_fixture(), :launch_missiles)
  end
end
