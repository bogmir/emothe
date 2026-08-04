defmodule Emothe.PlacesTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Places

  describe "slugify/1" do
    test "strips accents and punctuation" do
      assert Places.slugify("Atlántida") == "atlantida"
      assert Places.slugify("La Cortigiana (1525)") == "la-cortigiana-1525"
      assert Places.slugify("İstanbul") == "istanbul"
    end

    test "a name with no latin characters still yields a usable slug" do
      assert Places.slugify("……") == "place"
    end
  end

  describe "create_place/1" do
    test "requires at least one name" do
      assert {:error, changeset} = Places.create_place(%{"type" => "city", "names" => []})
      assert errors_on(changeset).names != []
    end

    test "derives the slug from the first name when none is given" do
      {:ok, place} =
        Places.create_place(%{
          "type" => "city",
          "names" => %{"0" => %{"name" => "Roma", "language" => "es", "is_preferred" => "true"}}
        })

      assert place.slug == "roma"
    end

    test "a colliding slug is suffixed rather than rejected" do
      _first = place_fixture(%{"name" => "Woods"})
      second = place_fixture(%{"name" => "Woods"})

      assert second.slug == "woods-2"
    end

    test "an explicit slug is respected" do
      place = place_fixture(%{"name" => "Roma", "slug" => "roma-antica"})
      assert place.slug == "roma-antica"
    end
  end

  describe "display_name/2" do
    setup do
      place =
        place_fixture(%{
          "name" => "Roma",
          "names" => [
            %{"name" => "Roma", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Rome", "language" => "en", "is_preferred" => "true"},
            %{"name" => "Roma antica", "language" => "it"}
          ]
        })

      %{place: Places.get_place!(place.id)}
    end

    test "prefers the preferred name in the requested locale", %{place: place} do
      assert Places.display_name(place, "es") == "Roma"
      assert Places.display_name(place, "en") == "Rome"
    end

    test "falls back to a non-preferred name in the locale", %{place: place} do
      assert Places.display_name(place, "it") == "Roma antica"
    end

    test "falls back to any preferred name for an unknown locale", %{place: place} do
      assert Places.display_name(place, "de") in ["Roma", "Rome"]
    end
  end

  describe "update_place/2" do
    test "a place cannot become its own parent" do
      place = place_fixture(%{"name" => "Roma"})

      assert {:error, changeset} =
               Places.update_place(place, %{"parent_place_id" => place.id})

      assert errors_on(changeset).parent_place_id != []
    end

    test "a parent cycle is refused" do
      europe = place_fixture(%{"name" => "Europa", "type" => "continent"})

      italy =
        place_fixture(%{"name" => "Italia", "type" => "country", "parent_place_id" => europe.id})

      assert {:error, changeset} = Places.update_place(europe, %{"parent_place_id" => italy.id})
      assert errors_on(changeset).parent_place_id != []
    end
  end

  describe "delete_place/1" do
    test "a place used by a play is refused with a readable message" do
      play = play_fixture()
      place = place_fixture(%{"name" => "Roma"})
      {:ok, _} = Places.link_place(play.id, place.id, %{})

      assert {:error, changeset} = Places.delete_place(place)
      assert "is still used by one or more plays" in errors_on(changeset).play_places
    end

    test "a place that is a parent is refused" do
      parent = place_fixture(%{"name" => "Italia", "type" => "country"})
      _child = place_fixture(%{"name" => "Roma", "parent_place_id" => parent.id})

      assert {:error, changeset} = Places.delete_place(parent)
      assert "is the parent of other places" in errors_on(changeset).children
    end

    test "an unreferenced place is deleted" do
      place = place_fixture(%{"name" => "Roma"})
      assert {:ok, _} = Places.delete_place(place)
    end
  end

  describe "list_places/1" do
    test "sorts by display name, ignoring accents, and carries the play count" do
      play = play_fixture()
      zaragoza = place_fixture(%{"name" => "Zaragoza"})
      alava = place_fixture(%{"name" => "Álava"})
      {:ok, _} = Places.link_place(play.id, alava.id, %{})

      names = Places.list_places() |> Enum.map(&Places.display_name(&1, "es"))
      assert names == ["Álava", "Zaragoza"]

      counts = Map.new(Places.list_places(), &{&1.id, &1.play_count})
      assert counts[alava.id] == 1
      assert counts[zaragoza.id] == 0
    end
  end

  describe "hierarchy" do
    setup do
      europe = place_fixture(%{"name" => "Europa", "type" => "continent"})

      romania =
        place_fixture(%{"name" => "Rumanía", "type" => "country", "parent_place_id" => europe.id})

      transylvania =
        place_fixture(%{
          "name" => "Transilvania",
          "type" => "region",
          "parent_place_id" => romania.id
        })

      woods =
        place_fixture(%{
          "name" => "Bosque",
          "type" => "forest",
          "parent_place_id" => transylvania.id
        })

      %{europe: europe, woods: woods}
    end

    test "ancestors are returned root first", %{woods: woods, europe: europe} do
      gazetteer = Places.gazetteer()
      ancestors = Places.ancestors(gazetteer[woods.id], gazetteer)

      assert Enum.map(ancestors, & &1.id) |> List.first() == europe.id
      assert length(ancestors) == 3
    end

    test "a breadcrumb reads outward from the place", %{woods: woods} do
      gazetteer = Places.gazetteer()

      assert Places.breadcrumb(gazetteer[woods.id], gazetteer, "es") ==
               "Bosque, Transilvania, Rumanía, Europa"
    end

    test "a place with no parent is its own breadcrumb", %{europe: europe} do
      gazetteer = Places.gazetteer()
      assert Places.breadcrumb(gazetteer[europe.id], gazetteer, "es") == "Europa"
    end
  end

  describe "search_names/2" do
    test "matches a name variant that is not the preferred one" do
      place =
        place_fixture(%{
          "names" => [
            %{"name" => "Constantinopla", "language" => "es", "is_preferred" => "true"},
            %{"name" => "İstanbul", "language" => "tr"}
          ]
        })

      assert [found] = Places.search_names("istanbul")
      assert found.id == place.id
    end

    test "is case insensitive and matches a fragment" do
      place = place_fixture(%{"name" => "Alexandría"})
      assert [found] = Places.search_names("ALEX")
      assert found.id == place.id
    end

    test "an empty term returns nothing" do
      place_fixture(%{"name" => "Roma"})
      assert Places.search_names("") == []
    end

    test "carries the play count, same as list_places/1" do
      play = play_fixture()
      place = place_fixture(%{"name" => "Cartagena"})
      {:ok, _} = Places.link_place(play.id, place.id, %{})

      assert [found] = Places.search_names("cartagena")
      assert found.play_count == 1
    end
  end

  describe "find_or_create_by_slug/1" do
    test "creates a place the first time and reuses it the second" do
      attrs = %{
        "slug" => "roma",
        "type" => "city",
        "names" => [%{"name" => "Roma", "language" => "es", "is_preferred" => "true"}]
      }

      assert {:ok, first, :created} = Places.find_or_create_by_slug(attrs)
      assert {:ok, second, :existing} = Places.find_or_create_by_slug(attrs)
      assert first.id == second.id
    end

    test "never overwrites the existing place" do
      curated = place_fixture(%{"name" => "Roma", "slug" => "roma", "note" => "Curated note"})

      {:ok, found, :existing} =
        Places.find_or_create_by_slug(%{
          "slug" => "roma",
          "type" => "town",
          "note" => "From a stale file",
          "names" => [%{"name" => "Rooma", "language" => "es", "is_preferred" => "true"}]
        })

      assert found.id == curated.id
      assert found.note == "Curated note"
      assert found.type == "city"
      assert Places.display_name(found, "es") == "Roma"
    end
  end

  describe "play links" do
    setup do
      play = play_fixture()
      roma = place_fixture(%{"name" => "Roma"})
      miseno = place_fixture(%{"name" => "Miseno"})
      %{play: play, roma: roma, miseno: miseno}
    end

    test "linking appends at the end", %{play: play, roma: roma, miseno: miseno} do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      {:ok, second} = Places.link_place(play.id, miseno.id, %{"role" => "mentioned"})

      assert first.position == 0
      assert second.position == 1
      assert second.role == "mentioned"
      assert first.origin == "manual"
    end

    test "listing returns them in position order with the place preloaded", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, _} = Places.link_place(play.id, roma.id, %{})
      {:ok, _} = Places.link_place(play.id, miseno.id, %{})

      assert [one, two] = Places.list_play_places(play.id)
      assert Places.display_name(one.place, "es") == "Roma"
      assert Places.display_name(two.place, "es") == "Miseno"
    end

    test "a place cannot be linked to the same play twice", %{play: play, roma: roma} do
      {:ok, _} = Places.link_place(play.id, roma.id, %{})

      assert {:error, changeset} = Places.link_place(play.id, roma.id, %{})
      assert "is already linked to this play" in errors_on(changeset).place_id
    end

    test "role and note are editable", %{play: play, roma: roma} do
      {:ok, link} = Places.link_place(play.id, roma.id, %{})

      {:ok, updated} =
        Places.update_play_place(link, %{"role" => "mentioned", "note" => "Act III only"})

      assert updated.role == "mentioned"
      assert updated.note == "Act III only"
    end

    test "moving a link down swaps it with its neighbour", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      {:ok, _second} = Places.link_place(play.id, miseno.id, %{})

      :ok = Places.move_play_place(first, :down)

      assert Places.list_play_places(play.id)
             |> Enum.map(&Places.display_name(&1.place, "es")) == ["Miseno", "Roma"]
    end

    test "moving the first link up is a no-op", %{play: play, roma: roma} do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      assert :ok = Places.move_play_place(first, :up)
      assert [only] = Places.list_play_places(play.id)
      assert only.position == 0
    end

    test "unlinking leaves the place in the gazetteer", %{play: play, roma: roma} do
      {:ok, link} = Places.link_place(play.id, roma.id, %{})
      {:ok, _} = Places.unlink_place(link)

      assert Places.list_play_places(play.id) == []
      assert Places.get_place!(roma.id)
    end

    test "a link created after an unlink does not collide with a surviving position", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      cartagena = place_fixture(%{"name" => "Cartagena"})
      alejandria = place_fixture(%{"name" => "Alejandria"})

      {:ok, _a} = Places.link_place(play.id, roma.id, %{})
      {:ok, b} = Places.link_place(play.id, miseno.id, %{})
      {:ok, c} = Places.link_place(play.id, cartagena.id, %{})

      {:ok, _} = Places.unlink_place(b)
      {:ok, d} = Places.link_place(play.id, alejandria.id, %{})

      :ok = Places.move_play_place(d, :up)

      assert Places.list_play_places(play.id)
             |> Enum.map(&Places.display_name(&1.place, "es")) == [
               "Roma",
               "Alejandria",
               "Cartagena"
             ]

      refute d.position == c.position
    end

    test "delete_tei_play_places/1 removes only importer-created links", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, _} = Places.link_place(play.id, roma.id, %{"origin" => "tei"})
      {:ok, _} = Places.link_place(play.id, miseno.id, %{"origin" => "manual"})

      {1, nil} = Places.delete_tei_play_places(play.id)

      assert [kept] = Places.list_play_places(play.id)
      assert Places.display_name(kept.place, "es") == "Miseno"
    end
  end
end
