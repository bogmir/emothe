defmodule Emothe.Places.SchemaTest do
  use Emothe.DataCase, async: true

  import Emothe.TestFixtures

  alias Emothe.Places.{Place, PlaceName, PlayPlace}
  alias Emothe.Repo

  defp insert_place(attrs \\ %{}) do
    attrs =
      Map.merge(%{"slug" => "p#{System.unique_integer([:positive])}", "type" => "city"}, attrs)

    {:ok, place} = %Place{} |> Place.changeset(attrs) |> Repo.insert()
    place
  end

  defp insert_name(place, attrs) do
    %PlaceName{}
    |> PlaceName.changeset(Map.put(attrs, "place_id", place.id))
    |> Repo.insert()
  end

  describe "places" do
    test "a slug is unique across the corpus" do
      insert_place(%{"slug" => "sch-roma"})

      assert {:error, changeset} =
               %Place{}
               |> Place.changeset(%{"slug" => "sch-roma", "type" => "city"})
               |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "an unknown type is rejected" do
      changeset = Place.changeset(%Place{}, %{"slug" => "x", "type" => "planet"})
      assert "is invalid" in errors_on(changeset).type
    end

    test "coordinates outside the globe are rejected" do
      changeset =
        Place.changeset(%Place{}, %{
          "slug" => "x",
          "type" => "city",
          "latitude" => "91.0",
          "longitude" => "0.0"
        })

      assert errors_on(changeset).latitude != []
    end

    test "one authority entity cannot become two places" do
      insert_place(%{"authority" => "wikidata", "authority_id" => "Q220"})

      assert {:error, changeset} =
               %Place{}
               |> Place.changeset(%{
                 "slug" => "roma-2",
                 "type" => "city",
                 "authority" => "wikidata",
                 "authority_id" => "Q220"
               })
               |> Repo.insert()

      assert errors_on(changeset).authority_id != []
    end

    test "two places with no authority link are both allowed" do
      insert_place(%{})
      assert %Place{} = insert_place(%{})
    end
  end

  describe "place_names" do
    test "one preferred name per language, and a second in the same language is refused" do
      place = insert_place()

      assert {:ok, _} =
               insert_name(place, %{"name" => "Roma", "language" => "es", "is_preferred" => true})

      assert {:error, changeset} =
               insert_name(place, %{"name" => "Rroma", "language" => "es", "is_preferred" => true})

      assert errors_on(changeset).is_preferred != []
    end

    test "a preferred name in another language is allowed" do
      place = insert_place()

      {:ok, _} =
        insert_name(place, %{"name" => "Roma", "language" => "es", "is_preferred" => true})

      assert {:ok, _} =
               insert_name(place, %{"name" => "Rome", "language" => "en", "is_preferred" => true})
    end

    test "two preferred language-neutral names are refused" do
      place = insert_place()
      {:ok, _} = insert_name(place, %{"name" => "Miseno", "is_preferred" => true})
      assert {:error, _} = insert_name(place, %{"name" => "Misenum", "is_preferred" => true})
    end

    test "deleting a place deletes its names" do
      place = insert_place()
      {:ok, _} = insert_name(place, %{"name" => "Roma", "language" => "es"})
      Repo.delete!(place)
      assert Repo.aggregate(PlaceName, :count, :id) == 0
    end
  end

  describe "play_places" do
    test "a play links a place once" do
      play = play_fixture()
      place = insert_place()
      attrs = %{"play_id" => play.id, "place_id" => place.id}

      {:ok, _} = %PlayPlace{} |> PlayPlace.changeset(attrs) |> Repo.insert()

      assert {:error, changeset} = %PlayPlace{} |> PlayPlace.changeset(attrs) |> Repo.insert()
      assert errors_on(changeset) != %{}
    end

    test "an unknown role is rejected" do
      changeset = PlayPlace.changeset(%PlayPlace{}, %{"role" => "birthplace"})
      assert "is invalid" in errors_on(changeset).role
    end

    test "an unknown origin is rejected" do
      changeset = PlayPlace.changeset(%PlayPlace{}, %{"origin" => "guesswork"})
      assert "is invalid" in errors_on(changeset).origin
    end

    test "a referenced place cannot be deleted" do
      play = play_fixture()
      place = insert_place()

      {:ok, _} =
        %PlayPlace{}
        |> PlayPlace.changeset(%{"play_id" => play.id, "place_id" => place.id})
        |> Repo.insert()

      assert_raise Ecto.ConstraintError, fn -> Repo.delete!(place) end
    end

    test "a place that is a parent cannot be deleted" do
      parent = insert_place(%{"slug" => "sch-italia", "type" => "country"})
      _child = insert_place(%{"parent_place_id" => parent.id})

      assert_raise Ecto.ConstraintError, fn -> Repo.delete!(parent) end
    end
  end
end
