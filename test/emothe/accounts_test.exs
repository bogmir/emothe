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
end
