defmodule Emothe.Export.StaticSiteTest do
  use Emothe.DataCase, async: true

  alias Emothe.Export.StaticSite.Renderer

  test "a play page carries its places and its historical time" do
    play =
      Emothe.TestFixtures.play_fixture(%{
        "is_complete" => true,
        "historical_time" => "siglo_xvii"
      })

    place = Emothe.TestFixtures.place_fixture(%{"name" => "Roma"})
    Emothe.TestFixtures.play_place_fixture(play, place)

    play = Emothe.Catalogue.get_play_with_all!(play.id)
    html = Renderer.play_page(play, [], [], nil, [])

    assert html =~ "Roma"
    assert html =~ "17th century"
  end

  test "the static site is English regardless of the ambient locale" do
    play =
      Emothe.TestFixtures.play_fixture(%{
        "is_complete" => true,
        "historical_time" => "siglo_xvii"
      })

    play = Emothe.Catalogue.get_play_with_all!(play.id)

    html =
      Gettext.with_locale(EmotheWeb.Gettext, "es", fn ->
        Renderer.play_page(play, [], [], nil, [])
      end)

    assert html =~ "17th century"
    refute html =~ "Siglo XVII"
  end

  test "a play page carries its composition date range and note" do
    play =
      Emothe.TestFixtures.play_fixture(%{
        "is_complete" => true,
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "1606; 1607"
      })

    play = Emothe.Catalogue.get_play_with_all!(play.id)
    html = Renderer.play_page(play, [], [], nil, [])

    assert html =~ "1606–1607"
    assert html =~ "1606; 1607"
  end

  test "a play page collapses a single-year composition date" do
    play =
      Emothe.TestFixtures.play_fixture(%{
        "is_complete" => true,
        "composition_date_from" => 1614,
        "composition_date_to" => 1614
      })

    play = Emothe.Catalogue.get_play_with_all!(play.id)
    html = Renderer.play_page(play, [], [], nil, [])

    assert html =~ "1614"
    refute html =~ "1614–1614"
  end

  test "a play page carries a composition note with no years" do
    play =
      Emothe.TestFixtures.play_fixture(%{
        "is_complete" => true,
        "composition_date_note" => "¿1694? y ¿1605?"
      })

    play = Emothe.Catalogue.get_play_with_all!(play.id)
    html = Renderer.play_page(play, [], [], nil, [])

    assert html =~ "¿1694? y ¿1605?"
  end

  test "a play page with no places renders no places section" do
    play = Emothe.TestFixtures.play_fixture(%{"is_complete" => true})
    play = Emothe.Catalogue.get_play_with_all!(play.id)

    html = Renderer.play_page(play, [], [], nil, [])

    refute html =~ "places-label"
  end
end
