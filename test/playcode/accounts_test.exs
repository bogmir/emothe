defmodule Playcode.AccountsTest do
  @moduledoc """
  The account rules the web journeys lean on but cannot easily reach: expired and
  superseded tokens, and how a password reset treats each account state. The
  journeys themselves (invite, accept, settings, user management) are asserted
  in test/playcode_web/.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Accounts

  describe "invitations" do
    test "an invited account is not active until it accepts, and the link then stops working" do
      assert {:ok, user, token} = Accounts.invite_user("nuevo@uv.es", :researcher, nil)

      refute Accounts.active?(user)
      assert Accounts.get_user_by_invite_token(token).id == user.id

      assert {:ok, accepted} =
               Accounts.accept_invite(user, %{"password" => valid_user_password()})

      assert Accounts.active?(accepted)
      assert is_nil(Accounts.get_user_by_invite_token(token))
    end

    test "inviting the same address again supersedes the earlier link" do
      {:ok, user, first} = Accounts.invite_user("dos@uv.es", :researcher, nil)
      {:ok, ^user, second} = Accounts.invite_user("dos@uv.es", :researcher, nil)

      assert is_nil(Accounts.get_user_by_invite_token(first))
      assert Accounts.get_user_by_invite_token(second).id == user.id
    end

    test "an active account cannot be invited" do
      assert {:error, :already_active} =
               Accounts.invite_user(user_fixture().email, :researcher, nil)
    end

    test "a short password leaves the account invited" do
      {user, _token} = invited_user_fixture()

      assert {:error, %Ecto.Changeset{}} = Accounts.accept_invite(user, %{"password" => "short"})
      refute Accounts.active?(Accounts.get_user!(user.id))
    end

    test "a link older than 7 days no longer works" do
      {user, token} = invited_user_fixture()

      # Time travel: no public API ages a token.
      import Ecto.Query

      from(t in Playcode.Accounts.UserToken, where: t.user_id == ^user.id)
      |> Playcode.Repo.update_all(
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -8, :day)]
      )

      assert is_nil(Accounts.get_user_by_invite_token(token))
    end
  end

  describe "password reset" do
    # Regression: an invited account that used "forgot password" instead of its
    # invite link got a valid password and confirmed_at: nil. It could
    # authenticate, then every gate refused it and destroyed the session —
    # a lockout with no way out through the UI.
    test "activates an account that was only invited" do
      {user, _token} = invited_user_fixture()

      assert {:ok, reset} = Accounts.reset_user_password(user, %{password: valid_user_password()})
      assert Accounts.active?(reset)
    end

    test "keeps the original confirmation time of a confirmed account" do
      user = user_fixture()

      # Time travel: confirmed long ago, so a reset that re-stamped it would show.
      import Ecto.Query
      confirmed = ~U[2020-01-01 00:00:00Z]

      from(u in Playcode.Accounts.User, where: u.id == ^user.id)
      |> Playcode.Repo.update_all(set: [confirmed_at: confirmed])

      user = Accounts.get_user!(user.id)

      assert {:ok, reset} =
               Accounts.reset_user_password(user, %{password: "a different password"})

      assert reset.confirmed_at == confirmed
    end

    test "does not let a deactivated account back in" do
      {:ok, user} = Accounts.deactivate_user(user_fixture())

      assert {:ok, reset} = Accounts.reset_user_password(user, %{password: valid_user_password()})
      refute Accounts.active?(reset)
    end
  end

  describe "sessions" do
    test "record the device they were opened from" do
      user = user_fixture()

      Accounts.generate_user_session_token(user, %{
        ip_address: "10.0.0.7",
        user_agent: "Firefox/141"
      })

      assert [%{ip_address: "10.0.0.7", user_agent: "Firefox/141"}] =
               Accounts.list_user_sessions(user)
    end

    test "can be ended one at a time, or all at once" do
      user = user_fixture()
      for _ <- 1..3, do: Accounts.generate_user_session_token(user)

      [first | _] = Accounts.list_user_sessions(user)
      assert :ok = Accounts.delete_user_session(user, first.id)
      assert length(Accounts.list_user_sessions(user)) == 2

      assert :ok = Accounts.force_logout(user)
      assert Accounts.list_user_sessions(user) == []
    end
  end
end
