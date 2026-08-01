defmodule Emothe.CatalogueSoftDeleteTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Catalogue

  test "delete_play/1 archives instead of destroying" do
    play = play_fixture(%{"code" => "EMOTHE9101_Archived"})

    assert {:ok, archived} = Catalogue.delete_play(play)
    assert archived.deleted_at

    assert Catalogue.list_plays() == []
    assert Catalogue.list_plays(include_deleted: true) |> Enum.map(& &1.id) == [play.id]
    assert Catalogue.count_plays() == 0
  end

  test "an archived play keeps its code reserved" do
    play = play_fixture(%{"code" => "EMOTHE9102_Reserved"})
    {:ok, _} = Catalogue.delete_play(play)

    assert {:error, changeset} =
             Catalogue.create_play(%{"code" => "EMOTHE9102_Reserved", "title" => "x"})

    assert %{code: _} = errors_on(changeset)
  end

  test "restore_play/1 brings it back" do
    play = play_fixture(%{"code" => "EMOTHE9103_Restored"})
    {:ok, archived} = Catalogue.delete_play(play)

    assert {:ok, restored} = Catalogue.restore_play(archived)
    refute restored.deleted_at
    assert Catalogue.list_plays() |> Enum.map(& &1.id) == [play.id]
  end

  test "purge_play/1 still destroys" do
    play = play_fixture(%{"code" => "EMOTHE9104_Purged"})

    assert {:ok, _} = Catalogue.purge_play(play)
    assert Catalogue.list_plays(include_deleted: true) == []
  end

  test "archived plays are excluded from the complete count" do
    play = play_fixture(%{"code" => "EMOTHE9105_Complete", "is_complete" => true})
    assert Catalogue.count_complete_plays() == 1

    {:ok, _} = Catalogue.delete_play(play)
    assert Catalogue.count_complete_plays() == 0
  end

  test "an archived play is invisible to the public reads" do
    play = play_fixture(%{"code" => "EMOTHE9106_Hidden"})
    {:ok, _} = Catalogue.delete_play(play)

    assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play!(play.id) end
    assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play_by_code!(play.code) end
    assert Catalogue.get_play!(play.id, include_deleted: true).id == play.id
  end
end
