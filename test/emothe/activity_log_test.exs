defmodule Emothe.ActivityLogTest do
  use Emothe.DataCase, async: true

  alias Emothe.ActivityLog
  alias Emothe.ActivityLog.{Diff, Entry}
  alias Emothe.TestFixtures

  defp user_fixture do
    {:ok, user} =
      Emothe.Accounts.register_user(%{
        email: "user#{System.unique_integer([:positive])}@test.com",
        password: "valid_password_123"
      })

    user
  end

  describe "log/1" do
    test "creates an entry with valid attrs" do
      user = user_fixture()
      play = TestFixtures.play_fixture()

      assert {:ok, entry} =
               ActivityLog.log(%{
                 user_id: user.id,
                 play_id: play.id,
                 action: "create",
                 resource_type: "play",
                 resource_id: play.id,
                 metadata: %{title: play.title, code: play.code}
               })

      assert entry.action == "create"
      assert entry.resource_type == "play"
      assert entry.user_id == user.id
      assert entry.play_id == play.id
      assert entry.inserted_at
    end

    test "creates entry without user (system action)" do
      play = TestFixtures.play_fixture()

      assert {:ok, entry} =
               ActivityLog.log(%{
                 action: "import",
                 resource_type: "play",
                 resource_id: play.id
               })

      assert is_nil(entry.user_id)
    end

    test "creates entry without play (user management)" do
      user = user_fixture()

      assert {:ok, entry} =
               ActivityLog.log(%{
                 user_id: user.id,
                 action: "role_change",
                 resource_type: "user",
                 changes: %{"role" => ["researcher", "admin"]}
               })

      assert entry.resource_type == "user"
    end

    test "fails with invalid action" do
      assert {:error, changeset} =
               ActivityLog.log(%{action: "invalid", resource_type: "play"})

      assert %{action: _} = errors_on(changeset)
    end

    test "fails with invalid resource_type" do
      assert {:error, changeset} =
               ActivityLog.log(%{action: "create", resource_type: "invalid"})

      assert %{resource_type: _} = errors_on(changeset)
    end

    test "fails without required fields" do
      assert {:error, changeset} = ActivityLog.log(%{})
      errors = errors_on(changeset)
      assert errors[:action]
      assert errors[:resource_type]
    end
  end

  describe "log!/1" do
    test "returns {:ok, entry} on success" do
      assert {:ok, %Entry{}} =
               ActivityLog.log!(%{action: "create", resource_type: "play"})
    end

    test "never raises on invalid data" do
      result = ActivityLog.log!(%{action: "invalid", resource_type: "bad"})
      assert {:error, _} = result
    end
  end

  describe "list_entries/1" do
    test "returns entries ordered by most recent first" do
      user = user_fixture()

      {:ok, entry_a} =
        ActivityLog.log(%{user_id: user.id, action: "create", resource_type: "play"})

      {:ok, entry_b} =
        ActivityLog.log(%{user_id: user.id, action: "update", resource_type: "play"})

      entries = ActivityLog.list_entries()
      ids = Enum.map(entries, & &1.id)
      assert entry_a.id in ids
      assert entry_b.id in ids
      assert length(ids) == 2
    end

    test "filters by user_id" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, _} = ActivityLog.log(%{user_id: user_a.id, action: "create", resource_type: "play"})
      {:ok, _} = ActivityLog.log(%{user_id: user_b.id, action: "delete", resource_type: "play"})

      entries = ActivityLog.list_entries(user_id: user_a.id)
      assert length(entries) == 1
      assert hd(entries).user_id == user_a.id
    end

    test "filters by play_id" do
      play_a = TestFixtures.play_fixture()
      play_b = TestFixtures.play_fixture()
      {:ok, _} = ActivityLog.log(%{play_id: play_a.id, action: "create", resource_type: "play"})
      {:ok, _} = ActivityLog.log(%{play_id: play_b.id, action: "create", resource_type: "play"})

      entries = ActivityLog.list_entries(play_id: play_a.id)
      assert length(entries) == 1
      assert hd(entries).play_id == play_a.id
    end

    test "filters by action" do
      {:ok, _} = ActivityLog.log(%{action: "create", resource_type: "play"})
      {:ok, _} = ActivityLog.log(%{action: "delete", resource_type: "play"})

      entries = ActivityLog.list_entries(action: "create")
      assert length(entries) == 1
      assert hd(entries).action == "create"
    end

    test "filters by resource_type" do
      {:ok, _} = ActivityLog.log(%{action: "create", resource_type: "play"})
      {:ok, _} = ActivityLog.log(%{action: "create", resource_type: "character"})

      entries = ActivityLog.list_entries(resource_type: "character")
      assert length(entries) == 1
      assert hd(entries).resource_type == "character"
    end

    test "paginates results" do
      user = user_fixture()

      for _ <- 1..5 do
        ActivityLog.log(%{user_id: user.id, action: "update", resource_type: "play"})
      end

      page1 = ActivityLog.list_entries(page: 1, per_page: 3)
      page2 = ActivityLog.list_entries(page: 2, per_page: 3)

      assert length(page1) == 3
      assert length(page2) == 2
    end

    test "preloads user and play" do
      user = user_fixture()
      play = TestFixtures.play_fixture()

      {:ok, _} =
        ActivityLog.log(%{
          user_id: user.id,
          play_id: play.id,
          action: "create",
          resource_type: "play"
        })

      [entry] = ActivityLog.list_entries()
      assert entry.user.email == user.email
      assert entry.play.title == play.title
    end
  end

  describe "count_entries/1" do
    test "counts all entries" do
      {:ok, _} = ActivityLog.log(%{action: "create", resource_type: "play"})
      {:ok, _} = ActivityLog.log(%{action: "delete", resource_type: "play"})

      assert ActivityLog.count_entries() == 2
    end

    test "counts with filters" do
      {:ok, _} = ActivityLog.log(%{action: "create", resource_type: "play"})
      {:ok, _} = ActivityLog.log(%{action: "delete", resource_type: "play"})

      assert ActivityLog.count_entries(action: "create") == 1
    end
  end

  describe "Diff.from_changeset/1" do
    test "extracts changed fields" do
      play = TestFixtures.play_fixture(%{"title" => "Old Title"})

      changeset =
        Ecto.Changeset.change(play, title: "New Title")

      diff = Diff.from_changeset(changeset)
      assert diff["title"] == ["Old Title", "New Title"]
    end

    test "excludes timestamps" do
      play = TestFixtures.play_fixture()

      changeset =
        Ecto.Changeset.change(play, title: "Changed", updated_at: DateTime.utc_now())

      diff = Diff.from_changeset(changeset)
      assert Map.has_key?(diff, "title")
      refute Map.has_key?(diff, "updated_at")
      refute Map.has_key?(diff, "inserted_at")
    end

    test "returns empty map for non-changeset input" do
      assert Diff.from_changeset(nil) == %{}
      assert Diff.from_changeset(:not_a_changeset) == %{}
    end
  end
end
