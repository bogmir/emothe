defmodule Emothe.CatalogueTest do
  use Emothe.DataCase, async: true

  alias Emothe.Catalogue
  alias Emothe.TestFixtures

  test "create_play/1 and update_play/2 persist valid data" do
    {:ok, play} =
      Catalogue.create_play(%{"title" => "La vida", "code" => TestFixtures.unique_code()})

    assert play.title == "La vida"

    {:ok, updated} = Catalogue.update_play(play, %{"author_name" => "Calderón"})
    assert updated.author_name == "Calderón"
  end

  test "create_play/1 rejects invalid data" do
    assert {:error, changeset} = Catalogue.create_play(%{"code" => TestFixtures.unique_code()})
    assert %{title: ["can't be blank"]} = errors_on(changeset)
  end

  test "list_plays/1 supports search by title, author and code" do
    play_a = TestFixtures.play_fixture(%{"title" => "Comedia nueva", "author_name" => "Lope"})
    _play_b = TestFixtures.play_fixture(%{"title" => "Otra obra", "author_name" => "Calderón"})

    assert [found_by_title] = Catalogue.list_plays(search: "Comedia")
    assert found_by_title.id == play_a.id

    assert [found_by_author] = Catalogue.list_plays(search: "Lope")
    assert found_by_author.id == play_a.id

    assert [found_by_code] = Catalogue.list_plays(search: play_a.code)
    assert found_by_code.id == play_a.id
  end

  test "list_plays/1 sorts by code when requested" do
    first = TestFixtures.play_fixture(%{"code" => "AAA-1", "title" => "A"})
    second = TestFixtures.play_fixture(%{"code" => "ZZZ-1", "title" => "Z"})

    [play_one, play_two | _] = Catalogue.list_plays(sort: :code)

    assert play_one.id == first.id
    assert play_two.id == second.id
  end

  test "get_play_by_code_with_all!/1 includes metadata associations" do
    play = TestFixtures.play_with_metadata_fixture()

    loaded = Catalogue.get_play_by_code_with_all!(play.code)

    assert length(loaded.sources) == 1
    assert length(loaded.editors) == 1
    assert length(loaded.editorial_notes) == 1
  end

  test "delete_play/1 removes the play" do
    play = TestFixtures.play_fixture()

    assert {:ok, _} = Catalogue.delete_play(play)
    assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play!(play.id) end
  end

  describe "historical_time" do
    test "accepts a slug from the vocabulary" do
      assert {:ok, play} =
               Emothe.Catalogue.create_play(%{
                 "title" => "A Play",
                 "code" => "HT0001",
                 "historical_time" => "siglo_xvii",
                 "historical_time_note" => "Contemporary. Reign of Philip IV."
               })

      assert play.historical_time == "siglo_xvii"
      assert play.historical_time_note == "Contemporary. Reign of Philip IV."
    end

    test "rejects a slug outside the vocabulary" do
      assert {:error, changeset} =
               Emothe.Catalogue.create_play(%{
                 "title" => "A Play",
                 "code" => "HT0002",
                 "historical_time" => "siglo_xxi"
               })

      assert %{historical_time: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts nil" do
      assert {:ok, play} =
               Emothe.Catalogue.create_play(%{"title" => "A Play", "code" => "HT0003"})

      assert play.historical_time == nil
    end

    test "historical_times/0 lists the nine terms" do
      assert length(Emothe.Catalogue.Play.historical_times()) == 9
      assert "antiguedad_clasica" in Emothe.Catalogue.Play.historical_times()
    end
  end
end
