defmodule Emothe.AccountsTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Accounts
  alias Emothe.Accounts.{User, UserToken}
  alias Emothe.Repo

  describe "invite_user/3" do
    test "given a new email then an invited user and a token are created" do
      assert {:ok, %User{} = user, token} =
               Accounts.invite_user("nuevo@uv.es", :researcher, nil)

      assert user.email == "nuevo@uv.es"
      assert user.role == :researcher
      assert is_nil(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_binary(token)
      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")
    end

    test "given an email invited twice then the earlier token stops working" do
      {:ok, user, first} = Accounts.invite_user("dos@uv.es", :researcher, nil)
      {:ok, ^user, second} = Accounts.invite_user("dos@uv.es", :researcher, nil)

      refute first == second
      assert is_nil(Accounts.get_user_by_invite_token(first))
      assert %User{} = Accounts.get_user_by_invite_token(second)
    end

    test "given an already active user then inviting is refused" do
      user = user_fixture()

      assert {:error, :already_active} =
               Accounts.invite_user(user.email, :researcher, nil)
    end
  end

  describe "accept_invite/2" do
    test "given a valid token and password then the account becomes active" do
      {user, _token} = invited_user_fixture()

      assert {:ok, accepted} =
               Accounts.accept_invite(user, %{"password" => valid_user_password()})

      assert Accounts.active?(accepted)
      assert is_binary(accepted.hashed_password)
      assert Repo.all(from t in UserToken, where: t.context == "invite") == []
    end

    test "given a short password then acceptance fails and the account stays invited" do
      {user, _token} = invited_user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Accounts.accept_invite(user, %{"password" => "short"})

      refute Accounts.active?(Repo.reload!(user))
    end
  end

  describe "get_user_by_invite_token/1" do
    test "given a garbage token then nil" do
      assert is_nil(Accounts.get_user_by_invite_token("not-a-token"))
    end

    test "given a used token then nil" do
      {user, token} = invited_user_fixture()
      {:ok, _} = Accounts.accept_invite(user, %{"password" => valid_user_password()})

      assert is_nil(Accounts.get_user_by_invite_token(token))
    end

    test "given a token older than 7 days then nil" do
      {user, token} = invited_user_fixture()

      from(t in UserToken, where: t.user_id == ^user.id and t.context == "invite")
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -8, :day)])

      assert is_nil(Accounts.get_user_by_invite_token(token))
    end
  end

  describe "deactivate_user/1" do
    test "given an active user with a session then the session token is destroyed" do
      user = user_fixture()
      _token = Accounts.generate_user_session_token(user)

      assert {:ok, deactivated} = Accounts.deactivate_user(user)
      refute Accounts.active?(deactivated)
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end
  end

  describe "reset_user_password/2" do
    # Regression: an invited account that used "forgot password" instead of its
    # invite link got a valid password and confirmed_at: nil. It could
    # authenticate, then every gate refused it and destroyed the session —
    # a lockout with no way out through the UI.
    test "given an invited user then resetting the password activates the account" do
      {user, _token} = invited_user_fixture()

      assert {:ok, reset} =
               Accounts.reset_user_password(user, %{password: valid_user_password()})

      assert Accounts.active?(reset)
    end

    test "given a confirmed user then the original confirmation time is kept" do
      user = user_fixture(confirmed_at: ~U[2020-01-01 00:00:00Z])

      assert {:ok, reset} =
               Accounts.reset_user_password(user, %{password: valid_user_password()})

      assert reset.confirmed_at == ~U[2020-01-01 00:00:00Z]
    end

    test "given a deactivated user then resetting the password does not let them back in" do
      user = user_fixture()
      {:ok, user} = Accounts.deactivate_user(user)

      assert {:ok, reset} =
               Accounts.reset_user_password(user, %{password: valid_user_password()})

      refute Accounts.active?(reset)
    end
  end

  describe "sessions" do
    test "given a login with device info then it is stored and listable" do
      user = user_fixture()

      Accounts.generate_user_session_token(user, %{
        ip_address: "10.0.0.7",
        user_agent: "Firefox/141"
      })

      assert [session] = Accounts.list_user_sessions(user)
      assert session.ip_address == "10.0.0.7"
      assert session.user_agent == "Firefox/141"
    end

    test "given several sessions then deleting one leaves the others" do
      user = user_fixture()
      Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)

      [first | _] = Accounts.list_user_sessions(user)
      assert :ok = Accounts.delete_user_session(user, first.id)

      assert length(Accounts.list_user_sessions(user)) == 1
    end

    test "given several sessions then delete_other_user_sessions keeps only the current one" do
      user = user_fixture()
      current = Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_other_user_sessions(user, current)

      assert [remaining] = Accounts.list_user_sessions(user)
      assert remaining.token == current
    end

    test "given force_logout then every session is gone" do
      user = user_fixture()
      Accounts.generate_user_session_token(user)
      Accounts.generate_user_session_token(user)

      assert :ok = Accounts.force_logout(user)
      assert Accounts.list_user_sessions(user) == []
    end

    test "given another user's token id then deleting it is refused" do
      mine = user_fixture()
      theirs = user_fixture()
      Accounts.generate_user_session_token(theirs)
      [their_session] = Accounts.list_user_sessions(theirs)

      assert :ok = Accounts.delete_user_session(mine, their_session.id)
      assert length(Accounts.list_user_sessions(theirs)) == 1
    end
  end
end
