defmodule EmotheWeb.PlayShowLiveTest do
  use EmotheWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Emothe.TestFixtures

  test "renders navigation panel with metadata and play section links", %{conn: conn} do
    %{play: play, act: act, scene: scene} = TestFixtures.play_with_structure_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#play-sections-panel")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-overview']")
    assert has_element?(view, "#scroll-spy-nav a[href='#div-#{act.id}']")
    assert has_element?(view, "#scroll-spy-nav a[href='#div-#{scene.id}']")
  end

  test "tab navigation switches between text and statistics", %{conn: conn} do
    %{play: play} = TestFixtures.play_with_structure_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#play-tab-text")
    refute has_element?(view, "#play-tab-statistics")

    view
    |> element("#scroll-spy-nav button[phx-value-tab='statistics']")
    |> render_click()

    assert has_element?(view, "#play-tab-statistics")
    refute has_element?(view, "#play-tab-text")

    view
    |> element("#scroll-spy-nav button[phx-value-tab='text']")
    |> render_click()

    assert has_element?(view, "#play-tab-text")
    refute has_element?(view, "#play-tab-statistics")
  end

  test "metadata links appear when metadata exists", %{conn: conn} do
    play = TestFixtures.play_with_metadata_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#scroll-spy-nav a[href='#meta-sources']")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-editors']")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-note-1']")
  end

  test "renders the research metadata panel when the play has a historical time", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "historical_time" => "antiguedad_clasica",
        "historical_time_note" => "First century BC."
      })

    {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#meta-study")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
    # This suite runs in Spanish (see the "no puede estar en blanco" assertion above),
    # so the gettext label renders translated, not as the msgid.
    assert html =~ "Antigüedad clásica"
    assert html =~ "First century BC."
  end

  test "omits the research metadata panel when there is no historical time", %{conn: conn} do
    play = TestFixtures.play_fixture()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    refute has_element?(view, "#meta-study")
    refute has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
  end

  describe "the places panel" do
    defp t(msgid), do: Gettext.gettext(EmotheWeb.Gettext, msgid)

    test "is absent when the play has no places", %{conn: conn} do
      play = Emothe.TestFixtures.play_fixture()
      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

      refute html =~ "meta-places"
    end

    test "lists settings before mentions, with breadcrumb and note", %{conn: conn} do
      play = Emothe.TestFixtures.play_fixture()

      italy =
        Emothe.TestFixtures.place_fixture(%{"name" => "Italia", "type" => "country"})

      roma =
        Emothe.TestFixtures.place_fixture(%{"name" => "Roma", "parent_place_id" => italy.id})

      miseno = Emothe.TestFixtures.place_fixture(%{"name" => "Miseno"})

      Emothe.TestFixtures.play_place_fixture(play, miseno, %{
        "role" => "mentioned",
        "note" => "Named, not staged."
      })

      Emothe.TestFixtures.play_place_fixture(play, roma, %{"role" => "setting"})

      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

      assert html =~ "meta-places"
      assert html =~ "Roma, Italia"
      assert html =~ "Named, not staged."
      assert html =~ t("Places")

      # settings first, whatever order they were linked in
      assert :binary.match(html, "Roma") < :binary.match(html, "Miseno")
    end

    test "a fictional place is marked", %{conn: conn} do
      play = Emothe.TestFixtures.play_fixture()

      atlantis =
        Emothe.TestFixtures.place_fixture(%{
          "name" => "Atlántida",
          "type" => "island",
          "is_fictional" => "true"
        })

      Emothe.TestFixtures.play_place_fixture(play, atlantis)

      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")
      assert html =~ t("Fictional")
    end
  end
end
