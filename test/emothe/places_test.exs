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
end
