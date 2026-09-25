defmodule Playcode.Export.StaticSiteTest do
  @moduledoc """
  The published site, generated with `StaticSite.generate/1` into a temp
  directory and read back as the files a visitor would get.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Export.StaticSite

  defp generate!(plays, opts \\ []) do
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    opts = Keyword.merge([output_dir: dir, play_codes: Enum.map(plays, & &1.code)], opts)
    assert {:ok, %{output_dir: ^dir}} = StaticSite.generate(opts)
    dir
  end

  defp page(dir, play), do: File.read!(Path.join([dir, "plays", "#{play.code}.html"]))

  defp complete_play(attrs \\ %{}), do: play_fixture(Map.put(attrs, "is_complete", true))

  test "only complete plays are published, and only they are in the catalogue" do
    complete = complete_play(%{"title" => "Obra terminada"})
    draft = play_fixture(%{"title" => "Obra en curso"})

    dir = generate!([complete, draft])

    assert File.exists?(Path.join([dir, "plays", "#{complete.code}.html"]))
    assert File.exists?(Path.join([dir, "plays", "#{complete.code}.xml"]))
    refute File.exists?(Path.join([dir, "plays", "#{draft.code}.html"]))

    index = File.read!(Path.join(dir, "index.html"))
    assert index =~ "Obra terminada"
    refute index =~ "Obra en curso"
  end

  test "with nothing complete to publish, nothing is generated" do
    assert {:error, _} =
             StaticSite.generate(output_dir: "/nonexistent", play_codes: [play_fixture().code])
  end

  test "a play page carries its places and its historical time, in English whatever the locale" do
    play = complete_play(%{"historical_time" => "siglo_xvii"})
    play_place_fixture(play, place_fixture(%{"name" => "Roma"}))

    dir = Gettext.with_locale(PlaycodeWeb.Gettext, "es", fn -> generate!([play]) end)
    html = page(dir, play)

    assert html =~ "Roma"
    assert html =~ "17th century"
    refute html =~ "Siglo XVII"
  end

  test "a play with no places has no places section" do
    play = complete_play()

    refute page(generate!([play]), play) =~ ~s(<p class="places-label">)
  end

  test "a composition date shows as a range, a single year, or the note alone" do
    range =
      complete_play(%{
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "1606; 1607"
      })

    single = complete_play(%{"composition_date_from" => 1614, "composition_date_to" => 1614})
    note_only = complete_play(%{"composition_date_note" => "¿1694? y ¿1605?"})

    dir = generate!([range, single, note_only])

    assert page(dir, range) =~ "1606–1607"
    assert page(dir, range) =~ "1606; 1607"
    assert page(dir, single) =~ "1614"
    refute page(dir, single) =~ "1614–1614"
    assert page(dir, note_only) =~ "¿1694? y ¿1605?"
  end
end
